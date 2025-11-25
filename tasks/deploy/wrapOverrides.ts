import { extendEnvironment } from "hardhat/config"
import type { HardhatRuntimeEnvironment } from "hardhat/types"
import { gasOptions, testnetChainId } from "./constants"

function safeStringify(obj: any) {
	return JSON.stringify(obj, (key, value) => (typeof value === "bigint" ? value.toString() : value))
}

export async function loadProviderNetwork(hre?: HardhatRuntimeEnvironment) {
	if (hre) {
		return await hre.ethers.provider.getNetwork()
	}
	// eslint-disable-next-line @typescript-eslint/no-var-requires
	const hardhat = require("hardhat") as typeof import("hardhat")
	return await hardhat.ethers.provider.getNetwork()
}

export async function isTestnetRequiringGas(hre?: HardhatRuntimeEnvironment): Promise<boolean> {
	const network = await loadProviderNetwork(hre)
	return network.chainId === BigInt(testnetChainId)
}

export async function getNetworkGasOptions(hre?: HardhatRuntimeEnvironment) {
	const network = await loadProviderNetwork(hre)
	if (network.chainId === BigInt(testnetChainId)) {
		return gasOptions
	}
	return {}
}

function wrapContractWithGasOptions(hre: HardhatRuntimeEnvironment, contract: any): any {
	return new Proxy(contract, {
		get(target, prop) {
			const originalValue = target[prop]

			if (typeof originalValue === "function") {
				if (prop === "connect") {
					return function (...args: any[]) {
						const connectedContract = originalValue.apply(target, args)
						return wrapContractWithGasOptions(hre, connectedContract)
					}
				}
				if (prop === "waitForDeployment") {
					return async function (...args: any[]) {
						const deployed = await originalValue.apply(target, args)
						return wrapContractWithGasOptions(hre, deployed)
					}
				}
				if (!isReadOnlyMethod(prop as string, target)) {
					return function (...args: any[]) {
						return addGasOptionsToCall(hre, originalValue, target, args)
					}
				}
			}

			return originalValue
		},
	})
}

function isReadOnlyMethod(methodName: string, target: any): boolean {
	try {
		const fragment = target.interface.getFunction(methodName)
		return fragment?.stateMutability === "view" || fragment?.stateMutability === "pure"
	} catch {
		return false
	}
}

async function addGasOptionsToCall(hre: HardhatRuntimeEnvironment, originalMethod: any, target: any, args: any[]): Promise<any> {
	try {
		const needsGasOptions = await isTestnetRequiringGas(hre)
		const methodName = originalMethod.name || originalMethod.fragment?.name || "unknown"
		console.log(`[DEBUG] Method: ${methodName}`)

		const resolvedArgs = await Promise.all(args.map(async arg => (arg instanceof Promise ? await arg : arg)))

		console.log(`[DEBUG] Arguments:`, safeStringify(resolvedArgs))
		console.log(`[DEBUG] Target address:`, target.target)

		if (needsGasOptions) {
			if (isReadOnlyMethod(methodName, target)) {
				console.log(`[DEBUG] Read-only method, calling directly`)
				return originalMethod.apply(target, resolvedArgs)
			}
			console.log(`[DEBUG] Adding gas options for ${methodName}`)

			const gasOptions = await getNetworkGasOptions(hre)
			console.log(`[DEBUG] Gas options:`, safeStringify(gasOptions))

			try {
				console.log(`[DEBUG] Trying original method with gas options`)
				const result = await originalMethod.apply(target, [...resolvedArgs, gasOptions])
				if (result && typeof result.wait === "function") {
					const receipt = await result.wait()
					return new Proxy(receipt, {
						get(innerTarget, innerProp) {
							if (innerProp === "wait") {
								return async () => innerTarget
							}
							return innerTarget[innerProp]
						},
					})
				}
				return result
			} catch (error: any) {
				console.log(`[DEBUG] Original method with gas options failed:`, error.message)
				if (error.message.includes("execution reverted") || error.code === "CALL_EXCEPTION") {
					console.log(`[DEBUG] Transaction reverted, trying static call for better error`)
					const fragment = target.interface.getFunction(methodName)
					if (fragment) {
						const data = target.interface.encodeFunctionData(fragment, resolvedArgs)
						try {
							await hre.ethers.provider.call({
								to: target.target,
								data: data,
								from: target.runner?.address,
							})
							throw error
						} catch (staticError: any) {
							if (staticError.message.includes("missing revert data")) {
								throw error
							}
							console.log(`[DEBUG] Static call also failed, using static error for better message`)
							throw staticError
						}
					}
				}
				throw error
			}
		}

		return originalMethod.apply(target, resolvedArgs)
	} catch (error: any) {
		console.warn(`[DEBUG] Gas options wrapper failed for method ${originalMethod.name || "unknown"}:`, error.message)
		console.warn(`[DEBUG] Full error:`, safeStringify(error))
		throw error
	}
}

async function mergeWithDefaultTxOverrides(hre: HardhatRuntimeEnvironment, options?: any) {
	const gasOptions = await getNetworkGasOptions(hre)
	if (!gasOptions || Object.keys(gasOptions).length === 0) {
		return options
	}
	const mergedOptions = {
		...(options ?? {}),
		txOverrides: {
			...gasOptions,
			...((options && options.txOverrides) || {}),
		},
	}
	return mergedOptions
}

function isOptionsObject(value: any) {
	return value && typeof value === "object" && !Array.isArray(value)
}

async function injectDefaultOverrides(hre: HardhatRuntimeEnvironment, args: any[]) {
	const updatedArgs = [...args]
	const maybeOptionsIndex = updatedArgs.length > 0 && isOptionsObject(updatedArgs[updatedArgs.length - 1]) ? updatedArgs.length - 1 : -1
	const updatedOptions = await mergeWithDefaultTxOverrides(hre, maybeOptionsIndex >= 0 ? updatedArgs[maybeOptionsIndex] : undefined)
	if (updatedOptions !== undefined) {
		if (maybeOptionsIndex >= 0) {
			updatedArgs[maybeOptionsIndex] = updatedOptions
		} else {
			updatedArgs.push(updatedOptions)
		}
	}
	return updatedArgs
}

function shouldWrapUpgradeMethod(methodName: string) {
	return ["deployProxy", "upgradeProxy", "prepareUpgrade", "deployImplementation"].includes(methodName)
}

function wrapUpgradesWithGasOptions(hre: HardhatRuntimeEnvironment, upgradesInstance: any): any {
	return new Proxy(upgradesInstance, {
		get(target, prop, receiver) {
			const original = Reflect.get(target, prop, receiver)
			if (typeof original !== "function" || !shouldWrapUpgradeMethod(prop as string)) {
				return original
			}
			return async (...args: any[]) => {
				const updatedArgs = await injectDefaultOverrides(hre, args)
				const result = await original.apply(target, updatedArgs)
				if (prop === "deployProxy" || prop === "upgradeProxy") {
					return wrapContractWithGasOptions(hre, result)
				}
				return result
			}
		},
	})
}

extendEnvironment((hre: HardhatRuntimeEnvironment) => {
	hre.upgrades = wrapUpgradesWithGasOptions(hre, hre.upgrades)
})

