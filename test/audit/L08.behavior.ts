import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"
import { EventLog } from "ethers"
import * as fs from "fs"
import * as path from "path"

import { runTx } from "../utils/TxUtils"

/**
 * L-08: claimFee floors each stakeholder share independently, leaves dust in
 * the distributor, and emits FeesClaimed(full amount).
 */
export function shouldBehaveLikeAuditL08(): void {
	describe("fee distributor rounding dust", function () {
		it("L-08 static: claimFee sends remainder to last stakeholder", function () {
			const src = fs.readFileSync(path.join(__dirname, "../../contracts/SymmioFeeDistributor.sol"), "utf8")
			const claim = src.slice(src.indexOf("function claimFee"), src.indexOf("function pause"))
			expect(claim).to.match(/amount - distributed|i == len - 1/)
			expect(claim).to.match(/FeesClaimed/)
		})

		it("L-08: claimFee leaves no dust; FeesClaimed equals sum of transfers", async function () {
			const [owner, admin, collector, manager, symmioReceiver, stakeholder1, stakeholder2] = await ethers.getSigners()

			const MockSymmio = await ethers.getContractFactory("MockSymmio")
			const mockSymmio = await MockSymmio.deploy()
			await mockSymmio.waitForDeployment()

			const MockToken = await ethers.getContractFactory("MockToken")
			const mockToken = await MockToken.deploy("Mock Token", "MTK")
			await mockToken.waitForDeployment()
			await runTx(mockSymmio.setCollateral(await mockToken.getAddress()))

			const FeeCollector = await ethers.getContractFactory("SymmioFeeDistributor")
			const impl = await FeeCollector.deploy()
			await impl.waitForDeployment()
			const ProxyAdmin = await ethers.getContractFactory(
				"@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin",
			)
			const proxyAdmin = await ProxyAdmin.deploy()
			await proxyAdmin.waitForDeployment()
			const initData = FeeCollector.interface.encodeFunctionData("initialize", [
				admin.address,
				await mockSymmio.getAddress(),
				symmioReceiver.address,
				ethers.parseEther("0.5"),
			])
			const TransparentUpgradeableProxy = await ethers.getContractFactory(
				"@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
			)
			const proxy = await TransparentUpgradeableProxy.deploy(
				await impl.getAddress(),
				await proxyAdmin.getAddress(),
				initData,
			)
			await proxy.waitForDeployment()
			const feeDistributor = FeeCollector.attach(await proxy.getAddress()) as any

			await runTx(feeDistributor.connect(admin).grantRole(await feeDistributor.COLLECTOR_ROLE(), collector.address))
			await runTx(feeDistributor.connect(admin).grantRole(await feeDistributor.MANAGER_ROLE(), manager.address))
			await runTx(
				feeDistributor.connect(manager).setStakeholders([
					{ receiver: stakeholder1.address, share: ethers.parseEther("0.3") },
					{ receiver: stakeholder2.address, share: ethers.parseEther("0.2") },
				]),
			)

			const fund = 1000n
			await runTx(mockToken.connect(owner).approve(await mockSymmio.getAddress(), fund))
			await runTx(mockSymmio.connect(owner).depositFor(fund, await feeDistributor.getAddress()))

			const claimAmount = 101n
			const beforeDist = await mockToken.balanceOf(await feeDistributor.getAddress())
			const receipt = await runTx(feeDistributor.connect(collector).claimFee(claimAmount))

			const distributed = receipt.logs
				.filter((log: any): log is EventLog => (log as EventLog).eventName === "FeeDistributed")
				.reduce((sum: bigint, log: EventLog) => sum + BigInt(log.args[1].toString()), 0n)
			const claimed = receipt.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "FeesClaimed")

			expect(claimed).to.not.be.undefined
			expect(BigInt(claimed!.args[0].toString())).to.equal(claimAmount)
			expect(distributed).to.equal(claimAmount)
			expect(await mockToken.balanceOf(await feeDistributor.getAddress())).to.equal(beforeDist)
			expect(
				(await mockToken.balanceOf(symmioReceiver.address)) +
					(await mockToken.balanceOf(stakeholder1.address)) +
					(await mockToken.balanceOf(stakeholder2.address)),
			).to.equal(claimAmount)
		})
	})
}
