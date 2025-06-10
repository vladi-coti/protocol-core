import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { ethers } from "hardhat"
import { RunContext } from "../models/RunContext"
import { time } from "@nomicfoundation/hardhat-network-helpers"

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
		const context = await fixtureFunction()

		// Wrap contract instances with gas-aware versions for testnets
		return wrapContractsWithGasOptions(context)
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

/**
 * Check if we're on a testnet that needs explicit gas options
 */
async function isTestnetRequiringGas(): Promise<boolean> {
	const network = await ethers.provider.getNetwork()
	return network.chainId === 7082400n // COTI testnet
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
			const waitTime = Math.min(Number(seconds) * 10, 5000) // Max 5 seconds wait
			console.log(`Waiting ${waitTime}ms to simulate time increase on testnet...`)
			await new Promise(resolve => setTimeout(resolve, waitTime))
		}
	},
}

/**
 * Wraps contract instances to automatically apply gas options on testnets
 */
function wrapContractsWithGasOptions(context: RunContext): RunContext {
	const wrappedContext = context as any
	const contractNames = [
		"accountFacet",
		"controlFacet",
		"diamondCutFacet",
		"diamondLoupeFacet",
		"liquidationFacet",
		"partyAFacet",
		"bridgeFacet",
		"viewFacet",
		"fundingRateFacet",
		"forceActionsFacet",
		"settlementFacet",
		"partyBPositionActionsFacet",
		"partyBQuoteActionsFacet",
		"partyBGroupActionsFacet",
	]

	contractNames.forEach(contractName => {
		if (wrappedContext[contractName]) {
			wrappedContext[contractName] = wrapContractWithGasOptions(wrappedContext[contractName])
		}
	})

	return context
}

/**
 * Wraps a contract instance to automatically apply gas options to method calls
 */
function wrapContractWithGasOptions(contract: any): any {
	return new Proxy(contract, {
		get(target, prop) {
			const originalValue = target[prop]

			// If it's a function and not a read-only method, wrap it
			if (typeof originalValue === "function" && !isReadOnlyMethod(prop as string)) {
				return function (...args: any[]) {
					// Call the original connect method if it's connect
					if (prop === "connect") {
						const connectedContract = originalValue.apply(target, args)
						return wrapContractWithGasOptions(connectedContract)
					}

					// For other methods, add gas options
					return addGasOptionsToCall(originalValue, target, args)
				}
			}

			return originalValue
		},
	})
}

/**
 * Checks if a method is read-only (doesn't need gas options)
 */
function isReadOnlyMethod(methodName: string): boolean {
	const readOnlyMethods = [
		"getAddress",
		"interface",
		"provider",
		"runner",
		"target",
		"balanceOf",
		"getQuote",
		"facetAddresses",
		"facetFunctionSelectors",
		"getBalanceInfo",
		"balanceInfoOfPartyA",
		"balanceInfoOfPartyB",
		"allocatedBalanceOfPartyA",
		"allocatedBalanceOfPartyB",
	]
	return readOnlyMethods.includes(methodName) || methodName.startsWith("get") || methodName.startsWith("view")
}

/**
 * Manually send transaction using populateTransaction to bypass gas estimation
 */
async function sendTestnetTransaction(contract: any, methodName: string, args: any[]): Promise<any> {
	const gasOptions = await getNetworkGasOptions()

	try {
		// Use populateTransaction which properly handles argument encoding
		const populatedTx = await contract[methodName].populateTransaction(...args)

		// Create transaction manually to completely bypass gas estimation
		const tx = {
			to: populatedTx.to,
			data: populatedTx.data,
			value: populatedTx.value || 0,
			...gasOptions,
		}

		// Send directly through signer to avoid any ethers gas estimation
		const signer = contract.runner
		const sentTx = await signer.sendTransaction(tx)

		return await sentTx.wait()
	} catch (error: any) {
		console.warn(`Manual transaction failed for ${methodName}:`, error.message)
		throw error
	}
}

/**
 * Adds gas options to a contract method call and waits for mining on testnets
 */
async function addGasOptionsToCall(originalMethod: any, target: any, args: any[]): Promise<any> {
	try {
		const needsGasOptions = await isTestnetRequiringGas()
		const methodName = originalMethod.name || originalMethod.fragment?.name || "unknown"
		console.log(`[DEBUG] Method: ${methodName}`)

		// Await any Promise arguments before proceeding
		const resolvedArgs = await Promise.all(
			args.map(async arg => {
				if (arg instanceof Promise) {
					return await arg
				}
				return arg
			}),
		)

		console.log(`[DEBUG] Arguments:`, JSON.stringify(resolvedArgs, null, 2))
		console.log(`[DEBUG] Target address:`, target.target)

		if (needsGasOptions) {
			// For read-only methods on testnets, just call normally
			if (isReadOnlyMethod(methodName)) {
				console.log(`[DEBUG] Read-only method, calling directly`)
				return originalMethod.apply(target, resolvedArgs)
			}
			console.log(`[DEBUG] Adding gas options for ${methodName}`)

			// TEMPORARY: Try original method with gas options first to see if it works
			try {
				const gasOptions = await getNetworkGasOptions()
				console.log(`[DEBUG] Gas options:`, JSON.stringify(gasOptions, null, 2))

				// Log the populated transaction before sending
				const populatedTx = await originalMethod.populateTransaction(...resolvedArgs)
				console.log(`[DEBUG] Populated transaction:`, JSON.stringify(populatedTx, null, 2))

				const result = await originalMethod.apply(target, [...resolvedArgs, gasOptions])
				// If it's a transaction, wait for it to be mined
				if (result && typeof result.wait === "function") {
					await new Promise(resolve => setTimeout(resolve, 500))
					return await result.wait()
				}
				return result
			} catch (gasError: any) {
				console.warn(`[DEBUG] Standard method with gas options failed for ${methodName}:`, gasError.message)
				console.warn(`[DEBUG] Error details:`, JSON.stringify(gasError, null, 2))
				// Fall back to manual transaction sending to completely avoid gas estimation
				if (target.interface && methodName !== "unknown") {
					return await sendTestnetTransaction(target, methodName, resolvedArgs)
				}
			}
		}

		// For local networks, use original method without modifications
		return originalMethod.apply(target, resolvedArgs)
	} catch (error: any) {
		console.warn(`[DEBUG] Gas options wrapper failed for method ${originalMethod.name || "unknown"}:`, error.message)
		console.warn(`[DEBUG] Full error:`, JSON.stringify(error, null, 2))
		// For testnets, don't fall back as it will cause gas estimation issues
		const needsGasOptions = await isTestnetRequiringGas()
		if (needsGasOptions) {
			throw error
		}
		// Only fall back for local networks
		return originalMethod.apply(target, args)
	}
}
