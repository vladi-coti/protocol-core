import chai from "chai"
import * as https from "node:https"
import { AbiCoder, toBeHex } from "ethers"
import { ethers, network } from "hardhat"

const ERROR_STRING_PREFIX = "0x08c379a0"
const PANIC_CODE_PREFIX = "0x4e487b71"
const COTI_SCAN_RETRY_COUNT = 6
const COTI_SCAN_RETRY_DELAY_MS = 2000
const abiCoder = AbiCoder.defaultAbiCoder()

type DecodedRevert =
	| { kind: "error"; reason: string }
	| { kind: "panic"; code: bigint }
	| { kind: "custom"; selector: string }
	| { kind: "empty" }

function normalizeReason(reason: string): string {
	if (reason.startsWith('execution reverted: "')) {
		return reason.slice('execution reverted: "'.length, -1)
	}
	if (reason.startsWith("execution reverted: ")) {
		return reason.slice("execution reverted: ".length)
	}
	return reason
}

function isGenericReason(reason: string): boolean {
	const normalized = normalizeReason(reason).trim().toLowerCase()
	return (
		normalized === "execution reverted" ||
		normalized.startsWith("execution reverted (") ||
		normalized === "transaction execution reverted" ||
		normalized.startsWith("transaction execution reverted (") ||
		normalized === "call exception" ||
		normalized === "missing revert data" ||
		normalized.startsWith("missing revert data ")
	)
}

function isReceiptStatusRevert(error: any): boolean {
	const status = error?.receipt?.status
	return network.name === "coti-testnet" && (status === 0 || status === 0n)
}

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
	const data = error?.data ?? error?.error?.data ?? error?.info?.error?.data
	if (typeof data === "string") return data
	if (typeof data?.data === "string") return data.data
	return undefined
}

function extractRevertReason(error: any): string | undefined {
	const revertArg = error?.revert?.args?.[0]
	if (typeof revertArg === "string" && revertArg.length > 0) {
		return revertArg
	}

	if (typeof error?.reason === "string" && error.reason.length > 0) {
		const normalized = normalizeReason(error.reason)
		if (!isGenericReason(normalized)) return normalized
	}

	if (typeof error?.shortMessage === "string" && error.shortMessage.length > 0) {
		const normalized = normalizeReason(error.shortMessage)
		if (!isGenericReason(normalized)) return normalized
	}

	const message = error?.info?.error?.message ?? error?.error?.message ?? error?.message
	if (typeof message === "string" && message.length > 0) {
		const normalized = normalizeReason(message)
		if (!isGenericReason(normalized)) return normalized
	}

	return undefined
}

function hasReplayableData(tx: any): boolean {
	return tx?.to != null && typeof tx?.data === "string" && tx.data.startsWith("0x") && tx.data.length >= 10
}

async function getReplayTransaction(error: any): Promise<any | null> {
	const directTx = error?.transaction
	if (hasReplayableData(directTx)) return directTx

	const txHash = error?.receipt?.hash ?? error?.transactionHash ?? error?.transaction?.hash
	if (!txHash) return null

	const fetchedTx = await ethers.provider.getTransaction(txHash)
	return hasReplayableData(fetchedTx) ? fetchedTx : null
}

