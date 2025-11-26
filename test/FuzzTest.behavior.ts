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

		const subscription = interval(10000).subscribe(() => {
			manager.actionsLoop.next({
				title: "SendQuote",
				action: () => {
					return new Promise((resolve, reject) => {
						if (manager.getPauseState()) {
							reject()
						}
						userController
							.sendQuote()
							.then(() => {
								resolve()
							})
							.catch(error => {
								if (error instanceof ManagedError) {
									if (error.message.indexOf("Insufficient funds available") >= 0) {
										console.error(error.message)
										subscription.unsubscribe()
									} else if (error.message.indexOf("Too many open quotes") >= 0) {
										// DO nothing
									}
									resolve()
								} else {
									reject(error)
									process.exitCode = 1
									console.error(error)
								}
							})
					})
				},
			})
		})

		await new Promise(r => setTimeout(r, 200000))
	})
}
