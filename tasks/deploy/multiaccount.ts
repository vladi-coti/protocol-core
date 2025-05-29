import { task, types } from "hardhat/config"
import { readData, writeData } from "../utils/fs"
import { DEPLOYMENT_LOG_FILE } from "./constants"

task("deploy:multiAccount", "Deploys the MultiAccount")
	.addParam("symmioAddress", "The address of the Symmio contract")
	.addParam("admin", "The admin address")
	.addOptionalParam("logData", "Write the deployed addresses to a data file", true, types.boolean)
	.setAction(async ({ symmioAddress, admin, logData }, { ethers, run }) => {
		console.log("Running deploy:multiAccount")

		const [deployer] = await ethers.getSigners()

		console.log("Deploying contracts with the account:", deployer.address)

		const SymmioPartyA = await ethers.getContractFactory("SymmioPartyA")

		// Deploy MultiAccount as regular contract (not upgradeable)
		const Factory = await ethers.getContractFactory("MultiAccount")
		console.log(admin, symmioAddress)

		// Deploy the contract directly with constructor parameters
		const contract = await Factory.deploy({
			gasLimit: 5000000,
			gasPrice: 1000000000, // 1 gwei
		})
		await contract.waitForDeployment()

		// Initialize the contract manually (since it's not a proxy anymore, we need to call initialize)
		// But first check if it's already initialized to avoid the error
		try {
			await contract.initialize(admin, symmioAddress, SymmioPartyA.bytecode, {
				gasLimit: 2000000,
				gasPrice: 1000000000, // 1 gwei
			})
		} catch (error: any) {
			if (error.message.includes("already initialized")) {
				console.log("Contract already initialized, skipping...")
			} else {
				throw error
			}
		}

		console.log("MultiAccount deployed to:", await contract.getAddress())

		if (logData) {
			// Read existing data
			let deployedData = []
			try {
				deployedData = readData(DEPLOYMENT_LOG_FILE)
			} catch (err) {
				console.error(`Could not read existing JSON file: ${err}`)
			}

			// Append new data
			deployedData.push({
				name: "MultiAccount",
				address: await contract.getAddress(),
				constructorArguments: [],
			})

			// Write updated data back to JSON file
			writeData(DEPLOYMENT_LOG_FILE, deployedData)
			console.log("Deployed addresses written to JSON file")
		}

		return contract
	})
