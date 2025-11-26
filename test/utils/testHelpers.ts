import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { ethers } from "hardhat"
import { RunContext } from "../models/RunContext"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { gasOptions, testnetChainId } from "../../tasks/deploy/constants"

/**
 * Helper function to load fixture compatible with both local and testnet environments
 * Uses loadFixture for Hardhat Network (with snapshots) and direct function call for testnets
 * 
 * Note: Gas options are now handled globally via wrapOverrides.ts which patches
 * estimateGas/getFeeData/signers at the HRE level. No contract wrapping needed here.
 */
export async function loadFixtureCompatible(fixtureFunction: () => Promise<RunContext>): Promise<RunContext> {
	const network = await ethers.provider.getNetwork()

	// Use loadFixture only for Hardhat Network (chainId 31337)
	if (network.chainId === 31337n) {
		return await loadFixture(fixtureFunction)
	} else {
		// For testnets, just call the fixture function directly
		// Gas handling is done globally by wrapOverrides.ts
		console.log(`Running on testnet (chainId: ${network.chainId}), initializing without snapshots...`)
		return await fixtureFunction()
	}
}

/**
 * Utility function to get network-specific gas options
 */
export async function getNetworkGasOptions() {
	const network = await ethers.provider.getNetwork()

	if (network.chainId === testnetChainId) {
		// COTI testnet
		return gasOptions
	}

	return {} // Use default gas estimation for other networks
}

/**
 * Check if we're on a testnet that needs explicit gas options
 */
export async function isTestnetRequiringGas(): Promise<boolean> {
	const network = await ethers.provider.getNetwork()
	return network.chainId === testnetChainId // COTI testnet
}

/**
 * Time helper compatible with both local and testnet environments
 */
export const timeCompatible = {
	async increase(seconds: bigint | number): Promise<void> {
		const network = await ethers.provider.getNetwork()

		if (network.chainId === 31337n) {
			// Use hardhat-network-helpers for local network
			await time.increase(seconds)
		} else {
			// For testnets, just wait the actual time (much shorter for testing)
			const waitTime = Number(seconds)
			console.log(`Waiting ${waitTime}s to simulate time increase on testnet...`)
			await new Promise(resolve => setTimeout(resolve, waitTime * 1000))
		}
	},
	async latest(): Promise<number> {
		const network = await ethers.provider.getNetwork()

		if (network.chainId === 31337n) {
			// Use hardhat-network-helpers for local network
			return await time.latest()
		} else {
			// For testnets, get current block timestamp
			const block = await ethers.provider.getBlock("latest")
			return block!.timestamp
		}
	},
	async setNextBlockTimestamp(timestamp: bigint): Promise<void> {
		const network = await ethers.provider.getNetwork()

		if (network.chainId === 31337n) {
			// Use hardhat-network-helpers for local network
			await time.setNextBlockTimestamp(timestamp)
		} else {
			// For testnets, just increase to reach the target
			const currentBlock = await ethers.provider.getBlock("latest")
			const currentTime = currentBlock!.timestamp
			const targetTime = Number(timestamp)
			const diff = targetTime - currentTime
			if (diff > 0) {
				await this.increase(diff)
			}
		}
	},
}
