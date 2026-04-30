import {readFileSync} from "fs"
import {expect} from "chai"

type AbiInput = {
	name: string
	type: string
	internalType?: string
	components?: AbiInput[]
}

type AbiEntry = {
	type: string
	name: string
	inputs?: AbiInput[]
}

const balanceEventNames = [
	"BalanceChangePartyA",
	"BalanceChangePartyB",
	"ObserverBalanceChangePartyA",
	"ObserverBalanceChangePartyB",
]

function readAbi(path: string): AbiEntry[] {
	const parsed = JSON.parse(readFileSync(path, "utf8"))
	return Array.isArray(parsed) ? parsed : parsed.abi
}

function expectEncryptedBalanceEvents(abi: AbiEntry[]) {
	for (const eventName of balanceEventNames) {
		const event = abi.find((entry) => entry.type === "event" && entry.name === eventName)
		expect(event, `${eventName} missing`).to.not.be.undefined

		const amount = event!.inputs?.find((input) => input.name === "amount")
		expect(amount?.type, `${eventName}.amount type`).to.equal("tuple")
		expect(amount?.internalType, `${eventName}.amount internalType`).to.equal("struct ctUint256")
		expect(amount?.components?.map((component) => component.name), `${eventName}.amount components`).to.deep.equal([
			"ciphertextHigh",
			"ciphertextLow",
		])
	}

	for (const eventName of ["BalanceChangePartyA", "BalanceChangePartyB"]) {
		const staleEvent = abi.find((entry) => {
			if (entry.type !== "event" || entry.name !== eventName) return false
			return entry.inputs?.some((input) => input.name === "amount" && input.type === "uint256")
		})
		expect(staleEvent, `${eventName} still has plaintext uint256 amount`).to.be.undefined
	}
}

function expectSetEncryptionAddress(abi: AbiEntry[]) {
	const functionEntry = abi.find((entry) => entry.type === "function" && entry.name === "setEncryptionAddress")
	expect(functionEntry, "setEncryptionAddress missing").to.not.be.undefined
	expect(functionEntry!.inputs?.map((input) => input.type), "setEncryptionAddress inputs").to.deep.equal(["address"])
}

export function shouldBehaveLikeEventAbi(): void {
	it("Should expose encrypted balance events in canonical ABIs", function () {
		expectEncryptedBalanceEvents(readAbi("artifacts/contracts/interfaces/ISymmio.sol/ISymmio.json"))
		expectEncryptedBalanceEvents(readAbi("abis/symmio.json"))
	})

	it("Should expose setEncryptionAddress in canonical ABIs", function () {
		expectSetEncryptionAddress(readAbi("artifacts/contracts/interfaces/ISymmio.sol/ISymmio.json"))
		expectSetEncryptionAddress(readAbi("abis/symmio.json"))
	})
}
