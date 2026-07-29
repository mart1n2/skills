#!/usr/bin/env bash
# find-drain-block.sh — binary-search a monotone token-balance drop.
# Usage: bash find-drain-block.sh <token> <victim> <lo_block> <hi_block> <threshold> [rpc]
# The low endpoint must be above threshold; the high endpoint must be at or below it.
set -u

TOKEN="${1:?token address}"; VICTIM="${2:?victim address}"
LO="${3:?lo block}"; HI="${4:?hi block}"; THRESH="${5:?threshold in base units}"
RPC="${6:-${RPC_URL:-${ETH_RPC_URL:-}}}"

fail() { echo "find-drain-block: $*" >&2; exit 1; }
is_uint() { case "$1" in ""|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
strip0() {
  local v="$1"
  while [ "${v#0}" != "$v" ] && [ ${#v} -gt 1 ]; do v="${v#0}"; done
  echo "$v"
}
gt() {
  local a b
  a="$(strip0 "${1:-0}")"; b="$(strip0 "${2:-0}")"
  if [ ${#a} -ne ${#b} ]; then [ ${#a} -gt ${#b} ]; return; fi
  [ "$a" \> "$b" ]
}
bal_at() {
  local raw value
  raw="$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$VICTIM" \
    --block "$1" --rpc-url "$RPC" 2>/dev/null)" || return 1
  value="$(printf '%s\n' "$raw" | awk '{print $1}')"
  is_uint "$value" || return 1
  printf '%s\n' "$value"
}

[ -n "$RPC" ] || fail "no RPC"
command -v cast >/dev/null 2>&1 || fail "cast required"
is_uint "$LO" && is_uint "$HI" && is_uint "$THRESH" || fail "blocks and threshold must be unsigned integers"
[ "$LO" -lt "$HI" ] || fail "lo block must be less than hi block"

echo "bisecting balance drop of $TOKEN held by $VICTIM in [$LO, $HI] (threshold $THRESH)"
LB="$(bal_at "$LO")" || fail "balance query failed at low block $LO"
HB="$(bal_at "$HI")" || fail "balance query failed at high block $HI"
echo "  lo=$LO bal=$LB ; hi=$HI bal=$HB"
gt "$LB" "$THRESH" || fail "low-block balance must be above threshold; widen the range earlier"
if gt "$HB" "$THRESH"; then
  fail "high-block balance is still above threshold; widen the range later"
fi

while [ $((HI - LO)) -gt 1 ]; do
  MID=$(((LO + HI) / 2))
  B="$(bal_at "$MID")" || fail "balance query failed at block $MID"
  if gt "$B" "$THRESH"; then LO=$MID; LB=$B; else HI=$MID; HB=$B; fi
  echo "  block $MID bal=$B -> lo=$LO hi=$HI"
done

echo "DROP between block $LO (balance $LB) and $HI (balance $HB)."
echo "Set BASELINE=$LO ; the drain tx(s) are in block $HI (or the range if multi-tx)."
