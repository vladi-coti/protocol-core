import { ethers, run } from "hardhat"

import { createRunContext, RunContext } from "./models/RunContext"
import { decimal } from "./utils/Common"
import { toUtf8Bytes } from "ethers"
import { getNetworkGasOptions } from "./utils/testHelpers";

export async function initializeFixture(): Promise<RunContext> {
	let collateral = await run("deploy:stablecoin")
	let diamond = await run("deploy:diamond", {
		logData: false,
		genABI: false,
		reportGas: true,
	})
	let multicall = process.env.DEPLOY_MULTICALL == "true" ? await run("deploy:multicall") : undefined
	console.log("deployed diamond at ", await diamond.getAddress())

	const multiAccount = await run("deploy:multiAccount", {
		symmioAddress: await diamond.getAddress(),
		admin: process.env.ADMIN_PUBLIC_KEY,
	})
	console.log("deployed multiAccount at ", await multiAccount.getAddress())

	const multiAccount2 = await run("deploy:multiAccount", {
		symmioAddress: await diamond.getAddress(),
		admin: process.env.ADMIN_PUBLIC_KEY,
	})
	console.log("deployed multiAccount2 at ", await multiAccount2.getAddress())
	let context = await createRunContext(
		await diamond.getAddress(),
		await collateral.getAddress(),
		await multiAccount.getAddress(),
		await multiAccount2.getAddress(),
		true,
	)
	console.log("created run context")
	const gasOptions = await getNetworkGasOptions()

	await (await context.controlFacet.connect(context.signers.admin).setAdmin(context.signers.admin.getAddress(), gasOptions)).wait()
	console.log("set admin")
	await (await context.controlFacet.connect(context.signers.admin).setCollateral(await context.collateral.getAddress(), gasOptions)).wait()
	console.log("set collateral")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("SYMBOL_MANAGER_ROLE")), gasOptions)
	).wait()
	console.log("grant symbol manager role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("SETTER_ROLE")), gasOptions)
	).wait()
	console.log("grant setter role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("PAUSER_ROLE")), gasOptions)
	).wait()
	console.log("grant pauser role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("PARTY_B_MANAGER_ROLE")), gasOptions)
	).wait()
	console.log("grant party b manager role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("SUSPENDER_ROLE")), gasOptions)
	).wait()
	console.log("grant suspender role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("DISPUTE_ROLE")), gasOptions)
	).wait()
	console.log("grant dispute role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("AFFILIATE_MANAGER_ROLE")), gasOptions)
	).wait()
	console.log("grant affiliate manager role")
	console.log("grant liquidator role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("LIQUIDATOR_ROLE")), gasOptions)
	).wait()
	console.log("grant liquidator role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.liquidator.getAddress(), ethers.keccak256(toUtf8Bytes("LIQUIDATOR_ROLE")), gasOptions)
	).wait()

	console.log("grant liquidator role")
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.addSymbol("BTCUSDT", decimal(5n), decimal(1n, 16), decimal(1n, 16), decimal(100n), 28800, 900, gasOptions)
	).wait()
	console.log("add symbol")
	await (await context.controlFacet.connect(context.signers.admin).setPendingQuotesValidLength(10, gasOptions)).wait()
	await (await context.controlFacet.connect(context.signers.admin).setLiquidatorShare(decimal(1n, 17), gasOptions)).wait()
	console.log("set liquidator share")
	await (await context.controlFacet.connect(context.signers.admin).setLiquidationTimeout(100, gasOptions)).wait()
	console.log("set liquidation timeout")
	await (await context.controlFacet.connect(context.signers.admin).setDeallocateCooldown(120, gasOptions)).wait()
	console.log("set deallocate cooldown")
	await (await context.controlFacet.connect(context.signers.admin).setSettlementCooldown(300, gasOptions)).wait()
	console.log("set settlement cooldown")
	await (await context.controlFacet.connect(context.signers.admin).setDeallocateDebounceTime(120, gasOptions)).wait()
	console.log("set deallocate debounce time")
	await (await context.controlFacet.connect(context.signers.admin).setBalanceLimitPerUser(decimal(10000n), gasOptions)).wait()
	await (await context.controlFacet.connect(context.signers.admin).setForceCloseCooldowns(300, 120, gasOptions)).wait()
	console.log("set force close cooldowns")
	await (await context.controlFacet.connect(context.signers.admin).setForceCancelCooldown(300, gasOptions)).wait()
	console.log("set force cancel cooldown")
	await (await context.controlFacet.connect(context.signers.admin).setForceCancelCloseCooldown(300, gasOptions)).wait()
	console.log("set force cancel close cooldown")
	await (
		await context.controlFacet.connect(context.signers.admin).setInvalidBridgedAmountsPool(context.signers.feeCollector.getAddress(), gasOptions)
	).wait()
	console.log("set invalid bridged amounts pool")
	await (await context.controlFacet.connect(context.signers.admin).registerPartyB(context.signers.hedger.getAddress(), gasOptions)).wait()
	console.log("register party b")
	await (await context.controlFacet.connect(context.signers.admin).registerPartyB(context.signers.hedger2.getAddress(), gasOptions)).wait()
	await (await context.controlFacet.connect(context.signers.admin).registerAffiliate(context.multiAccount, gasOptions)).wait()
	await (await context.controlFacet.connect(context.signers.admin).registerAffiliate(context.multiAccount2!, gasOptions)).wait()
	await (
		await context.controlFacet.connect(context.signers.admin).setFeeCollector(context.multiAccount, context.signers.feeCollector.address, gasOptions)
	).wait()
	await (
		await context.controlFacet
			.connect(context.signers.admin)
			.setFeeCollector(context.multiAccount2!, context.signers.feeCollector2.address, gasOptions)
	).wait()

	return context
}
