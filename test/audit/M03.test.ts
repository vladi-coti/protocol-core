import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM03 } from "./M03.behavior"

describe("Audit review2 M-03", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM03()
})
