import fs from "fs"
import hre from "hardhat"
import { JsonRpcProvider, parseEther, Wallet } from "@coti-io/coti-ethers"
import { getNetworkGasOptions } from "./testHelpers";

let pks = process.env.PRIVATE_KEYS_STR ? process.env.PRIVATE_KEYS_STR.split(",") : []

export async function setupAccounts() {
	// Get the network configuration from hardhat config
	const networkName = hre.network.name
	const networkConfig = hre.config.networks[networkName]
	const gasOptions = await getNetworkGasOptions()
	
	if (!networkConfig || typeof networkConfig !== 'object' || !('url' in networkConfig)) {
		throw new Error(`Network configuration not found for ${networkName}`)
	}
	
	const provider = new JsonRpcProvider(networkConfig.url);

	if (pks.length == 0) {
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

	const fundAccount = async (wallet: Wallet, mainWallet: Wallet) => {
		const userBalance = await provider.getBalance(wallet.address)
		if (userBalance === BigInt("0")) {
			await (await mainWallet.sendTransaction({ to: wallet.address, value: parseEther("1.0") , ...gasOptions})).wait()
		}
	}

	const toAccount = async (wallet: Wallet, userKey?: string) => {
		if (userKey) {
			wallet.setAesKey(userKey)
			return wallet
		}

		// console.log("************* Onboarding user ", wallet.address, " *************")
		// await wallet.generateOrRecoverAes()
		// console.log("************* Onboarded! created user key and saved into .env file *************")

		return wallet
	}

	let accounts: Wallet[] = []
	// if (userKeys.length !== wallets.length) {
	// 	await Promise.all(wallets.map(async account => await fundAccount(account, wallets[0])))

	// 	accounts = await Promise.all(wallets.map(async account => await toAccount(account)))
	// 	setEnvValue("USER_KEYS", accounts.map(a => a.getUserOnboardInfo()?.aesKey).join(","))
	// } else {
		accounts = await Promise.all(wallets.map(async (account, i) => await toAccount(account, userKeys[i])))
	// }

	return accounts
}

function setEnvValue(key: string, value: string) {
	fs.appendFileSync("./.env", `\n${key}=${value}`, "utf8")
}
