import {interval} from "rxjs"
import {join} from "path"
import {Hedger} from "./models/Hedger"
import {HedgerController} from "./models/HedgerController"
import {ManagedError} from "./models/ManagedError"
import {createRunContext, RunContext} from "./models/RunContext"
import {User} from "./models/User"
import {UserController} from "./models/UserController"
import {decimal} from "./utils/Common"
import fsPromise from "fs/promises"
import {QuoteCheckpoint} from "./models/quoteCheckpoint"

const ACTION_LOOP_INTERVAL_MS = 10000 // 10 seconds between actions
const ACTION_LOOP_DURATION_MS = 600000 // 10 minutes total duration

export function shouldBehaveLikeFuzzTest(): void {
	beforeEach(async function () {
		const addressesPath = join(__dirname, "..", "output", "addresses.json")
		const addresses = JSON.parse(await fsPromise.readFile(addressesPath, "utf8"))

		const {symmioAddress, collateralAddress, multiAccountAddress} = addresses
		if (!symmioAddress || !collateralAddress || !multiAccountAddress) {
			throw new Error("Missing deployment data in output/addresses.json. Run scripts/Initialize.ts first.")
		}

		this.context = await createRunContext(symmioAddress, collateralAddress, multiAccountAddress)
	})

	it("Should run fine", async function () {
		const context: RunContext = this.context
		const manager = context.manager
		const checkpoint = QuoteCheckpoint.getInstance()

		const uSigner = context.signers.user
		const user = new User(context, uSigner)
		await user.setup()
		// await user.setNativeBalance(100n ** 18n)
		const userController = new UserController(manager, user, checkpoint)

		const hSigner = context.signers.hedger
		const hedger = new Hedger(context, hSigner)
		await hedger.setup()
		// await hedger.setNativeBalance(100n ** 18n)
		await hedger.setBalances(decimal(1000000n), decimal(1000000n))
		await hedger.register()
		const hedgerController = new HedgerController(manager, hedger, checkpoint)

		await userController.start()
		await hedgerController.start()
		await user.setBalances(decimal(100000n), decimal(100000n), decimal(100000n))

		// Track statistics
		let totalAttempts = 0
		let successfulQuotes = 0
		let transactionReverts = 0
		let otherErrors = 0

		const subscription = interval(ACTION_LOOP_INTERVAL_MS).subscribe(() => {
			manager.actionsLoop.next({
				title: "SendQuote",
				action: () => {
					return new Promise((resolve, reject) => {
						if (manager.getPauseState()) {
							reject()
						}
						totalAttempts++
						userController
							.sendQuote()
							.then(() => {
								successfulQuotes++
								resolve()
							})
							.catch(error => {
								if (error instanceof ManagedError) {
									if (error.message.indexOf("Insufficient funds available") >= 0) {
										console.error(error.message)
										subscription.unsubscribe()
										resolve()
									} else if (error.message.indexOf("Too many open quotes") >= 0) {
										// Expected, continue
										resolve()
									} else if (error.message.indexOf("Transaction reverted") >= 0) {
										transactionReverts++
										// Continue fuzzing, but track the revert
										resolve()
									} else {
										otherErrors++
										resolve()
									}
								} else {
									otherErrors++
									reject(error)
									process.exitCode = 1
									console.error(error)
								}
							})
					})
				},
			})
		})

		await new Promise(r => setTimeout(r, ACTION_LOOP_DURATION_MS))
		subscription.unsubscribe()

		// Calculate failure rate
		const totalFailures = transactionReverts + otherErrors
		const failureRate = totalAttempts > 0 ? (totalFailures / totalAttempts) * 100 : 0

		console.log(`\nFuzz Test Statistics:`)
		console.log(`  Total attempts: ${totalAttempts}`)
		console.log(`  Successful quotes: ${successfulQuotes}`)
		console.log(`  Transaction reverts: ${transactionReverts}`)
		console.log(`  Other errors: ${otherErrors}`)
		console.log(`  Failure rate: ${failureRate.toFixed(2)}%`)

		// Fail the test if failure rate is too high (> 80%)
		if (failureRate > 80 && totalAttempts >= 3) {
			throw new Error(
				`Fuzz test failure rate too high: ${failureRate.toFixed(2)}% (${totalFailures}/${totalAttempts} failures). ` +
				`This suggests a systemic issue with quote generation or encrypted validation.`
			)
		}

		// Warn if failure rate is high but not critical
		if (failureRate > 50 && totalAttempts >= 3) {
			console.warn(`Warning: High failure rate: ${failureRate.toFixed(2)}%`)
		}
	})
}
