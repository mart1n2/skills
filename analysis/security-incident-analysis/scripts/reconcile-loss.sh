#!/usr/bin/env bash
# reconcile-loss.sh — quantify one ERC-20 loss with logs and balance snapshots.
# Usage: bash reconcile-loss.sh <token> <victim> <baseline> <post> <from> <to> [recipient] [rpc]
set -u

TOKEN="${1:?token}"; VICTIM="${2:?victim}"; BASELINE="${3:?baseline block}"; POST="${4:?post block}"
FROMB="${5:?from block}"; TOB="${6:?to block}"; RECIP="${7:--}"
RPC="${8:-${RPC_URL:-${ETH_RPC_URL:-}}}"
TRANSFER="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
CHUNK="${CHUNK:-9000}"

fail() { echo "reconcile-loss: $*" >&2; exit 1; }
is_uint() { case "$1" in ""|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
is_address() { [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; }
pad() { printf '0x%064s' "$(printf '%s' "${1#0x}" | tr 'A-F' 'a-f')" | tr ' ' '0'; }
tohex() {
  local value
  value="$(cast to-hex "$1" 2>/dev/null)" || return 1
  case "$value" in 0x[0-9a-fA-F]*) printf '%s\n' "$value" ;; *) return 1 ;; esac
}
decimal_balance() {
  local raw value
  raw="$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$VICTIM" \
    --block "$1" --rpc-url "$RPC" 2>/dev/null)" || return 1
  value="$(printf '%s\n' "$raw" | awk '{print $1}')"
  is_uint "$value" || return 1
  printf '%s\n' "$value"
}
sum_hex() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys
total = 0
for line in sys.stdin:
    value = line.strip()
    if value:
        total += int(value, 16)
print(total)'
  else
    local total value decimal
    total=0
    while IFS= read -r value; do
      [ -n "$value" ] || continue
      decimal="$(printf 'ibase=16; %s\n' "$(printf '%s' "${value#0x}" | tr 'a-f' 'A-F')" | bc)" \
        || return 1
      total="$(printf '%s + %s\n' "$total" "$decimal" | bc)" || return 1
    done
    printf '%s\n' "$total"
  fi
}
subtract() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; print(int(sys.argv[1]) - int(sys.argv[2]))' "$1" "$2"
  else
    printf '%s - %s\n' "$1" "$2" | bc
  fi
}

[ -n "$RPC" ] || fail "no RPC"
command -v cast >/dev/null 2>&1 || fail "cast required"
command -v jq >/dev/null 2>&1 || fail "jq required"
if ! command -v python3 >/dev/null 2>&1 && ! command -v bc >/dev/null 2>&1; then
  fail "python3 or bc required for big-integer arithmetic"
fi
is_address "$TOKEN" || fail "invalid token address"
is_address "$VICTIM" || fail "invalid victim address"
[ "$RECIP" = "-" ] || is_address "$RECIP" || fail "invalid recipient address"
is_uint "$BASELINE" && is_uint "$POST" && is_uint "$FROMB" && is_uint "$TOB" && is_uint "$CHUNK" \
  || fail "blocks and CHUNK must be unsigned integers"
[ "$BASELINE" -le "$POST" ] || fail "baseline block must not exceed post block"
[ "$FROMB" -le "$TOB" ] || fail "from block must not exceed to block"
[ "$CHUNK" -gt 0 ] || fail "CHUNK must be greater than zero"

FROM_TOPIC="$(pad "$VICTIM")"
TO_TOPIC="null"
RECIP_LABEL=""
if [ "$RECIP" != "-" ]; then
  TO_TOPIC="\"$(pad "$RECIP")\""
  RECIP_LABEL=", to=$RECIP"
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/incident-loss.XXXXXX")"
RESP_FILE="$(mktemp "${TMPDIR:-/tmp}/incident-logs.XXXXXX")"
cleanup() { rm -f "$TMP" "$RESP_FILE"; }
trap cleanup EXIT HUP INT TERM
: > "$TMP"

echo "== Method A: eth_getLogs Transfer(from=$VICTIM$RECIP_LABEL) over [$FROMB,$TOB] =="
b=$FROMB
while [ "$b" -le "$TOB" ]; do
  e=$((b + CHUNK - 1)); [ "$e" -gt "$TOB" ] && e=$TOB
  FROM_HEX="$(tohex "$b")" || fail "could not encode from block $b"
  TO_HEX="$(tohex "$e")" || fail "could not encode to block $e"
  FILTER='{"address":"'"$TOKEN"'","fromBlock":"'"$FROM_HEX"'","toBlock":"'"$TO_HEX"'","topics":["'"$TRANSFER"'","'"$FROM_TOPIC"'",'"$TO_TOPIC"']}'
  cast rpc eth_getLogs "$FILTER" --rpc-url "$RPC" > "$RESP_FILE" 2>/dev/null \
    || fail "eth_getLogs failed for blocks $b..$e"
  jq -e 'type == "array"
    and all(.[];
      (.data | type == "string")
      and (.data | test("^0x[0-9a-fA-F]{64}$")))' \
    "$RESP_FILE" >/dev/null 2>&1 || fail "invalid eth_getLogs response for blocks $b..$e"
  jq -r '.[].data' "$RESP_FILE" >> "$TMP"
  N="$(jq -r 'length' "$RESP_FILE")"
  echo "  blocks $b..$e : $N transfer logs"
  b=$((e + 1))
done
A_SUM="$(sum_hex < "$TMP")" || fail "could not sum transfer amounts"
is_uint "$A_SUM" || fail "invalid Method A sum"
A_CNT="$(wc -l < "$TMP" | tr -d ' ')"
echo "  Method A total (base units): $A_SUM   (from $A_CNT logs)"

echo "== Method B: balanceOf delta [$BASELINE -> $POST] =="
BB="$(decimal_balance "$BASELINE")" || fail "baseline balance query failed at block $BASELINE"
PB="$(decimal_balance "$POST")" || fail "post balance query failed at block $POST"
DELTA="$(subtract "$BB" "$PB")" || fail "could not compute balance delta"
RESID="$(subtract "$DELTA" "$A_SUM")" || fail "could not compute reconciliation residual"
echo "  baseline balance: $BB"
echo "  post balance:     $PB"
echo "  Method B delta (base units): $DELTA"
echo
echo "== Reconciliation =="
echo "  A (log sum out of victim): $A_SUM"
echo "  B (balance delta):         $DELTA"
echo "  residual (B - A):          $RESID"
echo
echo "NOTE: report NET attacker extraction; exclude round-tripped flash-loan principal."
echo "NOTE: baseline must be the block before the first attacker-touching transaction."
