import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { ethers } from "hardhat"
import { RunContext } from "../models/RunContext"

/**
 * Helper function to load fixture compatible with both local and testnet environments
 * Uses loadFixture for Hardhat Network (with snapshots) and direct function call for testnets
 */
export async function loadFixtureCompatible(fixtureFunction: () => Promise<RunContext>): Promise<RunContext> {
	const network = await ethers.provider.getNetwork()

	// Use loadFixture only for Hardhat Network (chainId 31337)
	if (network.chainId === 31337n) {
		return await loadFixture(fixtureFunction)
	} else {
		// For testnets, just call the fixture function directly
		console.log(`Running on testnet (chainId: ${network.chainId}), initializing without snapshots...`)
		return await fixtureFunction()
	}
}

/**
 * Utility function to check if we're running on a testnet
 */
export function isTestnet(): Promise<boolean> {
	return ethers.provider.getNetwork().then(network => network.chainId !== 31337n)
}

/**
 * Utility function to get network-specific gas options
 */
export async function getNetworkGasOptions() {
	const network = await ethers.provider.getNetwork()

	if (network.chainId === 7082400n) {
		// COTI testnet
		return {
			gasLimit: 3000000,
			gasPrice: ethers.parseUnits("1.2", "gwei"),
		}
	}

	return {} // Use default gas estimation for other networks
}
