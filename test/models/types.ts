import { SendQuoteForPartyBEvent } from "../../src/types/contracts/interfaces/ISymmio"

export type QuoteData = { quoteId: bigint; partyBEvent: SendQuoteForPartyBEvent.OutputObject | undefined }
