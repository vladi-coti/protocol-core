// import { shouldBehaveLikePrivateOpenPosition } from "./PrivateOpenPosition.behavior"

import hre from "hardhat"
import { expect } from "chai"

import { setupAccounts } from "./utils/accounts"
// import { PrivateERC20Mock, PrivateERC20WalletMock } from "@coti-io/coti-contracts/typechain-types"
import { itUint, Wallet, ZeroAddress } from "@coti-io/coti-ethers"

const GAS_LIMIT = 12000000

describe("COTI.io v2 Private Variables Integration", function () {
	before(async function () {})

	describe("Private Open Position Functionality", function () {
		// shouldBehaveLikePrivateOpenPosition()
	})

	// Import and run other private variable tests
	describe("MpcCore Library", function () {
		require("./MpcCore.test")
	})

	describe("LibPrivateQuote Library", function () {
		require("./LibPrivateQuote.test")
	})
})
