import { shouldBehaveLikePrivateOpenPosition } from "./PrivateOpenPosition.behavior"

describe("COTI.io v2 Private Variables Integration", function () {
	describe("Private Open Position Functionality", function () {
		shouldBehaveLikePrivateOpenPosition()
	})

	// Import and run other private variable tests
	describe("MpcCore Library", function () {
		require("./MpcCore.test")
	})

	describe("LibPrivateQuote Library", function () {
		require("./LibPrivateQuote.test")
	})
})
