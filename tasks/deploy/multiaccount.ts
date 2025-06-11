import { task, types } from "hardhat/config"
import { ContractFactory } from "ethers"
import { HardhatUpgrades } from "@openzeppelin/hardhat-upgrades"
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers"
import { readData, writeData } from "../utils/fs"
import { DEPLOYMENT_LOG_FILE } from "./constants"

task("deploy:multiAccount", "Deploys the MultiAccount")
	.addParam("symmioAddress", "The address of the Symmio contract")
	.addParam("admin", "The admin address")
	.addOptionalParam("logData", "Write the deployed addresses to a data file", true, types.boolean)
	.setAction(async ({ symmioAddress, admin, logData }, { ethers, upgrades, run }) => {
		console.log("Running deploy:multiAccount")

		const [deployer] = await ethers.getSigners()

		console.log("Deploying contracts with the account:", deployer.address)

		const SymmioPartyA = await ethers.getContractFactory("SymmioPartyA")

		const network = await ethers.provider.getNetwork()
		const isCotiTestnet = network.chainId === 7082400n

		const { contract, proxyAddress, proxyAdminAddress, implementationAddress } = await (isCotiTestnet
			? deployMultiAccountManually(ethers, admin, symmioAddress, deployer, SymmioPartyA)
			: deployMultiAccountUpgradeable(ethers, upgrades, admin, symmioAddress, SymmioPartyA))

		if (logData) {
			// Read existing data
			let deployedData = []
			try {
				deployedData = readData(DEPLOYMENT_LOG_FILE)
			} catch (err) {
				console.error(`Could not read existing JSON file: ${err}`)
			}

			// Append new data
			deployedData.push(
				{
					name: "MultiAccountProxy",
					address: proxyAddress,
					constructorArguments: [admin, symmioAddress, SymmioPartyA.bytecode],
				},
				{
					name: "MultiAccountAdmin",
					address: proxyAdminAddress,
					constructorArguments: [],
				},
				{
					name: "MultiAccountImplementation",
					address: implementationAddress,
					constructorArguments: [],
				},
			)

			// Write updated data back to JSON file
			writeData(DEPLOYMENT_LOG_FILE, deployedData)
			console.log("Deployed addresses written to JSON file")
		}

		return contract
	})

async function deployMultiAccountUpgradeable(
	ethers: any,
	upgrades: HardhatUpgrades,
	admin: string,
	symmioAddress: string,
	SymmioPartyA: ContractFactory,
) {
	// Deploy MultiAccount as upgradeable
	const Factory = await ethers.getContractFactory("MultiAccount")
	console.log(admin, symmioAddress)
	const contract = await upgrades.deployProxy(Factory, [admin, symmioAddress, SymmioPartyA.bytecode], { initializer: "initialize" })
	await contract.waitForDeployment()

	const addresses = {
		proxyAddress: await contract.getAddress(),
		proxyAdminAddress: await upgrades.erc1967.getAdminAddress(await contract.getAddress()),
		implementationAddress: await upgrades.erc1967.getImplementationAddress(await contract.getAddress()),
	}
	return { contract, ...addresses }
}

async function deployMultiAccountManually(
	ethers: any,
	admin: string,
	symmioAddress: string,
	deployer: HardhatEthersSigner,
	SymmioPartyA: ContractFactory,
) {
	// Deploy transparent proxy manually
	const Factory = await ethers.getContractFactory("MultiAccount")
	console.log(admin, symmioAddress)

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

	// 3. Encode the initializer call
	const initializeData = implementation.interface.encodeFunctionData("initialize", [admin, symmioAddress, SymmioPartyA.bytecode])

	// 4. Deploy TransparentUpgradeableProxy using artifacts
	console.log("Deploying TransparentUpgradeableProxy...")
	const transparentProxyArtifact = require("@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json")
	const TransparentUpgradeableProxyFactory = new ethers.ContractFactory(transparentProxyArtifact.abi, transparentProxyArtifact.bytecode, deployer)
	const proxy = await TransparentUpgradeableProxyFactory.deploy(implementationAddress, proxyAdminAddress, initializeData, gasOptions)
	await proxy.waitForDeployment()
	const proxyAddress = await proxy.getAddress()
	console.log("TransparentUpgradeableProxy deployed to:", proxyAddress)

	// 5. Get the contract instance connected to the proxy
	const contract = Factory.attach(proxyAddress)

	console.log("MultiAccount proxy system deployed successfully!")
	console.log("- Proxy:", proxyAddress)
	console.log("- Admin:", proxyAdminAddress)
	console.log("- Implementation:", implementationAddress)

	return { contract: proxy, implementationAddress, proxyAdminAddress, proxyAddress }
}
