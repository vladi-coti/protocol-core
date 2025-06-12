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
	const wrappedContext = { ...context }

	// Wrap all contract properties automatically
	for (const [key, value] of Object.entries(context)) {
		// Check if the value looks like a contract (has target, interface, runner properties)
		if (value && typeof value === "object" && "target" in value && "interface" in value && "runner" in value) {
			console.log(`[DEBUG] Wrapping contract: ${key}`)
			wrappedContext[key as keyof RunContext] = wrapContractWithGasOptions(value)
		}
	}

	return wrappedContext
}

/**
 * Wraps a contract instance to automatically apply gas options to method calls
 */
function wrapContractWithGasOptions(contract: any): any {
	return new Proxy(contract, {
		get(target, prop) {
			const originalValue = target[prop]

			// If it's a function and not a read-only method, wrap it
			if (typeof originalValue === "function" && !isReadOnlyMethod(prop as string, target)) {
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
function isReadOnlyMethod(methodName: string, target: any): boolean {
	const fragment = target.interface.getFunction(methodName)
	return fragment?.stateMutability === "view" || fragment?.stateMutability === "pure"
}

// Custom JSON stringify that handles BigInt
function safeStringify(obj: any) {
	return JSON.stringify(obj, (key, value) => (typeof value === "bigint" ? value.toString() : value))
}

/**
 * Creates a proxy for a transaction receipt that has a wait() method
 * This allows existing test code to call wait() even when we've already waited
 */
function createReceiptProxy(receipt: any): any {
	return new Proxy(receipt, {
		get(target, prop) {
			if (prop === "wait") {
				return async () => target // Return the receipt itself when wait() is called
			}
			return target[prop]
		},
	})
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

		console.log(`[DEBUG] Arguments:`, safeStringify(resolvedArgs))
		console.log(`[DEBUG] Target address:`, target.target)

		if (needsGasOptions) {
			// For read-only methods on testnets, just call normally
			if (isReadOnlyMethod(methodName, target)) {
				console.log(`[DEBUG] Read-only method, calling directly`)
				return originalMethod.apply(target, resolvedArgs)
			}
			console.log(`[DEBUG] Adding gas options for ${methodName}`)

			const gasOptions = await getNetworkGasOptions()
			console.log(`[DEBUG] Gas options:`, safeStringify(gasOptions))

			// First, try the simple approach: original method with gas options
			try {
				console.log(`[DEBUG] Trying original method with gas options`)
				const result = await originalMethod.apply(target, [...resolvedArgs, gasOptions])

				// If it's a transaction, wait for it to be mined
				if (result && typeof result.wait === "function") {
					const receipt = await result.wait()
					// Return a proxy that has a wait method returning the receipt
					return createReceiptProxy(receipt)
				}
				return result
			} catch (error: any) {
				console.log(`[DEBUG] Original method with gas options failed:`, error.message)

				// If it failed due to a revert (what we want for tests), try to get better error message
				if (error.message.includes("execution reverted") || error.code === "CALL_EXCEPTION") {
					console.log(`[DEBUG] Transaction reverted, trying static call for better error`)

					// Get function fragment and encode data for static call
					const fragment = target.interface.getFunction(methodName)
					if (fragment) {
						const data = target.interface.encodeFunctionData(fragment, resolvedArgs)

						try {
							await target.runner.provider.call({
								to: target.target,
								data: data,
								from: target.runner.address,
							})
							// If static call succeeds but transaction failed, re-throw original error
							throw error
						} catch (staticError: any) {
							console.log(`[DEBUG] Static call also failed, using static error for better message`)
							// Use static call error which has better revert reason
							throw staticError
						}
					}
				}

				// For other errors (gas estimation, etc.), re-throw original error
				throw error
			}
		}

		// For local networks, use original method without modifications
		return originalMethod.apply(target, resolvedArgs)
	} catch (error: any) {
		console.warn(`[DEBUG] Gas options wrapper failed for method ${originalMethod.name || "unknown"}:`, error.message)
		console.warn(`[DEBUG] Full error:`, safeStringify(error))
		throw error
	}
}
