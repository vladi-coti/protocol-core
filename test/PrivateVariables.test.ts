import hre from "hardhat"
import { expect } from "chai"
import { setupAccounts } from "./utils/accounts"
import { shouldBehaveLikeSendPrivateQuote } from "./SendPrivateQuote.behavior"
import { shouldBehaveLikePrivateParamsTest } from "./PrivateParamsTest.behavior"

const GAS_LIMIT = 12000000

describe("COTI.io v2 Private Variables Integration", function () {
	before(async function () {
		await setupAccounts()
	})

	if (process.env.TEST_MODE == "static") {
		describe("SendPrivateQuote", async function () {
			shouldBehaveLikeSendPrivateQuote()
		})

		describe("PrivateParamsTest", async function () {
			shouldBehaveLikePrivateParamsTest()
		})
	} else if (process.env.TEST_MODE == "fuzz") {
		describe("FuzzTest", async function () {})
	} else if (process.env.TEST_MODE == "pre-upgrade") {
		describe("pre-upgrade test", async function () {})
	} else {
		throw new Error("Invalid TEST_MODE property. should be static or fuzz")
	}
})
