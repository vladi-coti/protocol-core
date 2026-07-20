import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"

import { getNetworkGasOptions } from "../utils/testHelpers"

/**
 * L-09: auditor claimed tryAggregate / aggregate3 discard return data because
 * `Result memory result = returnData[i]` looks like a copy. In Solidity ≥0.8,
 * memory→memory struct assignment is a reference — field writes go through.
 */
export function shouldBehaveLikeAuditL09(): void {
	describe("multicall return data", function () {
		it("L-09: tryAggregate returns successful subcall returnData", async function () {
			const Factory = await ethers.getContractFactory("Multicall3")
			const multicall = await Factory.deploy(getNetworkGasOptions())
			await multicall.waitForDeployment()
			const addr = await multicall.getAddress()
			const callData = multicall.interface.encodeFunctionData("getChainId")
			const results = await multicall.tryAggregate.staticCall(true, [{ target: addr, callData }])
			expect(results.length).to.equal(1)
			expect(results[0].success).to.equal(true)
			expect(results[0].returnData).to.not.equal("0x")
			const [chainId] = multicall.interface.decodeFunctionResult("getChainId", results[0].returnData)
			expect(chainId).to.equal((await ethers.provider.getNetwork()).chainId)
		})

		it("L-09: aggregate3 returns successful subcall returnData", async function () {
			const Factory = await ethers.getContractFactory("Multicall3")
			const multicall = await Factory.deploy(getNetworkGasOptions())
			await multicall.waitForDeployment()
			const addr = await multicall.getAddress()
			const callData = multicall.interface.encodeFunctionData("getBlockNumber")
			const results = await multicall.aggregate3.staticCall([{ target: addr, allowFailure: false, callData }])
			expect(results.length).to.equal(1)
			expect(results[0].success).to.equal(true)
			expect(results[0].returnData).to.not.equal("0x")
			const [blockNumber] = multicall.interface.decodeFunctionResult("getBlockNumber", results[0].returnData)
			expect(blockNumber).to.be.a("bigint")
			expect(blockNumber).to.be.gt(0n)
		})
	})
}
