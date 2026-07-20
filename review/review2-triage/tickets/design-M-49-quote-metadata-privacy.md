---
id: design-M-49-quote-metadata-privacy
labels: [group:design-product, wayfinder:grilling]
priority: P2
finding: M-49
severity: Medium
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-49: Decide quote metadata privacy scope — Which quote metadata must be private vs acceptable public?

## Auditor claim

Medium severity. See [report §M-49](../report.md).

## Code references

`PartyAFacet.sol`; `QuoteStorage.sol`; `ViewFacet` quote views

## Suggested test seam

N/A — grilling session

## Auditor recommendation

Document public metadata; encrypt/commit rest if needed

## Resolution checklist

- [x] Read cited code paths in current branch
- [x] Grill / decide policy
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] Unblock privacy-P3-M-49

## Answer

**Decision:** **numbers-only** privacy.

Encrypt economic magnitudes (price, quantity, locked values, fees). Keep matching/routing metadata public: symbol, side (`positionType`), order type, deadline, affiliate, PartyB whitelist, ids/status/timestamps.

Intent-privacy (hide symbol/side/whitelist) would need commit-reveal or encrypted metadata + matching redesign — out of scope.

**Gates:** [privacy-P3-M-49](privacy-P3-M-49.md) closed as design-choice / wontfix.
