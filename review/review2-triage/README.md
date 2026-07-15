# Review2 audit triage

Local markdown tracker for [`report.md`](../report.md).

## Usage

```bash
# Map (start here)
review/review2-triage/map.md

# After ticket updates — regenerate local dashboard
node review/review2-triage/build-progress.mjs
open review/review2-triage/index.html   # generated; gitignored
```

## Structure

| Path | Role |
| --- | --- |
| [`map.md`](map.md) | Destination, frontier, decisions |
| [`tickets/*.md`](tickets/) | One finding / design decision each |
| [`index.template.html`](index.template.html) | Dashboard shell (tracked) |
| `index.html` | Built dashboard (gitignored) |
| [`build-progress.mjs`](build-progress.mjs) | Build dashboard from tickets |
| [`test-runs/sim-vs-testnet.md`](test-runs/sim-vs-testnet.md) | Sim vs testnet agreement table |

## Sim vs testnet

Ticket evidence stays on **sim** (`localSimCoti`). Optionally dual-run to see if sim is enough to move fast:

```bash
./review/review2-triage/scripts/run-dual-network-test.sh '<grep>' <file.ts> '<short name>'
```

Updates one row in `test-runs/sim-vs-testnet.md` (Test / Sim / Testnet / Details).
