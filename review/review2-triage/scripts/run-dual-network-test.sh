#!/usr/bin/env bash
# Run same Hardhat grep on localSimCoti then coti-testnet; upsert one row in sim-vs-testnet.md.
# Usage:
#   ./review/review2-triage/scripts/run-dual-network-test.sh 'third-party caller' test/audit/H12.test.ts 'H-12 third-party settleAndForceClose'
# Optional 4th arg = details cell (default empty).
# Requires: Muon off (`python3 utils/update_sig_checks.py 1`), sim node up.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

GREP_FILTER="${1:?grep filter required}"
TEST_FILE="${2:?test file required}"
TEST_NAME="${3:-$GREP_FILTER · $TEST_FILE}"
DETAILS="${4:-}"
REPORT="$ROOT/review/review2-triage/test-runs/sim-vs-testnet.md"

ensure_muon_off() {
  if ! grep -q '^// 		bool verified = LibMuonV04ClientBase.muonVerify' contracts/libraries/muon/LibMuon.sol; then
    echo "Muon signature checks appear ENABLED. Run: python3 utils/update_sig_checks.py 1" >&2
    exit 1
  fi
}

run_one() {
  local network="$1"
  set +e
  TEST_MODE=static npx hardhat test "$TEST_FILE" --grep "$GREP_FILTER" --network "$network" >&2
  local code=$?
  set -e
  if [[ $code -eq 0 ]]; then echo PASS; else echo FAIL; fi
}

ensure_muon_off

if ! curl -sf -X POST "${SIM_COTI_RPC_URL:-http://127.0.0.1:8546}" \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' >/dev/null; then
  echo "sim-coti-node not reachable at ${SIM_COTI_RPC_URL:-http://127.0.0.1:8546}" >&2
  echo "Start with: (cd /Users/Vlad1/coti/sim-coti-node && npm start)" >&2
  exit 1
fi

echo "=== dual run grep=$GREP_FILTER file=$TEST_FILE name=$TEST_NAME ==="

echo "--- localSimCoti ---" >&2
ss="$(run_one localSimCoti)"
echo "--- coti-testnet ---" >&2
ts="$(run_one coti-testnet)"

if [[ ! -f "$REPORT" ]]; then
  cat >"$REPORT" <<'EOF'
# Sim vs testnet

Purpose: see which audit tests agree on sim (`localSimCoti`) vs COTI testnet so we can prefer sim for speed.

| Test | Sim | Testnet | Details |
| --- | --- | --- | --- |
EOF
fi

esc() { printf '%s' "$1" | sed 's/|/\\|/g'; }
NAME_ESC="$(esc "$TEST_NAME")"
DET_ESC="$(esc "$DETAILS")"
ROW="| $NAME_ESC | $ss | $ts | $DET_ESC |"

tmp="$(mktemp)"
awk -v name="$NAME_ESC" -v row="$ROW" '
  BEGIN { done=0 }
  /^\| / && $0 !~ /^\| ---/ && $0 !~ /^\| Test \|/ {
    n = $0
    sub(/^\| /, "", n)
    split(n, cells, " \| ")
    if (cells[1] == name) { print row; done=1; next }
  }
  { print }
  END { if (!done) print row }
' "$REPORT" >"$tmp"
mv "$tmp" "$REPORT"

echo
echo "Recorded in $REPORT"
echo "  $TEST_NAME → sim=$ss testnet=$ts"

if [[ "$ss" != "PASS" || "$ts" != "PASS" ]]; then
  exit 1
fi
