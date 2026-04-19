import chai from "chai"
import { AbiCoder, toBeHex } from "ethers"
import { ethers } from "hardhat"

const ERROR_STRING_PREFIX = "0x08c379a0"
const PANIC_CODE_PREFIX = "0x4e487b71"
const abiCoder = AbiCoder.defaultAbiCoder()

type DecodedRevert =
	| { kind: "error"; reason: string }
	| { kind: "panic"; code: bigint }
	| { kind: "custom"; selector: string }
	| { kind: "empty" }

function decodeRevertData(data: string): DecodedRevert {
	if (data === "0x") return { kind: "empty" }

	if (data.startsWith(ERROR_STRING_PREFIX)) {
		const encodedReason = `0x${data.slice(ERROR_STRING_PREFIX.length)}`
		const [reason] = abiCoder.decode(["string"], encodedReason)
		return { kind: "error", reason }
	}

	if (data.startsWith(PANIC_CODE_PREFIX)) {
		const encodedCode = `0x${data.slice(PANIC_CODE_PREFIX.length)}`
		const [code] = abiCoder.decode(["uint256"], encodedCode)
		return { kind: "panic", code }
	}

	return { kind: "custom", selector: data.slice(0, 10) }
}

function extractRevertData(error: any): string | undefined {
	const data = error?.data ?? error?.error?.data
	if (typeof data === "string") return data
	if (typeof data?.data === "string") return data.data
	return undefined
}

async function recoverRevertData(error: any): Promise<string | undefined> {
	const directData = extractRevertData(error)
	if (directData) return directData

	const txHash = error?.receipt?.hash ?? error?.transactionHash ?? error?.transaction?.hash
	const tx =
		error?.transaction?.to != null && error?.transaction?.data != null
			? error.transaction
			: txHash
				? await ethers.provider.getTransaction(txHash)
				: null

	if (tx?.to == null || tx?.data == null) return undefined

	try {
		await ethers.provider.call({
			from: tx.from,
			to: tx.to,
			data: tx.data,
			value: tx.value,
		})
		return undefined
	} catch (callError: any) {
		return extractRevertData(callError)
	}
}

function matchesReason(expectedReason: string | RegExp, actualReason: string): boolean {
	return expectedReason instanceof RegExp ? expectedReason.test(actualReason) : actualReason === expectedReason
}

function formatExpectedReason(expectedReason: string | RegExp): string {
	return expectedReason instanceof RegExp ? expectedReason.source : expectedReason
}

chai.Assertion.overwriteMethod("revertedWith", function (_super) {
	return function (this: any, expectedReason: string | RegExp) {
		const expected = formatExpectedReason(expectedReason)
		const negated = this.__flags.negate
		const subject = this._obj

		const derivedPromise = Promise.resolve(subject).then(
			() => {
				throw new chai.AssertionError(
					`Expected transaction to be reverted with reason '${expected}', but it didn't revert`,
				)
			},
			async (error: any) => {
				const revertData = await recoverRevertData(error)

				if (revertData == null) {
					throw error
				}

				const decoded = decodeRevertData(revertData)

				if (decoded.kind === "error") {
					const matched = matchesReason(expectedReason, decoded.reason)
					if (negated ? matched : !matched) {
						throw new chai.AssertionError(
							negated
								? `Expected transaction NOT to be reverted with reason '${expected}', but it was`
								: `Expected transaction to be reverted with reason '${expected}', but it reverted with reason '${decoded.reason}'`,
						)
					}
					return
				}

				if (decoded.kind === "panic") {
					throw new chai.AssertionError(
						`Expected transaction to be reverted with reason '${expected}', but it reverted with panic code ${toBeHex(decoded.code)}`,
					)
				}

				if (decoded.kind === "custom") {
					throw new chai.AssertionError(
						`Expected transaction to be reverted with reason '${expected}', but it reverted with custom error '${decoded.selector}'`,
					)
				}

				throw new chai.AssertionError(
					`Expected transaction to be reverted with reason '${expected}', but it reverted without a reason`,
				)
			},
		)

		this.then = derivedPromise.then.bind(derivedPromise)
		this.catch = derivedPromise.catch.bind(derivedPromise)

		return this
	}
})
