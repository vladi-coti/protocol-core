# Privacy Changes Overview

This document summarizes the privacy-focused changes that distinguish the `privacy` branch from `main`. The update integrates COTI’s MPC primitives throughout the SYMM protocol so that all sensitive quote data can stay encrypted end-to-end.

---

## 1. Entry-Point Encryption

| Component | What changed | Result |
| --- | --- | --- |
| `PartyAFacet` (`sendQuote`, `requestToClosePosition`) | Accepts `QuoteBasicParams` plus `PrivateQuoteParams` (all ciphertexts validated through `MpcCore`). Emits new `SendQuoteForPartyA/B` and `RequestToClosePositionForPartyA/B` events with values off-boarded per party’s encryption address. | PartyA can publish fully encrypted quotes and close requests; each party only sees data encrypted for them. |
| `PartyBPositionActionsFacetImpl` | `openPosition`, `fillCloseRequest`, and emergency-close all consume encrypted filled amounts/prices (`gtUint256`). Solvency checks run on encrypted balances before any decrypted comparison. | PartyB never de-encrypts PartyA data; on-chain validation happens in MPC space. |
| Tests & controllers | Test models (`Hedger`, `User`, controllers, validators) and fixtures now decrypt using the correct wallet (PartyA vs PartyB), ensuring fuzz/static tests exercise the MPC flow. | Local tooling mirrors privacy behaviour. |

---

## 2. Storage & Data Layout

| Area | Changes | Notes |
| --- | --- | --- |
| `QuoteStorage` | Quote economics (`openedPrice`, `requestedOpenPrice`, `quantity`, `lockedValues`, `tradingFee`, etc.) migrate from `uint256` to `ut/ct/gt` structures. Helper structs (`EncryptedQuoteValues`, `PrivateQuoteParams`, `PrivateOpen/ClosePositionParams`) capture encryptable payloads for entry points and events. | Every quote can operate entirely with encrypted values while still tracking whitelist, timestamps, and affiliate in plaintext. |
| `AccountStorage` | Allocated balances, PartyB-per-PartyA ledgers, settlement states, and reserve tracking all store encrypted values. A `userEncryptionAddress` map resolves the wallet used for off-boarding ciphertexts. | Prevents uninitialized “garbage” by pairing with initializer helpers in `LibAccount`. |
| Locked values | `LockedValues` now represent ciphertexts; `GarbledLockedValues` and `UserLockedValues` provide MPC/on-chain views to avoid recomputing conversions. | Shared across PartyA and PartyB logic. |

---

## 3. Contract Libraries & Facets

| File | Highlights |
| --- | --- |
| `LibLockedValues` | Introduces `safeOnboard`, `onBoard`, `offBoard`, arithmetic helpers, and zero-initializers so storage always contains valid ciphertext before arithmetic. |
| `LibAccount` | All balance math (available for quotes, solvency, liquidation) now uses encrypted arithmetic via `MpcCore`. Adds `getUserEncryptionAddress`, `initializePartyA`, `initializePartyB`, and settlement-state helpers. |
| `LibSolvency` | Works directly with encrypted filled amounts and prices, only decrypting the final balance comparison. |
| `PartyA/PartyB facets` | Emit dual encrypted events, validate ciphertext inputs, and interact with the updated libs so every state transition respects privacy. |
| `LibPartyBPositionsActions`, `LibQuote`, `LibSettlement`, etc. | Updated to read/write encrypted structs, scale locked values using MPC math, and keep events in sync. |

---

## Encryption Process Complete Example: Sending a Quote

```typescript
import { ethers } from "hardhat";

async function sendEncryptedQuote() {
    // 1. Get contract instances
    const partyAFacet = await ethers.getContractAt("PartyAFacet", diamondAddress);
    const wallet = /* your COTI wallet instance */;
    
    // 2. Prepare plaintext parameters
    const basicParams = {
        partyBsWhiteList: [hedgerAddress],
        symbolId: 1,
        positionType: 0, // LONG
        orderType: 0,   // LIMIT
        maxFundingRate: 0,
        deadline: Math.floor(Date.now() / 1000) + 900,
        affiliate: ethers.ZeroAddress,
    };
    
    // 3. Get function selector
    const selector = partyAFacet.interface.getFunction("sendQuote").selector;
    const contractAddress = diamondAddress;
    
    // 4. Encrypt all sensitive values
    const encryptedPrice = await wallet.encryptUint256(
        BigInt("1000000000000000000"), // 1.0 in 18 decimals
        contractAddress,
        selector
    );
    
    const encryptedQuantity = await wallet.encryptUint256(
        BigInt("5000000000000000000"), // 5.0 in 18 decimals
        contractAddress,
        selector
    );
    
    const encryptedCva = await wallet.encryptUint256(
        BigInt("100000000000000000"), // 0.1 in 18 decimals
        contractAddress,
        selector
    );
    
    // ... encrypt LF, partyAmm, partyBmm similarly
    
    // 5. Build encrypted parameters
    const privateQuoteParams = {
        encryptedPrice,
        encryptedQuantity,
        encryptedCva,
        encryptedLf,
        encryptedPartyAmm,
        encryptedPartyBmm,
    };
    
    // 6. Get UPNL signature (implementation depends on your setup)
    const upnlSig = await getUpnlSignature();
    
    // 7. Send transaction
    const tx = await partyAFacet.connect(signer).sendQuote(
        basicParams,
        privateQuoteParams,
        upnlSig
    );
    
    await tx.wait();
    console.log("Quote sent:", tx.hash);
}
```

This document should be kept up-to-date as additional privacy-related work lands so downstream teams can easily track the delta versus `main`.

