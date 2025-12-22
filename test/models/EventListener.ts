import {Subject} from "rxjs"

import {logger} from "../utils/LoggerUtils"
import {Event, QuoteStatus} from "./Enums"
import {RunContext} from "./RunContext"
import {
	AcceptCancelRequestEvent,
	AllocatePartyAEvent,
	DeallocatePartyAEvent,
	DepositEvent,
	ExpireQuoteCloseEvent,
	ExpireQuoteOpenEvent,
	FullyLiquidatedPartyBEvent,
	LiquidatePartyBEvent,
	LockQuoteEvent,
	OpenPositionForPartyAEvent,
	OpenPositionForPartyBEvent,
	RequestToCancelCloseRequestEvent,
	RequestToCancelQuoteEvent,
	RequestToClosePositionForPartyAEvent,
	RequestToClosePositionForPartyBEvent,
	SendQuoteForPartyAEvent,
	SendQuoteForPartyBEvent,
	UnlockQuoteEvent,
	WithdrawEvent
} from "../../src/types/contracts/interfaces/ISymmio"

export class EventListener {
	queues: Map<QuoteStatus, Subject<bigint>> = new Map([
		[QuoteStatus.PENDING, new Subject<bigint>()],
		[QuoteStatus.LOCKED, new Subject<bigint>()],
		[QuoteStatus.CANCEL_PENDING, new Subject<bigint>()],
		[QuoteStatus.CANCELED, new Subject<bigint>()],
		[QuoteStatus.OPENED, new Subject<bigint>()],
		[QuoteStatus.CLOSE_PENDING, new Subject<bigint>()],
		[QuoteStatus.CANCEL_CLOSE_PENDING, new Subject<bigint>()],
		[QuoteStatus.CLOSED, new Subject<bigint>()],
		[QuoteStatus.LIQUIDATED, new Subject<bigint>()],
		[QuoteStatus.EXPIRED, new Subject<bigint>()],
	])

	eventTrackQueues: Map<Event, Subject<any>> = new Map<Event, Subject<any>>([
		[Event.SEND_QUOTE_FOR_PARTY_A, new Subject<SendQuoteForPartyAEvent.OutputObject>()],
		[Event.SEND_QUOTE_FOR_PARTY_B, new Subject<SendQuoteForPartyBEvent.OutputObject>()],
		[Event.REQUEST_TO_CANCEL_QUOTE, new Subject<RequestToCancelQuoteEvent.OutputObject>()],
		[Event.REQUEST_TO_CLOSE_POSITION_FOR_PARTY_A, new Subject<RequestToClosePositionForPartyAEvent.OutputObject>()],
		[Event.REQUEST_TO_CLOSE_POSITION_FOR_PARTY_B, new Subject<RequestToClosePositionForPartyBEvent.OutputObject>()],
		[Event.REQUEST_TO_CANCEL_CLOSE_REQUEST, new Subject<RequestToCancelCloseRequestEvent.OutputObject>()],
		[Event.LOCK_QUOTE, new Subject<LockQuoteEvent.OutputObject>()],
		[Event.UNLOCK_QUOTE, new Subject<UnlockQuoteEvent.OutputObject>()],
		[Event.ACCEPT_CANCEL_REQUEST, new Subject<AcceptCancelRequestEvent.OutputObject>()],
		[Event.OPEN_POSITION, new Subject<OpenPositionForPartyAEvent.OutputObject>()],
		[Event.ACCEPT_CANCEL_CLOSE_REQUEST, new Subject<any>()],
		[Event.FILL_CLOSE_REQUEST, new Subject<any>()],
		[Event.DEPOSIT, new Subject<DepositEvent.OutputObject>()],
		[Event.WITHDRAW, new Subject<WithdrawEvent.OutputObject>()],
		[Event.ALLOCATE_PARTYA, new Subject<AllocatePartyAEvent.OutputObject>()],
		[Event.DEALLOCATE_PARTYA, new Subject<DeallocatePartyAEvent.OutputObject>()],
		[Event.LIQUIDATE_PARTYA, new Subject<any>()],
		[Event.LIQUIDATE_POSITIONS_PARTYA, new Subject<any>()],
		[Event.LIQUIDATE_PARTYB, new Subject<LiquidatePartyBEvent.OutputObject>()],
		[Event.LIQUIDATE_POSITIONS_PARTYB, new Subject<any>()],
		[Event.FULLY_LIQUIDATED_PARTYB, new Subject<FullyLiquidatedPartyBEvent.OutputObject>()],
		[Event.EXPIRE_QUOTE_OPEN, new Subject<ExpireQuoteOpenEvent.OutputObject>()],
		[Event.EXPIRE_QUOTE_CLOSE, new Subject<ExpireQuoteCloseEvent.OutputObject>()],
	])

