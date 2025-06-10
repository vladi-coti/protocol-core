import { ethers } from "hardhat"
import { getNetworkGasOptions } from "./testHelpers"

export async function runTx(prm: Promise<any>): Promise<any> {
	const network = await ethers.provider.getNetwork()

	// For testnets, we need to handle transactions differently
	if (network.chainId !== 31337n) {
		// Get the transaction promise
		const tx = await prm

		// Wait for the transaction with longer timeout for testnets
		return await tx.wait()
	} else {
		// For local Hardhat network, use the original logic
		return await (await prm).wait()
	}
}

// Alternative function with retry logic for critical transactions
export async function runTxWithRetry(prm: Promise<any>, maxRetries = 3): Promise<any> {
	for (let i = 0; i < maxRetries; i++) {
		try {
			return await runTx(prm)
		} catch (error: any) {
			console.log(`Transaction attempt ${i + 1} failed:`, error.message)

			if (i === maxRetries - 1) {
				throw error // Re-throw on final attempt
			}

			// Wait with exponential backoff
			const delay = 2000 * Math.pow(2, i)
			console.log(`Waiting ${delay}ms before retry...`)
			await new Promise(resolve => setTimeout(resolve, delay))
		}
	}
}

// Helper function to create a contract transaction with network-appropriate gas options
export async function createTxWithGasOptions(contractMethod: any, ...args: any[]): Promise<any> {
	const gasOptions = await getNetworkGasOptions()

	// If gas options are provided (i.e., we're on a testnet), merge them with the transaction
	if (Object.keys(gasOptions).length > 0) {
		return contractMethod(...args, gasOptions)
	} else {
		// For local networks, just call without gas options
		return contractMethod(...args)
	}
}
