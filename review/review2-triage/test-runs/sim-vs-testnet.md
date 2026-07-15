# Sim vs testnet

Purpose: see which audit tests agree on sim (`localSimCoti`) vs COTI testnet so we can prefer sim for speed.

```bash
# sim node: cd /Users/Vlad1/coti/sim-coti-node && npm start
python3 utils/update_sig_checks.py 1
./review/review2-triage/scripts/run-dual-network-test.sh '<grep>' <test-file.ts> '<short name>'
```

| Test | Sim | Testnet | Details |
| --- | --- | --- | --- |
| H-12 third-party settleAndForceClose | PASS | PASS | Logic matches. Testnet needs `gasOptions.gasLimit` ≥120M for success path; force-close cooldowns ~minutes. |