async function recoverRevertData(error: any): Promise<string | undefined> {
	const directData = extractRevertData(error)
	if (directData) return directData

	const tx = await getReplayTransaction(error)
	if (tx == null) return undefined

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

async function recoverRevertReason(error: any): Promise<string | undefined> {
	const directReason = extractRevertReason(error)
	if (directReason) return directReason

	const tx = await getReplayTransaction(error)
	if (tx == null) return undefined

	try {
		await ethers.provider.call({
			from: tx.from,
			to: tx.to,
			data: tx.data,
			value: tx.value,
		})
		return undefined
	} catch (callError: any) {
		return extractRevertReason(callError)
	}
}

async function recoverExplorerRevertReason(error: any): Promise<string | undefined> {
	if (network.name !== "coti-testnet") return undefined

	const txHash = error?.receipt?.hash ?? error?.transactionHash ?? error?.transaction?.hash
	if (typeof txHash !== "string" || txHash.length === 0) return undefined

	for (let attempt = 0; attempt < COTI_SCAN_RETRY_COUNT; attempt++) {
		try {
			const payload: any = await new Promise((resolve, reject) => {
				const request = https.get(`https://testnet.cotiscan.io/api/v2/transactions/${txHash}`, (response) => {
					if ((response.statusCode ?? 500) >= 400) {
						resolve(undefined)
						return
					}

					let body = ""
					response.setEncoding("utf8")
					response.on("data", (chunk) => {
						body += chunk
					})
					response.on("end", () => {
						try {
							resolve(JSON.parse(body))
						} catch (parseError) {
							reject(parseError)
						}
					})
				})

				request.on("error", reject)
			})

			const parameters = payload?.revert_reason?.parameters
			if (Array.isArray(parameters)) {
				const reason =
					parameters.find((parameter: any) => parameter?.name === "reason")?.value ??
					parameters[0]?.value

				if (typeof reason === "string" && reason.length > 0) {
					const normalized = normalizeReason(reason)
					if (!isGenericReason(normalized)) return normalized
				}
			}
		} catch {
			// Retry below in case Blockscout has not indexed the revert reason yet.
		}

		if (attempt < COTI_SCAN_RETRY_COUNT - 1) {
			await new Promise((resolve) => setTimeout(resolve, COTI_SCAN_RETRY_DELAY_MS))
		}
	}

	return undefined
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

		const assertRevert = async (error: any) => {
			const revertData = await recoverRevertData(error)

			if (revertData != null) {
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
			}

			const recoveredReason = await recoverRevertReason(error)
			const explorerReason = recoveredReason == null ? await recoverExplorerRevertReason(error) : undefined
			const finalReason = recoveredReason ?? explorerReason
			if (finalReason == null) {
				if (isReceiptStatusRevert(error)) {
					if (negated) {
						throw new chai.AssertionError(
							`Expected transaction NOT to be reverted with reason '${expected}', but it reverted without a decoded reason`,
						)
					}
					return
				}
				throw error
			}

			const matched = matchesReason(expectedReason, finalReason)
			if (negated ? matched : !matched) {
				throw new chai.AssertionError(
					negated
						? `Expected transaction NOT to be reverted with reason '${expected}', but it was`
						: `Expected transaction to be reverted with reason '${expected}', but it reverted with reason '${finalReason}'`,
				)
			}
		}

		const derivedPromise = Promise.resolve(subject).then(
			async (result: any) => {
				if (typeof result?.wait === "function") {
					try {
						await result.wait()
					} catch (error: any) {
						await assertRevert(error)
						return
					}
				}
				throw new chai.AssertionError(
					`Expected transaction to be reverted with reason '${expected}', but it didn't revert`,
				)
			},
			assertRevert,
		)

		this.then = derivedPromise.then.bind(derivedPromise)
		this.catch = derivedPromise.catch.bind(derivedPromise)

		return this
	}
})

chai.Assertion.overwriteProperty("reverted", function (_super) {
	return function (this: any) {
		const negated = this.__flags.negate
		const subject = this._obj

		const derivedPromise = Promise.resolve(subject).then(
			async (result: any) => {
				if (typeof result?.wait === "function") {
					try {
						await result.wait()
						if (!negated) {
							throw new chai.AssertionError("Expected transaction to be reverted, but it didn't revert")
						}
					} catch (error: any) {
						if (error instanceof chai.AssertionError) throw error
						if (isReceiptStatusRevert(error)) {
							if (negated) {
								throw new chai.AssertionError("Expected transaction NOT to be reverted, but it reverted")
							}
							return
						}
						if (negated) {
							throw error
						}
						return
					}
					return
				}

				if (!negated) {
					throw new chai.AssertionError("Expected transaction to be reverted, but it didn't revert")
				}
			},
			(error: any) => {
				if (isReceiptStatusRevert(error)) {
					if (negated) {
						throw new chai.AssertionError("Expected transaction NOT to be reverted, but it reverted")
					}
					return
				}

				if (negated) {
					throw error
				}

				return _super.apply(this)
			},
		)

		this.then = derivedPromise.then.bind(derivedPromise)
		this.catch = derivedPromise.catch.bind(derivedPromise)

		return this
	}
})
