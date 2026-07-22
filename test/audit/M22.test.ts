import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

/**
 * M-22: COTI published packages must be exact registry pins (not floating git branches / link:).
 * Lockfile tracking is intentionally not required; pins in package.json are the policy.
 */
describe("Audit review2 M-22", function () {
	it("M-22 static: package.json pins coti-contracts/ethers; no floating feature-branch refs", function () {
		const pkgPath = path.join(__dirname, "../../package.json")
		const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"))
		const deps = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) }

		expect(deps["@coti-io/coti-contracts"], "coti-contracts must be exact registry version").to.equal("1.3.1")
		expect(deps["@coti-io/coti-ethers"], "coti-ethers must be exact registry version").to.equal("1.0.6")

		const raw = fs.readFileSync(pkgPath, "utf8")
		expect(raw).to.not.match(/#feat\//)
		expect(raw).to.not.match(/#extended-uint-support/)
		expect(raw).to.not.match(/github:.*coti-contracts/)
		expect(raw).to.not.match(/@coti-io\/coti-contracts":\s*"link:/)
	})
})
