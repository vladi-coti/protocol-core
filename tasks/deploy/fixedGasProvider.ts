import { extendEnvironment } from "hardhat/config"
import type { HardhatRuntimeEnvironment } from "hardhat/types"
import { gasOptions, testnetChainId } from "./constants"

function shouldUseFixedGas(hre: HardhatRuntimeEnvironment): boolean {
	const configuredChainId = hre.network?.config?.chainId
	if (configuredChainId != null) {
		try {
			return BigInt(configuredChainId) === testnetChainId
		} catch {
			return false
		}
	}
	return false
}

function getFixedGasConfig() {
	const gasLimit = gasOptions.gasLimit != null ? BigInt(gasOptions.gasLimit) : 30_000_000n
	const gasPrice = gasOptions.gasPrice != null ? BigInt(gasOptions.gasPrice) : undefined
	return { gasLimit, gasPrice }
}

/**
 * Patch the provider to return fixed gas values instead of estimating.
 * This is needed because the testnet doesn't support pending block queries.
 */
function patchProvider(provider: any, gasLimit: bigint, gasPrice?: bigint) {
	if (!provider) return

	provider.estimateGas = async () => gasLimit

	if (gasPrice != null) {
		provider.getFeeData = async () => ({
			gasPrice,
			lastBaseFeePerGas: null,
			maxFeePerGas: null,
			maxPriorityFeePerGas: null,
		})
		provider.getGasPrice = async () => gasPrice
	}
}

/**
 * Patch upgrades to inject txOverrides with gas settings.
 * This is needed because upgrades.deployProxy() etc. don't use the patched provider directly.
 */
function patchUpgrades(hre: HardhatRuntimeEnvironment, gasLimit: bigint, gasPrice?: bigint) {
	if (!hre.upgrades) return

	const methodsToWrap = ["deployProxy", "upgradeProxy", "prepareUpgrade", "deployImplementation"]

	for (const methodName of methodsToWrap) {
		const original = (hre.upgrades as any)[methodName]
		if (typeof original !== "function") continue

		;(hre.upgrades as any)[methodName] = async (...args: any[]) => {
			const txOverrides: any = { gasLimit: Number(gasLimit) }
			if (gasPrice != null) {
				txOverrides.gasPrice = Number(gasPrice)
			}

			// Find the options argument (usually last) and merge txOverrides
			const lastArg = args[args.length - 1]
			if (lastArg && typeof lastArg === "object" && !Array.isArray(lastArg) && !("interface" in lastArg)) {
				args[args.length - 1] = {
					...lastArg,
					txOverrides: {
						...txOverrides,
						...(lastArg.txOverrides || {}),
					},
				}
			} else {
				args.push({ txOverrides })
			}
			return original.apply(hre.upgrades, args)
		}
	}
}

extendEnvironment((hre: HardhatRuntimeEnvironment) => {
	if (!shouldUseFixedGas(hre)) return

	const { gasLimit, gasPrice } = getFixedGasConfig()
	
	// Patch the main provider - needed for contract calls that go through hre.ethers.provider
	patchProvider(hre.ethers.provider, gasLimit, gasPrice)
	
	// Patch upgrades - needed for deployProxy etc.
	patchUpgrades(hre, gasLimit, gasPrice)
})
