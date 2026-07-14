import "@nomicfoundation/hardhat-chai-matchers"
import "@nomicfoundation/hardhat-toolbox"
import "@openzeppelin/hardhat-upgrades"
import { config as dotenvConfig } from "dotenv"
import type { HardhatUserConfig } from "hardhat/config"
import { resolve } from "path"
import "solidity-docgen"

import "./tasks/deploy"

const dotenvConfigPath: string = process.env.DOTENV_CONFIG_PATH || "./.env"
dotenvConfig({ path: resolve(__dirname, dotenvConfigPath) })

// Ensure that we have all the environment variables we need.
const privateKey: string | undefined = process.env.PRIVATE_KEY
if (!privateKey) throw new Error("Please set your PRIVATE_KEY in a .env file")

const privateKeysStr: string | undefined = process.env.PRIVATE_KEYS_STR
const privateKeyList: string[] = privateKeysStr?.split(",") || []

const arbitrumApiKey: string = process.env.ARBITRUM_API_KEY || ""
const bnbApiKey: string = process.env.BNB_API_KEY || ""
const baseApiKey: string = process.env.BASE_API_KEY || ""
const polygonApiKey: string = process.env.POLYGON_API_KEY || ""
const zkEvmApiKey: string = process.env.ZKEVM_API_KEY || ""
const opBnbApiKey: string = process.env.OPBNB_API_KEY || ""
const sonicApiKey: string = process.env.SONIC_API_KEY || ""
const iotaApiKey: string = process.env.IOTA_API_KEY || ""
const modeApiKey: string = process.env.MODE_API_KEY || ""
const blastApiKey: string = process.env.BLAST_API_KEY || ""
const mantleAPIKey: string = process.env.MANTLE_API_KEY || ""
const mantle2APIKey: string = process.env.MANTLE2_API_KEY || ""
const beraAPIKey: string = process.env.BERA_API_KEY || ""

const hardhatDockerUrl: string | undefined = process.env.HARDHAT_DOCKER_URL || ""

