import { expect } from "chai"
import { ethers } from "hardhat"
import { ContractFactory, EventLog, Wallet } from "@coti-io/coti-ethers"
import { initializeFixture } from "./Initialize.fixture"
import { RunContext } from "./models/RunContext"
import { User } from "./models/User"
import { Hedger } from "./models/Hedger"
import { decimal } from "./utils/Common"
import { getDummySingleUpnlAndPriceSig } from "./utils/SignatureUtils"
import { loadFixtureCompatible } from "./utils/testHelpers"
import { setupAccounts } from "./utils/accounts"
import { PartyAFacet } from "../src/types"
import { limitQuoteRequestBuilder } from "./models/requestModels/QuoteRequest"

export function shouldBehaveLikePrivateParamsTest(): void {
	let context: RunContext
	let privateUser: User
	let privateUser2: User
	let hedger: Hedger
	let userWallet: Wallet
	let user2Wallet: Wallet

	describe("Direct Call Tests", function () {
		let privatePartyAFacet: PartyAFacet
		beforeEach(async function () {
			// deploy the contract directly
			const partyAFacetFactory = await ethers.getContractFactory("PartyAFacet")
			privatePartyAFacet = await partyAFacetFactory.deploy({ gasLimit: 12000000 })
			await privatePartyAFacet.waitForDeployment()
			console.log(`deployed privatePartyAFacet at ${await privatePartyAFacet.getAddress()}`)

			// Setup private wallets using Coti accounts
			const accounts = await setupAccounts()
			userWallet = accounts[1]
			const wallet2 = accounts[2]

			const partyBWhiteList = [wallet2.address]
		})

		it("Should emit PrivateParamsTest event when called directly", async function () {
			const request = limitQuoteRequestBuilder().build()
			const contractAddress = await privatePartyAFacet.getAddress()
			const selector = privatePartyAFacet.interface.getFunction("privateParamsTest").selector

			const basicParams = {
				partyBsWhiteList: request.partyBWhiteList,
				symbolId: request.symbolId,
				positionType: request.positionType,
				orderType: request.orderType,
				maxFundingRate: request.maxFundingRate,
				deadline: await request.deadline,
				affiliate: request.affiliate,
			}

			const encryptedPrice = await userWallet.encryptUint256(BigInt(request.price), contractAddress, selector)
			const encryptedQuantity = await userWallet.encryptUint256(BigInt(request.quantity), contractAddress, selector)
			const encryptedCva = await userWallet.encryptUint256(BigInt(request.cva), contractAddress, selector)
			const encryptedLf = await userWallet.encryptUint256(BigInt(request.lf), contractAddress, selector)
			const encryptedPartyAmm = await userWallet.encryptUint256(BigInt(request.partyAmm), contractAddress, selector)
			const encryptedPartyBmm = await userWallet.encryptUint256(BigInt(request.partyBmm), contractAddress, selector)

			const encryptedParams = {
				encryptedPrice: encryptedPrice,
				encryptedQuantity: encryptedQuantity,
				encryptedCva: encryptedCva,
				encryptedLf: encryptedLf,
				encryptedPartyAmm: encryptedPartyAmm,
				encryptedPartyBmm: encryptedPartyBmm,
			}

			const connectedContract = privatePartyAFacet.connect(userWallet)

			const tx = await connectedContract.privateParamsTest(basicParams, encryptedParams, await request.upnlSig, {
				gasLimit: 12000000,
			})
			const receipt = await tx.wait()
			if (receipt?.logs) {
				const privateParamsTestEvent = receipt.logs.find((log: any): log is EventLog => {
					return (log as EventLog).eventName === "PrivateParamsTest"
				})
				console.log(privateParamsTestEvent?.args[0])
			}
		})
	})

	describe("Proxy Call Tests", function () {
		let proxy: any
		beforeEach(async function () {
			// Setup private wallets using Coti accounts
			const accounts = await setupAccounts()
			userWallet = accounts[1]

			// deploy the contract using a transparent proxy
			const { contract } = await deployProxy(ethers, userWallet)
			proxy = contract
		})

		it("Should work through proxy call", async function () {
			const request = limitQuoteRequestBuilder().build()

			const contractAddress = await proxy.getAddress()
			const selector = proxy.interface.getFunction("privateParamsTest").selector

			const basicParams = {
				partyBsWhiteList: request.partyBWhiteList,
				symbolId: request.symbolId,
				positionType: request.positionType,
				orderType: request.orderType,
				maxFundingRate: request.maxFundingRate,
				deadline: await request.deadline,
				affiliate: request.affiliate,
			}

			const encryptedPrice = await userWallet.encryptUint256(BigInt(request.price), contractAddress, selector)
			const encryptedQuantity = await userWallet.encryptUint256(BigInt(request.quantity), contractAddress, selector)
			const encryptedCva = await userWallet.encryptUint256(BigInt(request.cva), contractAddress, selector)
			const encryptedLf = await userWallet.encryptUint256(BigInt(request.lf), contractAddress, selector)
			const encryptedPartyAmm = await userWallet.encryptUint256(BigInt(request.partyAmm), contractAddress, selector)
			const encryptedPartyBmm = await userWallet.encryptUint256(BigInt(request.partyBmm), contractAddress, selector)

			const encryptedParams = {
				encryptedPrice: encryptedPrice,
				encryptedQuantity: encryptedQuantity,
				encryptedCva: encryptedCva,
				encryptedLf: encryptedLf,
				encryptedPartyAmm: encryptedPartyAmm,
				encryptedPartyBmm: encryptedPartyBmm,
			}

			// Call through the proxy
			const connectedContract = proxy.connect(userWallet)

			const tx = await connectedContract.privateParamsTest(basicParams, encryptedParams, await request.upnlSig, {
				gasLimit: 12000000,
			})
			const receipt = await tx.wait()
			if (receipt?.logs) {
				const privateParamsTestEvent = receipt.logs.find((log: any): log is EventLog => {
					return (log as EventLog).eventName === "PrivateParamsTest"
				})
				console.log(privateParamsTestEvent?.args[0])
			}
		})
	})

	describe("Direct Call Tests - Plaintext", function () {
		let privatePartyAFacet: PartyAFacet
		beforeEach(async function () {
			// deploy the contract directly
			const partyAFacetFactory = await ethers.getContractFactory("PartyAFacet")
			privatePartyAFacet = await partyAFacetFactory.deploy({ gasLimit: 12000000 })
			await privatePartyAFacet.waitForDeployment()
			console.log(`deployed privatePartyAFacet at ${await privatePartyAFacet.getAddress()}`)

			// Setup private wallets using Coti accounts
			const accounts = await setupAccounts()
			userWallet = accounts[1]
			const wallet2 = accounts[2]

			const partyBWhiteList = [wallet2.address]
		})

		it("Should emit PrivateParamsTest event when called directly", async function () {
			const request = limitQuoteRequestBuilder().build()

			const basicParams = {
				partyBsWhiteList: request.partyBWhiteList,
				symbolId: request.symbolId,
				positionType: request.positionType,
				orderType: request.orderType,
				maxFundingRate: request.maxFundingRate,
				deadline: await request.deadline,
				affiliate: request.affiliate,
			}

			const encryptedParams = {
				encryptedPrice: BigInt(request.price)	,
				encryptedQuantity: BigInt(request.quantity),
				encryptedCva: BigInt(request.cva),
				encryptedLf: BigInt(request.lf),
				encryptedPartyAmm: BigInt(request.partyAmm),
				encryptedPartyBmm: BigInt(request.partyBmm),
			}

			const connectedContract = privatePartyAFacet.connect(userWallet)

			const tx = await connectedContract.privateParamsTestPlaintext(basicParams, encryptedParams, await request.upnlSig, {
				gasLimit: 12000000,
			})
			const receipt = await tx.wait()
			if (receipt?.logs) {
				const privateParamsTestEvent = receipt.logs.find((log: any): log is EventLog => {
					return (log as EventLog).eventName === "PrivateParamsTest"
				})
				console.log(privateParamsTestEvent?.args[0])
			}
		})
	})

	describe("Proxy Call Tests - Plaintext", function () {
		let proxy: any
		beforeEach(async function () {
			// Setup private wallets using Coti accounts
			const accounts = await setupAccounts()
			userWallet = accounts[1]

			// deploy the contract using a transparent proxy
			const { contract } = await deployProxy(ethers, userWallet)
			proxy = contract

			const partyBWhiteList = [accounts[2].address]
		})

		it("Should work through proxy call", async function () {
			const request = limitQuoteRequestBuilder().build()

			const basicParams = {
				partyBsWhiteList: request.partyBWhiteList,
				symbolId: request.symbolId,
				positionType: request.positionType,
				orderType: request.orderType,
				maxFundingRate: request.maxFundingRate,
				deadline: await request.deadline,
				affiliate: request.affiliate,
			}

			const encryptedParams = {
				encryptedPrice: BigInt(request.price),
				encryptedQuantity: BigInt(request.quantity),
				encryptedCva: BigInt(request.cva),
				encryptedLf: BigInt(request.lf),
				encryptedPartyAmm: BigInt(request.partyAmm),
				encryptedPartyBmm: BigInt(request.partyBmm),
			}

			// Call through the proxy
			const connectedContract = proxy.connect(userWallet)

			const tx = await connectedContract.privateParamsTestPlaintext(basicParams, encryptedParams, await request.upnlSig, {
				gasLimit: 12000000,
			})
			const receipt = await tx.wait()
			if (receipt?.logs) {
				const privateParamsTestEvent = receipt.logs.find((log: any): log is EventLog => {
					return (log as EventLog).eventName === "PrivateParamsTest"
				})
				console.log(privateParamsTestEvent?.args[0])
			}
		})
	})
}

