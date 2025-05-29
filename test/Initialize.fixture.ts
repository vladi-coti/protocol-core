import { ethers, run } from "hardhat"

import { createRunContext, RunContext } from "./models/RunContext"
import { decimal } from "./utils/Common"
import { toUtf8Bytes } from "ethers"

// Helper function to get gas options for COTI testnet
function getGasOptions() {
	const network = process.env.HARDHAT_NETWORK || "hardhat"
	if (network === "coti-testnet") {
		return {
			gasLimit: 2000000,
			gasPrice: 1000000000, // 1 gwei
		}
	}
	return {} // Use default gas estimation for other networks
}

export async function initializeFixture(): Promise<RunContext> {
	let collateral = await run("deploy:stablecoin")
	let diamond = await run("deploy:diamond", {
		logData: false,
		genABI: false,
		reportGas: true,
	})
	let multicall = process.env.DEPLOY_MULTICALL == "true" ? await run("deploy:multicall") : undefined

	const multiAccount = await run("deploy:multiAccount", {
		symmioAddress: await diamond.getAddress(),
		admin: process.env.ADMIN_PUBLIC_KEY,
	})
	const multiAccount2 = await run("deploy:multiAccount", {
		symmioAddress: await diamond.getAddress(),
		admin: process.env.ADMIN_PUBLIC_KEY,
	})

	let context = await createRunContext(
		await diamond.getAddress(),
		await collateral.getAddress(),
		await multiAccount.getAddress(),
		await multiAccount2.getAddress(),
		true,
	)

	const gasOptions = getGasOptions()

	await context.controlFacet.connect(context.signers.admin).setAdmin(context.signers.admin.getAddress(), gasOptions)

	await context.controlFacet.connect(context.signers.admin).setCollateral(await context.collateral.getAddress(), gasOptions)

	await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("SYMBOL_MANAGER_ROLE")), gasOptions)
	await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("SETTER_ROLE")), gasOptions)
	await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("PAUSER_ROLE")), gasOptions)
	await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("PARTY_B_MANAGER_ROLE")), gasOptions)
	await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("SUSPENDER_ROLE")), gasOptions)
	await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("DISPUTE_ROLE")), gasOptions)
	context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("AFFILIATE_MANAGER_ROLE")), gasOptions),
		await context.controlFacet
			.connect(context.signers.admin)
			.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("LIQUIDATOR_ROLE")), gasOptions)
	await context.controlFacet
		.connect(context.signers.admin)
		.grantRole(context.signers.liquidator.getAddress(), ethers.keccak256(toUtf8Bytes("LIQUIDATOR_ROLE")), gasOptions)

	await context.controlFacet
		.connect(context.signers.admin)
		.addSymbol("BTCUSDT", decimal(5n), decimal(1n, 16), decimal(1n, 16), decimal(100n), 28800, 900, gasOptions)

	await context.controlFacet.connect(context.signers.admin).setPendingQuotesValidLength(10, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setLiquidatorShare(decimal(1n, 17), gasOptions)
	await context.controlFacet.connect(context.signers.admin).setLiquidationTimeout(100, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setDeallocateCooldown(120, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setSettlementCooldown(300, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setDeallocateDebounceTime(120, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setBalanceLimitPerUser(decimal(10000n), gasOptions)
	await context.controlFacet.connect(context.signers.admin).setForceCloseCooldowns(300, 120, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setForceCancelCooldown(300, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setForceCancelCloseCooldown(300, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setInvalidBridgedAmountsPool(context.signers.feeCollector.getAddress(), gasOptions)
	await context.controlFacet.connect(context.signers.admin).registerPartyB(context.signers.hedger.getAddress(), gasOptions)
	await context.controlFacet.connect(context.signers.admin).registerPartyB(context.signers.hedger2.getAddress(), gasOptions)
	await context.controlFacet.connect(context.signers.admin).registerAffiliate(context.multiAccount, gasOptions)
	await context.controlFacet.connect(context.signers.admin).registerAffiliate(context.multiAccount2!, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setFeeCollector(context.multiAccount, context.signers.feeCollector.address, gasOptions)
	await context.controlFacet.connect(context.signers.admin).setFeeCollector(context.multiAccount2!, context.signers.feeCollector2.address, gasOptions)

	return context
}