const config: HardhatUserConfig = {
	defaultNetwork: "coti-testnet",
	gasReporter: {
		currency: "USD",
		enabled: false,
		excludeContracts: [],
		src: "./contracts",
	},
	networks: {
		"private-testnet": {
			url: "http://40.160.11.74:8545",
			chainId: 15151515,
			accounts: privateKeyList,
			gasPrice: 1000000000,
			gasMultiplier: 1.5,
			blockGasLimit: 30000000,
			timeout: 120000,
			initialBaseFeePerGas: 1200000000, // 1.2 gwei
		},
		"soda-testnet": {
			url: "http://3.88.141.22:7000",
			chainId: 50505050,
			accounts: privateKeyList,
			gasPrice: 1000000000,
			gasMultiplier: 1.5,
			blockGasLimit: 30000000,
			timeout: 120000,
			initialBaseFeePerGas: 1200000000, // 1.2 gwei
		},
		"coti-testnet": {
			url: "https://testnet.coti.io/rpc",
			chainId: 7082400,
			accounts: privateKeyList,
			gasPrice: 1000000000,
			gasMultiplier: 1.5,
			blockGasLimit: 30000000,
			timeout: 120000,
			initialBaseFeePerGas: 1200000000, // 1.2 gwei
		},
		/** Local sim-coti-node (`npm start` in sim-coti-node). Hardhat default keys only. */
		localSimCoti: {
			url: process.env.SIM_COTI_RPC_URL || "http://127.0.0.1:8546",
			chainId: 7082401,
			accounts: [
				"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
				"0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
				"0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
				"0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
				"0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",
				"0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba",
				"0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e",
				"0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356",
				"0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97",
				"0x2a871d0798f97d79848a013d4936a609675a46a64cb97a9da67b92a791a9f8a9",
				"0xf214f2b2cd398c806f84e317254e0f0b801d0643303237e212a861d0f5bde0c9",
				"0x701b615bbdfb9de6522bfcad1e6e12e344ba44cc19d17e6f2b55a9488e6dff7f",
			],
			gasPrice: 1000000000,
			gasMultiplier: 1.2,
			blockGasLimit: 60000000,
			timeout: 120000,
		},
		"coti-mainnet": {
			url: "https://mainnet.coti.io/rpc",
			chainId: 2632500,
			accounts: [privateKey],
			gas: 8000000,
			gasPrice: 1000000000, // 1 gwei
			timeout: 60000,
		},
		hardhat: {
			forking: {
				url: "https://base-mainnet.infura.io/v3/b16236911a594ad1a9a9b6e161c70ce7",
				blockNumber: 23478537,
			},
			loggingEnabled: false,
			allowUnlimitedContractSize: false,
		},
		docker: {
			url: hardhatDockerUrl,
			allowUnlimitedContractSize: false,
			accounts: privateKeyList,
		},
		bsc: {
			url: "https://bscrpc.com",
			accounts: [privateKey],
		},
		opbnb: {
			url: "https://opbnb.publicnode.com",
			accounts: [privateKey],
		},
		base: {
			url: "https://virtual.base.rpc.tenderly.co/b0a4916f-040f-46c4-970d-a3c95d04ee02",
			accounts: [privateKey],
		},
		polygon: {
			url: "https://polygon-rpc.com",
			accounts: [privateKey],
		},
		zkEvm: {
			url: "https://zkevm-rpc.com",
			accounts: [privateKey],
		},
		iota: {
			url: "https://json-rpc.evm.iotaledger.net",
			accounts: [privateKey],
		},
		blast: {
			url: "https://rpc.blast.io",
			accounts: [privateKey],
		},
		mode: {
			url: "https://mainnet.mode.network",
			accounts: [privateKey],
		},
		mantle: {
			url: "https://mantle.drpc.org",
			accounts: [privateKey],
		},
		mantle2: {
			url: "https://mantle.drpc.org",
			accounts: [privateKey],
		},
		arbitrum: {
			url: "https://arbitrum.llamarpc.com",
			accounts: [privateKey],
		},
		sonic: {
			url: "https://rpc.soniclabs.com",
			accounts: [privateKey],
		},
		bera: {
			url: "https://rpc.berachain.com",
			accounts: [privateKey],
		},
	},
	etherscan: {
		apiKey: {
			arbitrumOne: arbitrumApiKey,
			iota: iotaApiKey,
			mode: modeApiKey,
			// mode2: modeApiKey,
			blast: blastApiKey,
			bsc: bnbApiKey,
			base: baseApiKey,
			polygon: polygonApiKey,
			// mantle: mantleAPIKey,
			mantle: mantle2APIKey,
			zkEvm: zkEvmApiKey,
			opbnb: opBnbApiKey,
			sonic: sonicApiKey,
			bera: beraAPIKey,
		},
		customChains: [
			// {
			// 	network: "bera",
			// 	chainId: 80094,
			// 	urls: {
			// 		apiURL: `https://api.berascan.com/api?apiKey=${beraAPIKey}`,
			// 		browserURL: "https://berascan.com",
			// 	},
			// },
			{
				network: "bera",
				chainId: 80094,
				urls: {
					apiURL: "https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan",
					browserURL: "https://beratrail.io",
				},
			},
			{
				network: "zkEvm",
				chainId: 1101,
				urls: {
					apiURL: `https://api-zkevm.polygonscan.com/api?apikey=${zkEvmApiKey}`,
					browserURL: "https://zkevm.polygonscan.com",
				},
			},
			{
				network: "opbnb",
				chainId: 204,
				urls: {
					apiURL: `https://api-opbnb.bscscan.com/api?apikey=${opBnbApiKey}`,
					browserURL: "https://opbnb.bscscan.com",
				},
			},
			{
				network: "iota",
				chainId: 8822,
				urls: {
					apiURL: "https://explorer.evm.iota.org/api",
					browserURL: "https://explorer.evm.iota.org",
				},
			},
			// {
			// 	network: "mode",
			// 	chainId: 34443,
			// 	urls: {
			// 		apiURL: "https://explorer.mode.network/api",
			// 		browserURL: "https://explorer.mode.network"
			// 	}
			// },
			{
				network: "mode",
				chainId: 34443,
				urls: {
					apiURL: "https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan",
					browserURL: "https://modescan.io",
				},
			},
			{
				network: "blast",
				chainId: 81457,
				urls: {
					apiURL: `https://api.blastscan.io/api?apiKey=${blastApiKey}`,
					browserURL: "https://blastscan.io",
				},
			},
			// {
			// 	network: "mantle",
			// 	chainId: 5000,
			// 	urls: {
			// 		apiURL: "https://explorer.mantle.xyz/api",
			// 		browserURL: "https://explorer.mantle.xyz"
			// 	}
			// },
			{
				network: "mantle",
				chainId: 5000,
				urls: {
					apiURL: "https://api.mantlescan.xyz/api",
					browserURL: "https://mantlescan.xyz",
				},
			},
			{
				network: "sonic",
				chainId: 146,
				urls: {
					apiURL: "https://api.sonicscan.org/api",
					browserURL: "https://sonicscan.org",
				},
			},
		],
	},
	paths: {
		artifacts: "./artifacts",
		cache: "./cache",
		sources: "./contracts",
		tests: "./test",
	},
	solidity: {
		version: "0.8.19",
		settings: {
			metadata: {
				// Not including the metadata hash
				// https://github.com/paulrberg/hardhat-template/issues/31
				bytecodeHash: "none",
			},
			// Disable the optimizer when debugging
			// https://hardhat.org/hardhat-network/#solidity-optimizer-support
			optimizer: {
				enabled: true,
				runs: 200,
			},
			viaIR: true,
		},
	},
	typechain: {
		outDir: "src/types",
		target: "ethers-v6",
	},
	mocha: {
		timeout: 100000000,
	},
}

export default config