async function deployProxy(ethers: any, deployer: any) {
	// Deploy transparent proxy manually
	const Factory = await ethers.getContractFactory("PrivatePartyAFacet")

	const gasOptions = {
		gasLimit: 5000000,
		gasPrice: 1000000000,
	}

	// 1. Deploy the implementation contract
	console.log("Deploying implementation...")
	const implementation = await Factory.deploy(gasOptions)
	await implementation.waitForDeployment()
	const implementationAddress = await implementation.getAddress()
	console.log("Implementation deployed to:", implementationAddress)

	// 2. Deploy ProxyAdmin using artifacts
	console.log("Deploying ProxyAdmin...")
	const proxyAdminArtifact = require("@openzeppelin/contracts/build/contracts/ProxyAdmin.json")
	const ProxyAdminFactory = new ethers.ContractFactory(proxyAdminArtifact.abi, proxyAdminArtifact.bytecode, deployer)
	const proxyAdmin = await ProxyAdminFactory.deploy(gasOptions)
	await proxyAdmin.waitForDeployment()
	const proxyAdminAddress = await proxyAdmin.getAddress()
	console.log("ProxyAdmin deployed to:", proxyAdminAddress)

	// 3. Deploy TransparentUpgradeableProxy using artifacts
	console.log("Deploying TransparentUpgradeableProxy...")
	const transparentProxyArtifact = require("@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json")
	const TransparentUpgradeableProxyFactory = new ethers.ContractFactory(transparentProxyArtifact.abi, transparentProxyArtifact.bytecode, deployer)
	const proxy = await TransparentUpgradeableProxyFactory.deploy(implementationAddress, proxyAdminAddress, "0x", gasOptions)
	await proxy.waitForDeployment()
	const proxyAddress = await proxy.getAddress()
	console.log("TransparentUpgradeableProxy deployed to:", proxyAddress)

	// 4. Attach the implementation ABI to the proxy address
	const proxyContract = Factory.attach(proxyAddress)

	return { contract: proxyContract, implementationAddress, proxyAdminAddress, proxyAddress }
}