	constructor(public context: RunContext) {
		;(context.partyAFacet.runner as any).pollingInterval = 500 // was .provider !
		;(context.partyBPositionActionsFacet.runner as any).pollingInterval = 500 // was .provider !
		;(context.partyBQuoteActionsFacet.runner as any).pollingInterval = 500 // was .provider !

		context.accountFacet.on(context.accountFacet.filters.Deposit, async (...args) => {
			let value: DepositEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			this.eventTrackQueues.get(Event.DEPOSIT)!.next(value)
		})

		context.accountFacet.on(context.accountFacet.filters.Withdraw, async (...args) => {
			let value: WithdrawEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			this.eventTrackQueues.get(Event.WITHDRAW)!.next(value)
		})

		context.accountFacet.on(context.accountFacet.filters.AllocatePartyA, async (...args) => {
			let value: AllocatePartyAEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			this.eventTrackQueues.get(Event.ALLOCATE_PARTYA)!.next(value)
		})

		context.accountFacet.on(context.accountFacet.filters.DeallocatePartyA, async (...args) => {
			let value: DeallocatePartyAEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			this.eventTrackQueues.get(Event.DEALLOCATE_PARTYA)!.next(value)
		})

		context.partyAFacet.on(context.partyAFacet.filters.SendQuoteForPartyA, async (...args) => {
			let value: SendQuoteForPartyAEvent.OutputObject = (args[args.length - 1]! as any).args
			this.eventTrackQueues.get(Event.SEND_QUOTE_FOR_PARTY_A)!.next(value)
			this.queues.get(QuoteStatus.PENDING)!.next(value.quoteId)
		})
		context.partyAFacet.on(context.partyAFacet.filters.RequestToCancelQuote, async (...args) => {
			let value: RequestToCancelQuoteEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			this.eventTrackQueues.get(Event.REQUEST_TO_CANCEL_QUOTE)!.next(value)
			this.queues.get(QuoteStatus.CANCEL_PENDING)!.next(value.quoteId)
		})
		context.partyAFacet.on(context.partyAFacet.filters.RequestToClosePositionForPartyB, async (...args) => {
			let value: RequestToClosePositionForPartyBEvent.OutputObject = (args[args.length - 1]! as any).args
			logger.detailedEventDebug("RequestToClosePositionForPartyB event received")
			logger.detailedEventDebug(value)
			this.eventTrackQueues.get(Event.REQUEST_TO_CLOSE_POSITION_FOR_PARTY_B)!.next(value)
			this.queues.get(QuoteStatus.CLOSE_PENDING)!.next(value.quoteId)
		})
		context.partyAFacet.on(context.partyAFacet.filters.RequestToCancelCloseRequest, async (...args) => {
			let value: RequestToCancelCloseRequestEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			this.eventTrackQueues.get(Event.REQUEST_TO_CANCEL_CLOSE_REQUEST)!.next(value)
			this.queues.get(QuoteStatus.CANCEL_CLOSE_PENDING)!.next(value.quoteId)
		})
		context.partyBQuoteActionsFacet.on(context.partyBQuoteActionsFacet.filters.LockQuote, async (...args) => {
			let value: LockQuoteEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			logger.detailedEventDebug("LockQuote event received")
			logger.detailedEventDebug(value)
			this.eventTrackQueues.get(Event.LOCK_QUOTE)!.next(value)
			this.queues.get(QuoteStatus.LOCKED)!.next(value.quoteId)
		})
		context.partyBQuoteActionsFacet.on(context.partyBQuoteActionsFacet.filters.UnlockQuote, async (...args) => {
			let value: UnlockQuoteEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			logger.detailedEventDebug("UnLockQuote event received")
			logger.detailedEventDebug(value)
			this.eventTrackQueues.get(Event.UNLOCK_QUOTE)!.next(value)
			this.queues.get(QuoteStatus.PENDING)!.next(value.quoteId)
		})
		context.partyBQuoteActionsFacet.on(context.partyBQuoteActionsFacet.filters.AcceptCancelRequest, async (...args) => {
			let value: AcceptCancelRequestEvent.OutputObject = (args[args.length - 1]! as any).args //FIXME: Will probably not work
			logger.detailedEventDebug("AcceptCancelRequest event received")
			logger.detailedEventDebug(value)
			this.eventTrackQueues.get(Event.ACCEPT_CANCEL_REQUEST)!.next(value)
			this.queues.get(QuoteStatus.CANCELED)!.next(value.quoteId)
		})
		// Listen for new encrypted OpenPosition events
		context.partyBPositionActionsFacet.on(context.partyBPositionActionsFacet.filters.OpenPositionForPartyA, async (...args) => {
			let value: OpenPositionForPartyAEvent.OutputObject = (args[args.length - 1]! as any).args
			logger.detailedEventDebug("OpenPositionForPartyA event received (encrypted)")
			logger.detailedEventDebug(value)
			// Extract quoteId from encrypted event
			const eventValue: any = {
				quoteId: value.quoteId,
				partyA: value.partyA,
				partyB: value.partyB,
				values: value.values // Encrypted values
			}
			this.eventTrackQueues.get(Event.OPEN_POSITION)!.next(eventValue)
			this.queues.get(QuoteStatus.OPENED)!.next(value.quoteId)
		})
		context.partyBPositionActionsFacet.on(context.partyBPositionActionsFacet.filters.OpenPositionForPartyB, async (...args) => {
			let value: OpenPositionForPartyBEvent.OutputObject = (args[args.length - 1]! as any).args
			logger.detailedEventDebug("OpenPositionForPartyB event received (encrypted)")
			logger.detailedEventDebug(value)
			// This event is for Party B's perspective, already tracked via PartyA event
		})
		// Note: AcceptCancelCloseRequest and FillCloseRequest events are handled via PartyBGroupActionsFacet
		// but these events have changed and may not be directly trackable with new encrypted events
		// Event listeners are commented out until proper event filters are available
		
		// context.partyBGroupActionsFacet.on("AcceptCancelCloseRequest", async (...args: any[]) => {
		// 	let value = (args[args.length - 1]! as any).args
		// 	logger.detailedEventDebug("AcceptCancelCloseRequest event received")
		// 	logger.detailedEventDebug(value)
		// 	this.eventTrackQueues.get(Event.ACCEPT_CANCEL_CLOSE_REQUEST)!.next(value)
		// 	this.queues.get(QuoteStatus.OPENED)!.next(value.quoteId)
		// })
		
		// context.partyBGroupActionsFacet.on("FillCloseRequest", async (...args: any[]) => {
		// 	let value = (args[args.length - 1]! as any).args
		// 	logger.detailedEventDebug("FillCloseRequest event received")
		// 	logger.detailedEventDebug(value)
		// 	this.eventTrackQueues.get(Event.FILL_CLOSE_REQUEST)!.next(value)
		// 	let id = value.quoteId
		// 	if (value.quoteStatus == BigInt(QuoteStatus.CLOSED)) this.queues.get(QuoteStatus.CLOSED)!.next(id)
		// 	else this.queues.get(QuoteStatus.OPENED)!.next(id)
		// })

		try {
			//Contract dev logging
			// Add logging capabilities here if needed
		} catch (ex) {
		}
	}
}
