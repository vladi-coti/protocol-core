import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditC01 } from "./C01.behavior"

describe("Audit review2 C-01", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditC01()
})
