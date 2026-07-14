import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { ethers } from "hardhat"
import { network } from "hardhat"
import { RunContext } from "../models/RunContext"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { gasOptions, simCotiChainId, testnetChainId } from "../../tasks/deploy/constants"

const TESTNET_TIME_POLL_MS = 5_000
const TESTNET_EXTRA_SECONDS = 1n

function sleep(ms: number): Promise<void> {
	return new Promise(resolve => setTimeout(resolve, ms))
}

/** In-process Hardhat or local sim-coti-node (Hardhat JSON-RPC with time travel). */
function supportsInstantTimeTravel(): boolean {
	return network.name === "hardhat" || network.name === "localSimCoti"
}

async function waitForTestnetTimestamp(targetTimestamp: bigint): Promise<void> {
	for (;;) {
		const block = await ethers.provider.getBlock("latest")
		if (block && BigInt(block.timestamp) >= targetTimestamp) {
			return
		}
		await sleep(TESTNET_TIME_POLL_MS)
	}
}

/**
 * Helper function to load fixture compatible with both local and testnet environments
 * Uses loadFixture for Hardhat Network (with snapshots) and direct function call for testnets
 * 
 * Note: Gas options are now handled globally via wrapOverrides.ts which patches
 * estimateGas/getFeeData/signers at the HRE level. No contract wrapping needed here.
 */
export async function loadFixtureCompatible(fixtureFunction: () => Promise<RunContext>): Promise<RunContext> {
	const chain = await ethers.provider.getNetwork()

	// This repo runs local tests on Hardhat while emulating the COTI chain ID.
	// Detect the in-process Hardhat network by name instead of chain ID.
	// localSimCoti is an external Hardhat node — no snapshot/loadFixture support across the RPC.
	if (network.name === "hardhat") {
		return await loadFixture(fixtureFunction)
	} else {
		// For testnets / sim, just call the fixture function directly
		// Gas handling is done globally by wrapOverrides.ts
		console.log(`Running on testnet (chainId: ${chain.chainId}), initializing without snapshots...`)
		return await fixtureFunction()
	}
}

/**
 * Utility function to get network-specific gas options
 */
export async function getNetworkGasOptions() {
	const chain = await ethers.provider.getNetwork()

	if (chain.chainId === testnetChainId || chain.chainId === simCotiChainId || network.name === "localSimCoti") {
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
		const chain = await ethers.provider.getNetwork()

		if (supportsInstantTimeTravel()) {
			// hardhat-network-helpers uses evm_increaseTime / evm_mine — works on
			// in-process Hardhat and on external sim-coti-node (Hardhat JSON-RPC).
			await time.increase(seconds)
		} else {
			// On real testnet, wait until block.timestamp has actually advanced beyond the
			// requested delta. Add one extra second because many cooldown checks use `>`.
			const latestBlock = await ethers.provider.getBlock("latest")
			const startTimestamp = BigInt(latestBlock!.timestamp)
			const delta = BigInt(seconds)
			const targetTimestamp = startTimestamp + delta + TESTNET_EXTRA_SECONDS
			console.log(
				`Waiting for testnet time increase to ${targetTimestamp} (chainId: ${chain.chainId}, delta: ${delta}s)...`
			)
			await waitForTestnetTimestamp(targetTimestamp)
		}
	},
	async latest(): Promise<number> {
		if (supportsInstantTimeTravel()) {
			return await time.latest()
		} else {
			// For testnets, get current block timestamp
			const block = await ethers.provider.getBlock("latest")
			return block!.timestamp
		}
	},
	async setNextBlockTimestamp(timestamp: bigint): Promise<void> {
		if (supportsInstantTimeTravel()) {
			await time.setNextBlockTimestamp(timestamp)
		} else {
			// On real testnet we cannot set time, only wait until the chain reaches it.
			const targetTimestamp = BigInt(timestamp)
			const currentBlock = await ethers.provider.getBlock("latest")
			const currentTimestamp = BigInt(currentBlock!.timestamp)
			if (currentTimestamp < targetTimestamp) {
				console.log(`Waiting for testnet block timestamp ${targetTimestamp}...`)
				await waitForTestnetTimestamp(targetTimestamp)
			}
		}
	},
}
