import { BigNumberish, ethers, EventLog } from "ethers"
import { Wallet, itUint } from "@coti-io/coti-ethers"
import { User } from "./User"
import { RunContext } from "./RunContext"
import { PositionType, OrderType } from "./Enums"
import { decimal, serializeToJson } from "../utils/Common"
import { logger } from "../utils/LoggerUtils"

export interface PrivateQuoteRequest {
	partyBWhiteList: string[]
	symbolId: BigNumberish
	positionType: PositionType
	orderType: OrderType
	price: BigNumberish
	quantity: BigNumberish
	cva: BigNumberish
	lf: BigNumberish
	partyAmm: BigNumberish
	partyBmm: BigNumberish
	maxFundingRate: BigNumberish
	deadline: Promise<BigNumberish>
	affiliate: string
	upnlSig: any
}

export class PrivateUser extends User {
	private privateWallet: Wallet

	constructor(context: RunContext, wallet: Wallet) {
		const regularSigner = {
			address: wallet.address,
			getAddress: () => Promise.resolve(wallet.address),
			signMessage: wallet.signMessage.bind(wallet),
			signTransaction: wallet.signTransaction.bind(wallet),
			connect: (provider: any) => wallet.connect(provider),
			sendTransaction: wallet.sendTransaction.bind(wallet),
		} as any

		super(context, regularSigner)
		this.privateWallet = wallet
	}

	public getPrivateWallet(): Wallet {
		return this.privateWallet
	}

	public async encryptValue(value: bigint, contractAddress: string, selector: string): Promise<itUint> {
		return (await this.privateWallet.encryptValue(value, contractAddress, selector)) as itUint
	}

	public async decryptValue(ciphertext: any): Promise<bigint | string> {
		return await this.privateWallet.decryptValue(ciphertext)
	}

	public async sendPrivateQuote(request: PrivateQuoteRequest): Promise<bigint> {
		logger.detailedDebug(
			serializeToJson({
				request: request,
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)

		const contractAddress = this.context.diamond
		const selector = this.context.privatePartyAFacet.interface.getFunction("sendPrivateQuote")!.selector

		const encryptedPrice = await this.encryptValue(BigInt(request.price.toString()), contractAddress, selector)
		const encryptedQuantity = await this.encryptValue(BigInt(request.quantity.toString()), contractAddress, selector)
		const encryptedCva = await this.encryptValue(BigInt(request.cva.toString()), contractAddress, selector)
		const encryptedLf = await this.encryptValue(BigInt(request.lf.toString()), contractAddress, selector)
		const encryptedPartyAmm = await this.encryptValue(BigInt(request.partyAmm.toString()), contractAddress, selector)
		const encryptedPartyBmm = await this.encryptValue(BigInt(request.partyBmm.toString()), contractAddress, selector)

		const basicParams = {
			partyBsWhiteList: request.partyBWhiteList,
			symbolId: request.symbolId,
			positionType: request.positionType,
			orderType: request.orderType,
			maxFundingRate: request.maxFundingRate,
			deadline: await request.deadline,
			affiliate: request.affiliate,
		}

		const encryptedParams = {
			encryptedPrice,
			encryptedQuantity,
			encryptedCva,
			encryptedLf,
			encryptedPartyAmm,
			encryptedPartyBmm,
		}

		// Connect the private wallet to the diamond contract
		const diamondWithPrivateWallet = this.context.privatePartyAFacet.connect(this.privateWallet)

		let tx = await diamondWithPrivateWallet.sendPrivateQuote(basicParams, encryptedParams, await request.upnlSig)

		const receipt = await tx.wait()

		if (receipt && receipt.logs) {
			const sendQuotePublicEvent = receipt.logs.find((log: any): log is EventLog => {
				return (log as EventLog).eventName === "SendPrivateQuotePublic"
			})

			if (sendQuotePublicEvent && sendQuotePublicEvent.args) {
				const id = sendQuotePublicEvent.args.quoteId
				logger.info("PrivateUser::::SendPrivateQuote: " + id)
				return id.toString()
			}
		}
		throw new Error("SendPrivateQuotePublic event not found in transaction receipt")
	}

	public static createDefaultPrivateQuoteRequest(): PrivateQuoteRequest {
		return {
			partyBWhiteList: [],
			symbolId: 1,
			positionType: PositionType.LONG,
			orderType: OrderType.LIMIT,
			price: decimal(1000n),
			quantity: decimal(100n),
			cva: decimal(50n),
			lf: decimal(25n),
			partyAmm: decimal(75n),
			partyBmm: decimal(75n),
			maxFundingRate: decimal(5n),
			deadline: Promise.resolve(Math.floor(Date.now() / 1000) + 1000),
			affiliate: ethers.ZeroAddress,
			upnlSig: null,
		}
	}
}
