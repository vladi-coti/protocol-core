import { task } from "hardhat/config"

task("create-wallets", "Creates 10 new wallets and transfers 1 native token to each")
	.addOptionalParam("count", "Number of wallets to create", "10")
	.addOptionalParam("amount", "Amount of native tokens to transfer to each wallet", "1")
	.setAction(async ({ count, amount }, { ethers }) => {
		const walletCount = parseInt(count)
		const transferAmount = ethers.parseEther(amount)

		console.log(`Creating ${walletCount} new wallets and transferring ${amount} native token(s) to each...`)

		// Get the main account
		const [mainSigner] = await ethers.getSigners()
		console.log("Main account address:", mainSigner.address)

		// Check main account balance
		const mainBalance = await ethers.provider.getBalance(mainSigner.address)
		console.log("Main account balance:", ethers.formatEther(mainBalance), "ETH")

		// Check if main account has enough balance
		const totalRequired = transferAmount * BigInt(walletCount)
		const estimatedGas = BigInt(21000) * BigInt(walletCount) * ethers.parseUnits("1.2", "gwei")
		const totalWithGas = totalRequired + estimatedGas

		if (mainBalance < totalWithGas) {
			throw new Error(`Insufficient balance. Required: ${ethers.formatEther(totalWithGas)} ETH, Available: ${ethers.formatEther(mainBalance)} ETH`)
		}

		// Arrays to store wallet info
		const privateKeys: string[] = []
		const addresses: string[] = []

		// Generate wallets
		console.log("\nGenerating wallets...")
		for (let i = 0; i < walletCount; i++) {
			const wallet = ethers.Wallet.createRandom()
			privateKeys.push(wallet.privateKey)
			addresses.push(wallet.address)
			console.log(`Wallet ${i + 1}: ${wallet.address}`)
		}

		// Get network-specific gas options
		const network = await ethers.provider.getNetwork()
		let gasOptions = {}

		if (network.chainId === 7082400n) {
			// COTI testnet
			gasOptions = {
				gasLimit: 21000,
				gasPrice: ethers.parseUnits("1.2", "gwei"),
			}
		}

		// Transfer tokens to each wallet
		console.log(`\nTransferring ${amount} native token(s) to each wallet...`)

		for (let i = 0; i < walletCount; i++) {
			try {
				console.log(`Transferring to wallet ${i + 1} (${addresses[i]})...`)

				const tx = await mainSigner.sendTransaction({
					to: addresses[i],
					value: transferAmount,
					...gasOptions,
				})

				console.log(`Transaction ${i + 1} sent: ${tx.hash}`)
				await tx.wait()
				console.log(`Transaction ${i + 1} confirmed`)

				// Verify balance
				const balance = await ethers.provider.getBalance(addresses[i])
				console.log(`Wallet ${i + 1} balance: ${ethers.formatEther(balance)} ETH`)
			} catch (error) {
				console.error(`Error transferring to wallet ${i + 1}:`, error)
			}

			// Small delay to prevent nonce conflicts
			if (i < walletCount - 1) {
				await new Promise(resolve => setTimeout(resolve, 1500))
			}
		}

		// Output results
		console.log("\n" + "=".repeat(80))
		console.log("WALLET CREATION COMPLETED")
		console.log("=".repeat(80))

		console.log("\nPrivate Keys (comma-separated):")
		console.log(privateKeys.join(","))

		console.log("\nAddresses (comma-separated):")
		console.log(addresses.join(","))

		console.log("\nFor .env file (PRIVATE_KEYS_STR):")
		console.log(privateKeys.join(","))

		// Final balances
		console.log("\nFinal balances:")
		for (let i = 0; i < walletCount; i++) {
			try {
				const balance = await ethers.provider.getBalance(addresses[i])
				console.log(`Wallet ${i + 1}: ${ethers.formatEther(balance)} ETH`)
			} catch (error) {
				console.log(`Wallet ${i + 1}: Error checking balance`)
			}
		}

		// Main account final balance
		const finalMainBalance = await ethers.provider.getBalance(mainSigner.address)
		console.log(`\nMain account final balance: ${ethers.formatEther(finalMainBalance)} ETH`)

		console.log("\nScript completed successfully!")
	})
