import { ethers } from "hardhat"

import {
	AccountManagementFacet,
	AccountFacet,
	BridgeFacet,
	ControlFacet,
	DiamondCutFacet,
	DiamondLoupeFacet,
	ForceActionsFacet,
	FundingRateFacet,
	IForceActionsFacet,
	ISymmio,
	LiquidationFacet,
	LiquidationPositionsFacet,
	LiquidationResolutionFacet,
	PartyAFacet,
	PartyBCloseActionsFacet,
	PartyBGroupActionsFacet,
	PartyBPositionActionsFacet,
	PartyBQuoteActionsFacet,
	RecoveryActionsFacet,
	SettlementFacet,
	ViewFacet,
} from "../../src/types"
import { TestManager } from "./TestManager"
import { Wallet } from "@coti-io/coti-ethers";
import { setupAccounts } from "../utils/accounts";

export class RunContext {
	accountFacet!: AccountFacet
	accountManagementFacet!: AccountManagementFacet
	diamondCutFacet!: DiamondCutFacet
	diamondLoupeFacet!: DiamondLoupeFacet
	symmio!: ISymmio
	partyAFacet!: PartyAFacet
	partyBQuoteActionsFacet!: PartyBQuoteActionsFacet
	partyBGroupActionsFacet!: PartyBGroupActionsFacet
	partyBPositionActionsFacet!: PartyBPositionActionsFacet
	partyBCloseActionsFacet!: PartyBCloseActionsFacet
	bridgeFacet!: BridgeFacet
	viewFacet!: ViewFacet
	liquidationFacet!: LiquidationFacet
	liquidationPositionsFacet!: LiquidationPositionsFacet
	liquidationResolutionFacet!: LiquidationResolutionFacet
	controlFacet!: ControlFacet
	fundingRateFacet!: FundingRateFacet
	settlementFacet!: SettlementFacet
	forceActionsFacet!: ForceActionsFacet
	forceCloseFacet!: IForceActionsFacet
	recoveryActionsFacet!: RecoveryActionsFacet
	signers!: {
		admin: Wallet
		user: Wallet
		user2: Wallet
		liquidator: Wallet
		hedger: Wallet
		hedger2: Wallet
		bridge: Wallet
		bridge2: Wallet
		feeCollector: Wallet
		feeCollector2: Wallet
		others: Wallet[]
	}
	diamond!: string
	multiAccount!: string
	multiAccount2?: string
	collateral: any
	manager!: TestManager
}

export async function createRunContext(
	diamond: string,
	collateral: string,
	multiAccount: string,
	multiAccount2: string | undefined = undefined,
	onlyInitialize: boolean = false,
): Promise<RunContext> {
	let context = new RunContext()

	const signers = await setupAccounts()
	context.signers = {
		admin: signers[0],
		user: signers[1],
		user2: signers[2],
		liquidator: signers[3],
		hedger: signers[4],
		hedger2: signers[5],
		bridge: signers[6],
		bridge2: signers[7],
		feeCollector: signers[8],
		feeCollector2: signers[9],
		others: [signers[10], signers[11]],
	}

	context.diamond = diamond
	context.multiAccount = multiAccount
	context.multiAccount2 = multiAccount2
	context.collateral = await ethers.getContractAt("FakeStablecoin", collateral)
	context.accountFacet = await ethers.getContractAt("AccountFacet", diamond)
	context.accountManagementFacet = await ethers.getContractAt("AccountManagementFacet", diamond)
	context.diamondCutFacet = await ethers.getContractAt("DiamondCutFacet", diamond)
	context.diamondLoupeFacet = await ethers.getContractAt("DiamondLoupeFacet", diamond)
	context.symmio = await ethers.getContractAt("ISymmio", diamond)
	context.partyAFacet = await ethers.getContractAt("PartyAFacet", diamond)
	context.partyBQuoteActionsFacet = await ethers.getContractAt("PartyBQuoteActionsFacet", diamond)
	context.partyBPositionActionsFacet = await ethers.getContractAt("PartyBPositionActionsFacet", diamond)
	context.partyBCloseActionsFacet = await ethers.getContractAt("PartyBCloseActionsFacet", diamond)
	context.partyBGroupActionsFacet = await ethers.getContractAt("PartyBGroupActionsFacet", diamond)
	context.bridgeFacet = await ethers.getContractAt("BridgeFacet", diamond)
	context.viewFacet = await ethers.getContractAt("ViewFacet", diamond)
	context.liquidationFacet = await ethers.getContractAt("LiquidationFacet", diamond)
	context.liquidationPositionsFacet = await ethers.getContractAt("LiquidationPositionsFacet", diamond)
	context.liquidationResolutionFacet = await ethers.getContractAt("LiquidationResolutionFacet", diamond)
	context.controlFacet = await ethers.getContractAt("ControlFacet", diamond)
	context.fundingRateFacet = await ethers.getContractAt("FundingRateFacet", diamond)
	context.settlementFacet = await ethers.getContractAt("SettlementFacet", diamond)
	context.forceActionsFacet = await ethers.getContractAt("ForceActionsFacet", diamond)
	context.forceCloseFacet = await ethers.getContractAt("IForceActionsFacet", diamond)
	context.recoveryActionsFacet = await ethers.getContractAt("RecoveryActionsFacet", diamond)

	context.manager = new TestManager(context, onlyInitialize)
	if (!onlyInitialize) await context.manager.start()

	return context
}
