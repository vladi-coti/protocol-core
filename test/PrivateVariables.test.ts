import hre from "hardhat"
import { expect } from "chai"
import { setupAccounts } from "./utils/accounts"
// import { PrivateERC20Mock, PrivateERC20WalletMock } from "@coti-io/coti-contracts/typechain-types"
import { itUint, Wallet, ZeroAddress } from "@coti-io/coti-ethers"
import { shouldBehaveLikePrivateOpenPosition } from "./PrivateOpenPosition.behavior"

const GAS_LIMIT = 12000000

describe("COTI.io v2 Private Variables Integration", function () {
	before(async function () {})

	if (process.env.TEST_MODE == "static") {
		describe("PrivateOpenPosition", async function () {
			shouldBehaveLikePrivateOpenPosition()
		})

		describe("MpcCore Library", function () {
			require("./MpcCore.test")
		})

		describe("LibPrivateQuote Library", function () {
			require("./LibPrivateQuote.test")
		})
	} else if (process.env.TEST_MODE == "fuzz") {
		describe("FuzzTest", async function () {})
	} else if (process.env.TEST_MODE == "pre-upgrade") {
		describe("pre-upgrade test", async function () {})
	} else {
		throw new Error("Invalid TEST_MODE property. should be static or fuzz")
	}
})
