# Sim vs testnet

Purpose: see which audit tests agree on sim (`localSimCoti`) vs COTI testnet so we can prefer sim for speed.

**Policy:** after each closed validation ticket, dual-run the same `--grep` and add one row here (do not skip for “sim-only” unless the user says so).

```bash
# sim: cd /home/vld/coti/sim-coti-node && npm start   # or mac path
python3 utils/update_sig_checks.py 1
./review/review2-triage/scripts/run-dual-network-test.sh '<grep>' <test-file.ts> '<short name>'
```

| Test | Sim | Testnet | Details |
| --- | --- | --- | --- |
| H-12 third-party settleAndForceClose | PASS | PASS | Logic matches. Testnet needs `gasOptions.gasLimit` ≥120M for success path; force-close cooldowns ~minutes. |
| H-14 partial-reserve force-close liquidate | PASS | PASS | Fix: pass `gtWithReserve` into `liquidatePartyBFromAvailable`. Agree on both. |
| H-15 remainingLf > alloc (+UPNL) liquidate | PASS | PASS | Cap remainingLf to alloc; re-dual after LibAccount available-balance mux fix |
| H-16 deferred type uses signed alloc snapshot | PASS | PASS | `deferredSetSymbolsPrice` + reimbursement use `liquidationAllocatedBalance`. |
| H-26 force-close LF unlock before PartyB liq | PASS | PASS | Unlock closed-quote cva+lf on PartyB locks before liquidatePartyBFromAvailable |
| H-08 allocate/internalTransfer free-balance before limit | PASS | PASS | Public balance require before encrypted allocated-limit decrypt |
| H-04 force-close Muon before price decrypt | PASS | PASS | verifyHighLowPrice before requestedClosePrice onboard; testnet has force-close cooldown |
| H-32 emergency close insolvency vs liquidation | PASS | PASS | design-choice: solvency gate intentional; liq still works in PartyB emergency |
| H-33 fee distributor encrypted claim | PASS | PASS | claimAllFeeCollectorBalance before getClaimable/withdraw |
| H-34 force close after deadline | PASS | PASS | require block.timestamp <= quote.deadline |
| H-35 force-close liq reward to PartyA | PASS | PASS | liquidatePartyBFromAvailable pays quote.partyA not msg.sender |
| H-01 force-close 10-open-position gas sample | PASS | FAIL | Sim full migration: forceClose 10 positions ~65.59M gas. COTI testnet 10-position force-close failed, receipt `gasUsed=116,282,373`; cap must be materially below 10 or flow needs batching. |
| H-01 force-close 8-open-position gas sample | PASS | PASS | Testnet force-close ~114.4M gas (under 120M block); openPosition@8 ~98M. Production cap `maxPartyAOpenPositions=8`. |
| H-11 SettleUpnl strips updatedPrices | PASS | PASS | Event ABI drop; calldata residual intentional |
| M-14 ObserverBalanceChange only allocate/dealloc | PASS | — | sim PASS; dual pending — wontfix/polling model |
| M-44 PartyB pending observer stale after liq cleanup | PASS | — | sim PASS after storePartyBPendingLockedBalance fix |
| M-13 flip+migrateObserverForPartyA | PASS | PASS | admin batched observer catch-up after address flip |
| M-02 stale price reuse / liquidationId bind | PASS | PASS | fixture setMuonConfig(3600); live timestamp reuse after fix |
| H-05 liq detail UPNL already encrypted | PASS | PASS | invalid/wontfix; utInt256 offBoardToUser |
| M-03 dispute accumulator CVA cap | PASS | PASS | positive-leg payable=alloc+settlementCva |
