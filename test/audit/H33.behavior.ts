import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { getQuoteQuantity, getTradingFeeForQuoteWithFilledAmount } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-33: trading fees accrue to encryptedFeeCollectorBalances; SymmioFeeDistributor
 * only balanceOf()+withdraw(). If the distributor is the fee collector, claimAllFee
 * sees plaintext 0 and underclaims while encrypted fees remain stuck.
 *
 * Contract collectors also need setSymmioEncryptionAddress(onboarded EOA) so COTI
 * offBoardToUser succeeds during openPosition.
 */
export function shouldBehaveLikeAuditH33(): void {
	describe("fee distributor vs encrypted fee collector accrual", function () {
		it("H-33: distributor as fee collector must claim encrypted fees before withdraw", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(ethers.parseEther("2000"), ethers.parseEther("1000"), ethers.parseEther("500"))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(ethers.parseEther("4000"), ethers.parseEther("4000"))

			const admin = context.signers.admin
			const collector = context.signers.liquidator
			const stakeholder = context.signers.user2
			const encryptionEOA = context.signers.feeCollector
			const symmioShare = ethers.parseEther("0.5")

			const FeeCollector = await ethers.getContractFactory("SymmioFeeDistributor")
			const impl = await FeeCollector.deploy()
			await impl.waitForDeployment()
			const ProxyAdmin = await ethers.getContractFactory(
				"@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin",
			)
			const proxyAdmin = await ProxyAdmin.deploy()
			await proxyAdmin.waitForDeployment()
			const initData = FeeCollector.interface.encodeFunctionData("initialize", [
				await admin.getAddress(),
				context.diamond,
				await admin.getAddress(),
				symmioShare,
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
			const distributorAddr = await feeDistributor.getAddress()

			await runTx(feeDistributor.connect(admin).grantRole(await feeDistributor.COLLECTOR_ROLE(), await collector.getAddress()))
			await runTx(feeDistributor.connect(admin).grantRole(await feeDistributor.SETTER_ROLE(), await admin.getAddress()))
			await runTx(feeDistributor.connect(admin).grantRole(await feeDistributor.MANAGER_ROLE(), await admin.getAddress()))
			await runTx(
				feeDistributor.connect(admin).setStakeholders([
					{ receiver: await stakeholder.getAddress(), share: ethers.parseEther("0.5") },
				]),
			)
			await runTx(feeDistributor.connect(admin).setSymmioEncryptionAddress(await encryptionEOA.getAddress()))

			await runTx(context.controlFacet.connect(admin).setDeallocateCooldown(0))
			await runTx(context.controlFacet.connect(admin).setFeeCollector(context.multiAccount, distributorAddr))

			const quote = await user.sendQuote()
			await hedger.lockQuote(quote)
			const filledAmount = await getQuoteQuantity(context, quote.quoteId)
			const expectedFee = await getTradingFeeForQuoteWithFilledAmount(context, quote.quoteId, filledAmount)
			expect(expectedFee).to.be.gt(0n)

			await hedger.openPosition(quote, limitOpenRequestBuilder().filledAmount(filledAmount).build())

			expect(await context.viewFacet.balanceOf(distributorAddr)).to.equal(0n)

			const stakeholderBefore = await context.collateral.balanceOf(await stakeholder.getAddress())
			await runTx(feeDistributor.connect(collector).claimAllFee())
			const stakeholderAfter = await context.collateral.balanceOf(await stakeholder.getAddress())

			// 50% stakeholder share of trading fee (token decimals == 18 in fixture).
			expect(stakeholderAfter - stakeholderBefore).to.equal(expectedFee / 2n)
			expect(await context.viewFacet.balanceOf(distributorAddr)).to.equal(0n)
		})
	})
}
