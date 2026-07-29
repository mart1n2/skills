#!/usr/bin/env bash
# intake.sh — atomically freeze the facts of an incident. Bash 3.2 compatible.
# Usage: bash intake.sh <tx_hash|-> <victim_addr|-> <chain> <workspace>
# Pass "-" for an unknown tx or victim. Run preflight.sh first.
set -u

TX="${1:--}"; VICTIM="${2:--}"; CHAIN="${3:-ethereum}"; WORKSPACE="${4:-incident-workspace/_intake}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$WORKSPACE/evidence"
RUN_ENV="$WORKSPACE/run.env"
mkdir -p "$EVIDENCE_DIR"

fail() { echo "intake: $*" >&2; exit 1; }
emit_env() {
  printf '%s=' "$1"
  printf '%q\n' "$2"
}
is_uint() {
  case "$1" in ""|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/load-env.sh" ] && . "$SCRIPT_DIR/load-env.sh"
# shellcheck disable=SC1090
[ -f "$WORKSPACE/tool-resolution.env" ] && . "$WORKSPACE/tool-resolution.env"
RPC_URL="${RPC_URL:-${ETH_RPC_URL:-}}"

command -v cast >/dev/null 2>&1 || fail "cast (foundry) required"
command -v jq >/dev/null 2>&1 || fail "jq required"
[ -n "$RPC_URL" ] || fail "no RPC_URL — run preflight.sh or export RPC_URL"
[ ! -e "$RUN_ENV" ] || fail "$RUN_ENV already exists; use a new workspace to preserve the frozen intake"

HEAD="$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null)" || fail "could not read chain head"
is_uint "$HEAD" || fail "invalid chain head from RPC: ${HEAD:-<empty>}"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

TX_TMP=""; RECEIPT_TMP=""; BLOCK_TMP=""; RUN_TMP=""
cleanup() { rm -f "$TX_TMP" "$RECEIPT_TMP" "$BLOCK_TMP" "$RUN_TMP"; }
trap cleanup EXIT HUP INT TERM
RUN_TMP="$(mktemp "$WORKSPACE/.run.env.XXXXXX")"

BLOCK=""; PRE=""; POST=""; TS=""; STATUS=""; TO=""; FROM=""; BLOCK_HASH=""; HR=""
if [ "$TX" != "-" ]; then
  TX_FINAL="$EVIDENCE_DIR/tx.json"
  RECEIPT_FINAL="$EVIDENCE_DIR/receipt.json"
  BLOCK_FINAL="$EVIDENCE_DIR/block.json"
  [ ! -e "$TX_FINAL" ] && [ ! -e "$RECEIPT_FINAL" ] && [ ! -e "$BLOCK_FINAL" ] \
    || fail "evidence already exists; refusing to overwrite immutable artifacts"

  TX_TMP="$(mktemp "$EVIDENCE_DIR/.tx.json.XXXXXX")"
  RECEIPT_TMP="$(mktemp "$EVIDENCE_DIR/.receipt.json.XXXXXX")"
  BLOCK_TMP="$(mktemp "$EVIDENCE_DIR/.block.json.XXXXXX")"

  cast tx "$TX" --rpc-url "$RPC_URL" --json > "$TX_TMP" 2>/dev/null \
    || fail "cast tx failed for $TX"
  cast receipt "$TX" --rpc-url "$RPC_URL" --json > "$RECEIPT_TMP" 2>/dev/null \
    || fail "cast receipt failed for $TX"
  jq -e 'type == "object" and (.hash | type == "string") and (.blockNumber != null)' \
    "$TX_TMP" >/dev/null 2>&1 || fail "transaction response is incomplete or invalid JSON"
  jq -e 'type == "object" and (.transactionHash | type == "string") and (.status != null)' \
    "$RECEIPT_TMP" >/dev/null 2>&1 || fail "receipt response is incomplete or invalid JSON"

  TX_NORM="$(printf '%s' "$TX" | tr 'A-F' 'a-f')"
  FETCHED_TX="$(jq -r '.hash' "$TX_TMP" | tr 'A-F' 'a-f')"
  RECEIPT_TX="$(jq -r '.transactionHash' "$RECEIPT_TMP" | tr 'A-F' 'a-f')"
  [ "$FETCHED_TX" = "$TX_NORM" ] || fail "transaction hash mismatch in tx response"
  [ "$RECEIPT_TX" = "$TX_NORM" ] || fail "transaction hash mismatch in receipt response"

  BLOCK_RAW="$(jq -r '.blockNumber' "$TX_TMP")"
  BLOCK="$(cast to-dec "$BLOCK_RAW" 2>/dev/null)" || fail "could not decode transaction block number"
  is_uint "$BLOCK" || fail "invalid transaction block number: ${BLOCK:-<empty>}"
  [ "$BLOCK" -gt 0 ] || fail "transaction is not in a mined block"
  PRE=$((BLOCK - 1)); POST=$BLOCK

  cast block "$BLOCK" --rpc-url "$RPC_URL" --json > "$BLOCK_TMP" 2>/dev/null \
    || fail "cast block failed for block $BLOCK"
  jq -e 'type == "object" and (.hash | type == "string") and (.timestamp != null)' \
    "$BLOCK_TMP" >/dev/null 2>&1 || fail "block response is incomplete or invalid JSON"

  BLOCK_HASH="$(jq -r '.hash' "$BLOCK_TMP")"
  TS_RAW="$(jq -r '.timestamp' "$BLOCK_TMP")"
  TS="$(cast to-dec "$TS_RAW" 2>/dev/null)" || fail "could not decode block timestamp"
  is_uint "$TS" || fail "invalid block timestamp: ${TS:-<empty>}"
  STATUS="$(jq -r '.status' "$RECEIPT_TMP")"
  TO="$(jq -r '.to // ""' "$TX_TMP")"
  FROM="$(jq -r '.from // ""' "$TX_TMP")"
  [ -n "$FROM" ] || fail "transaction response has no sender"
  HR="$(date -u -r "$TS" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$TS" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
    || fail "could not format block timestamp"

  mv "$TX_TMP" "$TX_FINAL"; TX_TMP=""
  mv "$RECEIPT_TMP" "$RECEIPT_FINAL"; RECEIPT_TMP=""
  mv "$BLOCK_TMP" "$BLOCK_FINAL"; BLOCK_TMP=""
fi

{
  echo "# frozen at intake — do not edit"
  emit_env CHAIN "$CHAIN"
  emit_env RPC_URL "$RPC_URL"
  emit_env RPC_SOURCE "${RPC_SOURCE:-unknown}"
  emit_env ARCHIVE_OK "${ARCHIVE_OK:-unknown}"
  emit_env AUDIT_MODE "${AUDIT_MODE:-unknown}"
  emit_env HEAD_AT_INTAKE "$HEAD"
  emit_env INTAKE_UTC "$NOW_UTC"
  emit_env TX "$TX"
  emit_env VICTIM "$VICTIM"
  if [ "$TX" != "-" ]; then
    emit_env BLOCK "$BLOCK"
    emit_env PRE "$PRE"
    emit_env POST "$POST"
    emit_env BLOCK_HASH "$BLOCK_HASH"
    emit_env EXPLOIT_TS "$TS"
    emit_env EXPLOIT_UTC "$HR"
    emit_env TX_STATUS "$STATUS"
    emit_env TX_FROM "$FROM"
    emit_env TX_TO "$TO"
    TO_NORM="$(printf '%s' "$TO" | tr 'A-F' 'a-f')"
    VICTIM_NORM="$(printf '%s' "$VICTIM" | tr 'A-F' 'a-f')"
    if [ "$VICTIM" != "-" ] && [ "$TO_NORM" != "$VICTIM_NORM" ]; then
      emit_env NOTE_ROUTING "tx.to ($TO) != victim ($VICTIM) — attack routed through another contract"
    fi
  fi
} > "$RUN_TMP"
mv "$RUN_TMP" "$RUN_ENV"; RUN_TMP=""

echo "intake: wrote $RUN_ENV"
cat "$RUN_ENV"
