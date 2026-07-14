# Wayfinder: Review2 Audit Triage

Local markdown issue tracker for [`report.md`](../report.md).

## Usage

```bash
# Open the map (start here)
review/review2/wayfinder/map.md

# Work one ticket per session
/wayfinder review/review2/wayfinder/map.md
# or name a ticket:
/wayfinder review/review2/wayfinder/tickets/logic-P0-C-01.md
```

## Structure

| Path | Role |
| --- | --- |
| [`map.md`](map.md) | `wayfinder:map` — destination, frontier, decisions index |
| [`tickets/*.md`](tickets/) | Child issues — one finding or design decision each |
| [`index.html`](index.html) | Progress dashboard (open in browser) |
| [`build-progress.mjs`](build-progress.mjs) | Regenerate dashboard data from tickets |

### Progress dashboard

```bash
node review/wayfinder/build-progress.mjs   # after ticket updates
open review/wayfinder/index.html           # macOS; or serve the folder
```

Shows closed / in-progress / open counts, group and priority breakdown, frontier, decisions, and a filterable ticket table with checklist progress.

## Ticket workflow

1. Pick from **Frontier** in `map.md` (or claim a named ticket).
2. Set ticket `status: in-progress` in frontmatter.
3. Follow **diagnosing-bugs** — build red testnet test before theorizing.
4. Fill **Answer** with verdict + evidence + fix disposition.
5. Close ticket (`status: closed`); append one line to map **Decisions so far**.

## Labels

- `group:logic-security` — exploit / correctness / DoS
- `group:privacy-leak` — calldata, events, views, oracles
- `group:design-product` — intentional tradeoff; decide before fixing
- `wayfinder:research` — AFK validation ticket
- `wayfinder:grilling` — HITL product/architecture decision
