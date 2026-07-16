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
| H-15 remainingLf > alloc (+UPNL) liquidate | PASS | PASS | Cap `remainingLf` via `MpcCore.min(..., partyBAllocated)`. Agree on both. |
| H-16 deferred type uses signed alloc snapshot | PASS | PASS | `deferredSetSymbolsPrice` + reimbursement use `liquidationAllocatedBalance`. |
| H-26 force-close LF unlock before PartyB liq | PASS | PASS | Unlock closed-quote cva+lf on PartyB locks before liquidatePartyBFromAvailable |
| H-08 allocate/internalTransfer free-balance before limit | PASS | PASS | Public balance require before encrypted allocated-limit decrypt |
| H-04 force-close Muon before price decrypt | PASS | PASS | verifyHighLowPrice before requestedClosePrice onboard; testnet has force-close cooldown |
| H-32 emergency close insolvency vs liquidation | PASS | PASS | design-choice: solvency gate intentional; liq still works in PartyB emergency |
| H-33 fee distributor encrypted claim | PASS | PASS | claimAllFeeCollectorBalance before getClaimable/withdraw |
| H-34 force close after deadline | PASS | PASS | require block.timestamp <= quote.deadline |
| H-35 force-close liq reward to PartyA | PASS | PASS | liquidatePartyBFromAvailable pays quote.partyA not msg.sender |
