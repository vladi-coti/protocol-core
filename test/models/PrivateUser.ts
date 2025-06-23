import { ethers, EventLog } from "ethers";
import { Wallet, ctUint256, itUint256 } from "@coti-io/coti-ethers";
import { User } from "./User";
import { RunContext } from "./RunContext";
import { PositionType, OrderType } from "./Enums";
import { serializeToJson } from "../utils/Common";
import { logger } from "../utils/LoggerUtils";
import { PrivateQuoteParamsStruct, QuoteBasicParamsStruct } from "../../src/types/contracts/facets/PartyA/IPrivatePartyAFacet";

export interface PrivateQuoteRequest {
	partyBWhiteList: string[];
	symbolId: bigint;
	positionType: PositionType;
	orderType: OrderType;
	price: bigint;
	quantity: bigint;
	cva: bigint;
	lf: bigint;
	partyAmm: bigint;
	partyBmm: bigint;
	maxFundingRate: bigint;
	deadline: Promise<bigint>;
	affiliate: string;
	upnlSig: any;
}

export class PrivateUser extends User {
	private privateWallet: Wallet;

	constructor(context: RunContext, wallet: Wallet) {
		super(context, wallet as any);
		this.privateWallet = wallet;
	}

	public getPrivateWallet(): Wallet {
		return this.privateWallet;
	}

	public async encryptUint256(value: bigint, contractAddress: string, selector: string): Promise<itUint256> {
		return await this.privateWallet.encryptUint256(value, contractAddress, selector);
	}

	public async decryptUint256(ciphertext: ctUint256): Promise<bigint> {
		return await this.privateWallet.decryptUint256(ciphertext);
	}

	public async sendPrivateQuote(request: PrivateQuoteRequest): Promise<bigint> {
		logger.detailedDebug(
			serializeToJson({
				request: request,
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		);

		const contractAddress = this.context.diamond;
		const functionFragment = this.context.privatePartyAFacet.interface.getFunction("sendPrivateQuote");
		const selector = functionFragment.selector;

		const basicParams: QuoteBasicParamsStruct = {
			partyBsWhiteList: request.partyBWhiteList,
			symbolId: request.symbolId,
			positionType: request.positionType,
			orderType: request.orderType,
			maxFundingRate: request.maxFundingRate,
			deadline: await request.deadline,
			affiliate: request.affiliate,
		};

		const encryptedPrice = await this.encryptUint256(request.price, contractAddress, selector);
		const encryptedQuantity = await this.encryptUint256(request.quantity, contractAddress, selector);
		const encryptedCva = await this.encryptUint256(request.cva, contractAddress, selector);
		const encryptedLf = await this.encryptUint256(request.lf, contractAddress, selector);
		const encryptedPartyAmm = await this.encryptUint256(request.partyAmm, contractAddress, selector);
		const encryptedPartyBmm = await this.encryptUint256(request.partyBmm, contractAddress, selector);

		const encryptedParams: PrivateQuoteParamsStruct = {
			encryptedPrice: encryptedPrice,
			encryptedQuantity: encryptedQuantity,
			encryptedCva: encryptedCva,
			encryptedLf: encryptedLf,
			encryptedPartyAmm: encryptedPartyAmm,
			encryptedPartyBmm: encryptedPartyBmm,
		};

		// Connect the private wallet to the diamond contract
		const diamondWithPrivateWallet = this.context.privatePartyAFacet.connect(this.privateWallet);

		let tx = await diamondWithPrivateWallet.sendPrivateQuote(basicParams, encryptedParams, await request.upnlSig);

		const receipt = await tx.wait();

		if (receipt && receipt.logs) {
			const sendQuotePublicEvent = receipt.logs.find((log: any): log is EventLog => {
				return (log as EventLog).eventName === "SendPrivateQuotePublic";
			});

			if (sendQuotePublicEvent && sendQuotePublicEvent.args) {
				const id = sendQuotePublicEvent.args.quoteId;
				logger.info("PrivateUser::::SendPrivateQuote: " + id);
				return id.toString();
			}
		}
		throw new Error("SendPrivateQuotePublic event not found in transaction receipt");
	}

	public static createDefaultPrivateQuoteRequest(partyBWhiteList: string[]): PrivateQuoteRequest {
		return {
			partyBWhiteList: partyBWhiteList,
			symbolId: 1n,
			positionType: PositionType.LONG,
			orderType: OrderType.LIMIT,
			// price: decimal(1000n),
			// quantity: decimal(100n),
			// cva: decimal(50n),
			// lf: decimal(25n),
			// partyAmm: decimal(75n),
			// partyBmm: decimal(75n),
			// maxFundingRate: decimal(5n),
			// Use smaller values that fit within 64-bit encryption limit
			price: 1000000n, // 1,000,000 (fits in 64 bits)
			quantity: 100000n, // 100,000 (fits in 64 bits)
			cva: 50000n, // 50,000 (fits in 64 bits)
			lf: 25000n, // 25,000 (fits in 64 bits)
			partyAmm: 75000n, // 75,000 (fits in 64 bits)
			partyBmm: 75000n, // 75,000 (fits in 64 bits)
			maxFundingRate: 5000n, // 5,000 (fits in 64 bits)
			deadline: Promise.resolve(BigInt(Math.floor(Date.now() / 1000) + 1000)),
			affiliate: ethers.ZeroAddress,
			upnlSig: null,
		};
	}
}
