import fs from "fs"
import hre from "hardhat"
import { JsonRpcProvider, parseEther, Wallet } from "@coti-io/coti-ethers"
import { getNetworkGasOptions } from "./testHelpers"
import { gasOptions as defaultGasOptions, simCotiChainId, testnetChainId } from "../../tasks/deploy/constants"

let pks = process.env.PRIVATE_KEYS_STR ? process.env.PRIVATE_KEYS_STR.split(",") : []

function isTestnetChain(): boolean {
	const network = hre.network.config
	return network.chainId === Number(testnetChainId)
}

function isSimChain(): boolean {
	if (hre.network.name === "localSimCoti") return true
	const chainId = hre.network.config.chainId
	return chainId != null && Number(chainId) === Number(simCotiChainId)
}

async function loadSimCotiEthers() {
	return await import("@coti-io/sim-coti-node/coti-ethers")
}

function patchProviderForTestnet(provider: any) {
	if (!isTestnetChain() && !isSimChain()) return

	const gasLimit = BigInt(defaultGasOptions.gasLimit)
	const gasPrice = BigInt(defaultGasOptions.gasPrice)

	provider.estimateGas = async () => gasLimit
	provider.getFeeData = async () => ({
		gasPrice,
		lastBaseFeePerGas: null,
		maxFeePerGas: null,
		maxPriorityFeePerGas: null,
	})
	provider.getGasPrice = async () => gasPrice
}

function wrapWalletForTestnet(wallet: Wallet): Wallet {
	if (!isTestnetChain() && !isSimChain()) return wallet

	const gasLimit = BigInt(defaultGasOptions.gasLimit)
	const gasPrice = BigInt(defaultGasOptions.gasPrice)

	const originalSendTransaction = wallet.sendTransaction.bind(wallet)
	wallet.sendTransaction = async (tx: any) => {
		const patchedTx = { ...tx }
		if (patchedTx.gasLimit == null) patchedTx.gasLimit = gasLimit
		if (gasPrice != null) {
			delete patchedTx.maxFeePerGas
			delete patchedTx.maxPriorityFeePerGas
			patchedTx.gasPrice = gasPrice
		}
		const response = await originalSendTransaction(patchedTx)
		if (response && typeof response.wait === "function") {
			const receipt = await response.wait()
			return new Proxy(response, {
				get(target, p) {
					if (p === "wait") return async () => receipt
					return (target as any)[p]
				},
			}) as any
		}
		return response
	}

	return wallet
}

export async function setupAccounts() {
	const networkName = hre.network.name
	const networkConfig = hre.config.networks[networkName]
	const gasOptions = await getNetworkGasOptions()
	const sim = isSimChain()

	if (!networkConfig || typeof networkConfig !== "object" || !("url" in networkConfig)) {
		throw new Error(`Network configuration not found for ${networkName}`)
	}

	// Prefer HRE provider so sim wallets share nonce state with hardhat-ethers deploys.
	const provider = (sim ? (hre.ethers.provider as any) : new JsonRpcProvider(networkConfig.url as string)) as JsonRpcProvider
	patchProviderForTestnet(provider)

	if (sim) {
		const { HARDHAT_DEFAULT_PRIVATE_KEYS } = await loadSimCotiEthers()
		pks = [...HARDHAT_DEFAULT_PRIVATE_KEYS]
	} else if (pks.length == 0) {
		const key1 = Wallet.createRandom(provider)
		const key2 = Wallet.createRandom(provider)
		pks = [key1.privateKey, key2.privateKey]

		setEnvValue("PUBLIC_KEYS_STR", `${key1.address},${key2.address}`)
		setEnvValue("PRIVATE_KEYS_STR", `${key1.privateKey},${key2.privateKey}`)

		throw new Error(`Created new random accounts ${key1.address} and ${key2.address}. Please use faucet to fund them.`)
	}

	const wallets = pks.map(pk => new Wallet(pk, provider))
	if ((await provider.getBalance(wallets[0].address)) === BigInt("0")) {
		throw new Error(`Please use faucet to fund account ${wallets[0].address}`)
	}

	let userKeys = process.env.USER_KEYS ? process.env.USER_KEYS.split(",") : []

	const fundAccount = async (wallet: Wallet, mainWallet: Wallet, nonce: number) => {
		const userBalance = await provider.getBalance(wallet.address)
		if (userBalance === BigInt("0")) {
			const tx = await mainWallet.sendTransaction({
				to: wallet.address,
				value: parseEther("1.0"),
				nonce,
				gasLimit: (gasOptions as any).gasLimit ?? defaultGasOptions.gasLimit,
				gasPrice: (gasOptions as any).gasPrice ?? defaultGasOptions.gasPrice,
			})
			await tx.wait()
			return true
		}
		return false
	}

	const toAccount = async (wallet: Wallet, userKey?: string) => {
		if (sim) {
			const { enableCotiEthersSimWallet } = await loadSimCotiEthers()
			return (await enableCotiEthersSimWallet(wallet as any, provider as any)) as unknown as Wallet
		}
		if (userKey) {
			wallet.setAesKey(userKey)
			return wallet
		}
		return wallet
	}

	let accounts: Wallet[] = []
	if (sim) {
		let nonce = await provider.getTransactionCount(wallets[0].address, "latest")
		for (const account of wallets.slice(1)) {
			const sent = await fundAccount(account, wallets[0], nonce)
			if (sent) nonce += 1
		}
		accounts = []
		for (const account of wallets) {
			accounts.push(await toAccount(account))
		}
	} else {
		accounts = await Promise.all(wallets.map(async (account, i) => await toAccount(account, userKeys[i])))
	}

	return accounts.map(wrapWalletForTestnet)
}

function setEnvValue(key: string, value: string) {
	fs.appendFileSync("./.env", `\n${key}=${value}`, "utf8")
}
