#!/usr/bin/env bash
# preflight.sh — resolve a reachable archive RPC and verify tooling for incident analysis.
# Usage: bash preflight.sh <chain> [workspace]
# Writes <workspace>/tool-resolution.env (machine) and tool-resolution.md (human).
# Bash 3.2 compatible (macOS/Linux). Run with bash, not the interactive shell.
set -u

CHAIN="${1:-ethereum}"
WORKSPACE="${2:-incident-workspace/_preflight}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHAINS_JSON="$SKILL_DIR/config/chains.json"
mkdir -p "$WORKSPACE"

# Load API keys / RPC overrides from .env chain.
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/load-env.sh" ] && . "$SCRIPT_DIR/load-env.sh"

have() { command -v "$1" >/dev/null 2>&1; }
add_note() { NOTES="${NOTES:+$NOTES; }$1"; }
emit_env() {
  printf '%s=' "$1"
  printf '%q\n' "$2"
}
rpc_chain_id() {
  cast chain-id --rpc-url "$1" --rpc-timeout "$RPC_PROBE_TIMEOUT" 2>/dev/null
}
rpc_is_archival() {
  cast balance 0x0000000000000000000000000000000000000000 \
    --block "$ARCHIVE_PROBE_BLOCK" --rpc-url "$1" \
    --rpc-timeout "$RPC_PROBE_TIMEOUT" >/dev/null 2>&1
}

HAS_CAST=false;  have cast  && HAS_CAST=true
HAS_FORGE=false; have forge && HAS_FORGE=true
HAS_JQ=false;    have jq    && HAS_JQ=true
HAS_CURL=false;  have curl  && HAS_CURL=true

MODE="full"; NOTES=""
CHAIN_ID=""; RPC_ENV=""; RPC_DEFAULT=""; EXPLORER_API=""; EXPLORER_KEY_ENV=""; EXPLORER_URL=""
RPC_URL_INPUT="${RPC_URL:-}"; RPC_URL=""; RPC_SOURCE=""; CHAIN_ID_LIVE=""; ARCHIVE_OK="unknown"
RPC_PROBE_TIMEOUT_INPUT="${RPC_PROBE_TIMEOUT:-}"
ARCHIVE_PROBE_BLOCK_INPUT="${ARCHIVE_PROBE_BLOCK:-}"
CHAINLIST_URL_INPUT="${CHAINLIST_URL:-}"
CHAINLIST_MAX_CANDIDATES_INPUT="${CHAINLIST_MAX_CANDIDATES:-}"
RPC_PROBE_TIMEOUT="${RPC_PROBE_TIMEOUT_INPUT:-8}"
ARCHIVE_PROBE_BLOCK="${ARCHIVE_PROBE_BLOCK_INPUT:-1000000}"
CHAINLIST_URL="${CHAINLIST_URL_INPUT:-https://chainid.network/chains.json}"
CHAINLIST_MAX_CANDIDATES="${CHAINLIST_MAX_CANDIDATES_INPUT:-8}"
CONNECT_TIMEOUT=10; REQUEST_TIMEOUT=30

if [ "$HAS_CAST" != true ]; then
  MODE="blocked"; add_note "cast (foundry) not found — required for all on-chain forensics"
fi
if [ "$HAS_JQ" != true ]; then
  MODE="blocked"; add_note "jq not found — required to resolve chains and parse evidence"
fi

# --- Resolve the configured EVM chain (aliases supported) ---------------------
KEY=""
if [ "$HAS_JQ" = true ] && [ -f "$CHAINS_JSON" ]; then
  KEY="$(jq -r --arg c "$CHAIN" '
    to_entries
    | map(select((.key | startswith("_") | not)
                 and (.key==$c or ((.value.aliases // []) | index($c)))))
    | (.[0].key // "")' "$CHAINS_JSON" 2>/dev/null)"
  if [ -n "$KEY" ] && [ "$KEY" != "null" ]; then
    CHAIN_ID="$(jq -r --arg k "$KEY" '.[$k].chain_id // ""' "$CHAINS_JSON")"
    RPC_ENV="$(jq -r --arg k "$KEY" '.[$k].rpc_url_env // ""' "$CHAINS_JSON")"
    RPC_DEFAULT="$(jq -r --arg k "$KEY" '.[$k].rpc_url_default // ""' "$CHAINS_JSON")"
    EXPLORER_API="$(jq -r --arg k "$KEY" '.[$k].explorer_api // ""' "$CHAINS_JSON")"
    EXPLORER_KEY_ENV="$(jq -r --arg k "$KEY" '.[$k].explorer_key_env // ""' "$CHAINS_JSON")"
    EXPLORER_URL="$(jq -r --arg k "$KEY" '.[$k].explorer_url // ""' "$CHAINS_JSON")"
    CONNECT_TIMEOUT="$(jq -r '._rpc_defaults.connect_timeout // 10' "$CHAINS_JSON")"
    REQUEST_TIMEOUT="$(jq -r '._rpc_defaults.request_timeout // 30' "$CHAINS_JSON")"
    [ -n "$RPC_PROBE_TIMEOUT_INPUT" ] || RPC_PROBE_TIMEOUT="$(jq -r '._rpc_defaults.probe_timeout // 8' "$CHAINS_JSON")"
    [ -n "$ARCHIVE_PROBE_BLOCK_INPUT" ] || ARCHIVE_PROBE_BLOCK="$(jq -r '._rpc_defaults.archive_probe_block // 1000000' "$CHAINS_JSON")"
    [ -n "$CHAINLIST_URL_INPUT" ] || CHAINLIST_URL="$(jq -r '._rpc_defaults.chainlist_url // "https://chainid.network/chains.json"' "$CHAINS_JSON")"
    [ -n "$CHAINLIST_MAX_CANDIDATES_INPUT" ] || CHAINLIST_MAX_CANDIDATES="$(jq -r '._rpc_defaults.max_chainlist_candidates // 8' "$CHAINS_JSON")"
    CHAIN="$KEY"
  fi
fi
if [ -z "$KEY" ]; then
  MODE="blocked"; add_note "unknown chain '$CHAIN' in config/chains.json"
elif [ -z "$CHAIN_ID" ]; then
  MODE="blocked"; add_note "chain '$CHAIN' is not an EVM chain supported by this skill"
fi

RPC_ENV_VALUE=""
if [ -n "$RPC_ENV" ]; then
  eval "RPC_ENV_VALUE=\"\${$RPC_ENV:-}\""
fi

# RPC precedence:
#   1. explicit RPC_URL
#   2. configured per-chain environment variable
#   3. first reachable + archival Chainlist endpoint
#   4. configured official/public endpoint
if [ -n "$RPC_URL_INPUT" ]; then
  RPC_URL="$RPC_URL_INPUT"
  RPC_SOURCE="environment:RPC_URL"
elif [ -n "$RPC_ENV_VALUE" ]; then
  RPC_URL="$RPC_ENV_VALUE"
  RPC_SOURCE="environment:$RPC_ENV"
elif [ "$HAS_CAST" = true ] && [ "$HAS_JQ" = true ] && [ -n "$CHAIN_ID" ]; then
  CANDIDATES="$(mktemp "${TMPDIR:-/tmp}/incident-rpc-candidates.XXXXXX")"
  CANDIDATES_DEDUP="$(mktemp "${TMPDIR:-/tmp}/incident-rpc-dedup.XXXXXX")"
  CHAINLIST_JSON="$(mktemp "${TMPDIR:-/tmp}/incident-chainlist.XXXXXX")"
  : > "$CANDIDATES"

  if [ "$HAS_CURL" = true ] && curl -fsSL \
      --connect-timeout "$CONNECT_TIMEOUT" --max-time "$REQUEST_TIMEOUT" \
      "$CHAINLIST_URL" -o "$CHAINLIST_JSON" 2>/dev/null \
      && jq -e 'type == "array"' "$CHAINLIST_JSON" >/dev/null 2>&1; then
    jq -r --argjson id "$CHAIN_ID" --argjson max "$CHAINLIST_MAX_CANDIDATES" '
      [.[] | select(.chainId == $id) | .rpc[]?
       | select(type == "string")
       | select(test("^https?://"))
       | select(contains("${") | not)
       | select(contains("{") | not)
       | select(test("[[:space:]]") | not)][0:$max][]' \
      "$CHAINLIST_JSON" 2>/dev/null \
      | while IFS= read -r url; do printf 'chainlist\t%s\n' "$url"; done \
      >> "$CANDIDATES"
  else
    add_note "Chainlist registry unavailable — trying configured official/public RPC"
  fi
  [ -n "$RPC_DEFAULT" ] && printf 'config-default\t%s\n' "$RPC_DEFAULT" >> "$CANDIDATES"
  awk -F '\t' '!seen[$2]++' "$CANDIDATES" > "$CANDIDATES_DEDUP"

  FIRST_REACHABLE_URL=""; FIRST_REACHABLE_SOURCE=""
  TAB="$(printf '\t')"
  while IFS="$TAB" read -r source url; do
    [ -n "$url" ] || continue
    LIVE_ID="$(rpc_chain_id "$url")" || continue
    [ "$LIVE_ID" = "$CHAIN_ID" ] || continue
    if [ -z "$FIRST_REACHABLE_URL" ]; then
      FIRST_REACHABLE_URL="$url"
      FIRST_REACHABLE_SOURCE="$source"
    fi
    if rpc_is_archival "$url"; then
      RPC_URL="$url"
      RPC_SOURCE="$source"
      CHAIN_ID_LIVE="$LIVE_ID"
      ARCHIVE_OK="yes"
      break
    fi
  done < "$CANDIDATES_DEDUP"

  if [ -z "$RPC_URL" ] && [ -n "$FIRST_REACHABLE_URL" ]; then
    RPC_URL="$FIRST_REACHABLE_URL"
    RPC_SOURCE="$FIRST_REACHABLE_SOURCE"
    CHAIN_ID_LIVE="$CHAIN_ID"
    ARCHIVE_OK="no"
  fi
  rm -f "$CANDIDATES" "$CANDIDATES_DEDUP" "$CHAINLIST_JSON"
fi

EXPLORER_KEY=""
[ -n "$EXPLORER_KEY_ENV" ] && eval "EXPLORER_KEY=\"\${$EXPLORER_KEY_ENV:-}\""
[ -z "$EXPLORER_KEY" ] && EXPLORER_KEY="${ETHERSCAN_API_KEY:-}"

# --- Verify selected endpoint and require archive state -----------------------
if [ -z "$RPC_URL" ]; then
  MODE="blocked"
  add_note "no reachable RPC resolved for '$CHAIN' (set ${RPC_ENV:-RPC_URL} to a dedicated archive endpoint)"
elif [ "$HAS_CAST" = true ]; then
  if [ -z "$CHAIN_ID_LIVE" ]; then
    CHAIN_ID_LIVE="$(rpc_chain_id "$RPC_URL")"
  fi
  if [ -z "$CHAIN_ID_LIVE" ]; then
    MODE="blocked"; add_note "RPC unreachable: $RPC_URL"
  elif [ "$CHAIN_ID_LIVE" != "$CHAIN_ID" ]; then
    MODE="blocked"; add_note "RPC chain-id $CHAIN_ID_LIVE != expected $CHAIN_ID for '$CHAIN'"
  else
    if [ "$ARCHIVE_OK" = "unknown" ]; then
      if rpc_is_archival "$RPC_URL"; then ARCHIVE_OK="yes"; else ARCHIVE_OK="no"; fi
    fi
    if [ "$ARCHIVE_OK" != "yes" ]; then
      MODE="blocked"
      add_note "RPC is reachable but not archival at block $ARCHIVE_PROBE_BLOCK — configure a dedicated archive endpoint"
    fi
  fi
fi

[ "$HAS_FORGE" != true ] && { [ "$MODE" = "full" ] && MODE="degraded"; add_note "forge not found — Phase 6 fork replay unavailable"; }
[ "$HAS_CURL" != true ]  && { [ "$MODE" = "full" ] && MODE="degraded"; add_note "curl not found — Chainlist/source fetch unavailable"; }
[ -z "$EXPLORER_KEY" ]   && add_note "no explorer API key — verified-source lookups are limited"

# --- Emit source-safe machine output + human summary --------------------------
ENV_OUT="$WORKSPACE/tool-resolution.env"
{
  emit_env AUDIT_MODE "$MODE"
  emit_env CHAIN "$CHAIN"
  emit_env CHAIN_ID "${CHAIN_ID:-$CHAIN_ID_LIVE}"
  emit_env RPC_URL "$RPC_URL"
  emit_env RPC_SOURCE "$RPC_SOURCE"
  emit_env ARCHIVE_OK "$ARCHIVE_OK"
  emit_env ARCHIVE_PROBE_BLOCK "$ARCHIVE_PROBE_BLOCK"
  emit_env EXPLORER_API "$EXPLORER_API"
  emit_env EXPLORER_URL "$EXPLORER_URL"
  emit_env HAS_CAST "$HAS_CAST"
  emit_env HAS_FORGE "$HAS_FORGE"
  emit_env HAS_JQ "$HAS_JQ"
  emit_env HAS_CURL "$HAS_CURL"
  emit_env SKILL_DIR "$SKILL_DIR"
} > "$ENV_OUT"

{
  echo "# Preflight — $CHAIN"
  echo
  echo "- Mode: **$MODE**"
  echo "- Chain id (config/live): ${CHAIN_ID:-?} / ${CHAIN_ID_LIVE:-?}"
  echo "- RPC source: **${RPC_SOURCE:-none}**"
  echo "- RPC: $RPC_URL"
  echo "- Archival at block $ARCHIVE_PROBE_BLOCK: **$ARCHIVE_OK**"
  echo "- Tools: cast=$HAS_CAST forge=$HAS_FORGE jq=$HAS_JQ curl=$HAS_CURL"
  [ -n "$NOTES" ] && { echo; echo "Notes: $NOTES"; }
} > "$WORKSPACE/tool-resolution.md"

echo "preflight: mode=$MODE chain=$CHAIN source=${RPC_SOURCE:-none} archival=$ARCHIVE_OK rpc=$RPC_URL"
[ "$MODE" = "blocked" ] && { echo "BLOCKED — $NOTES" >&2; exit 1; }
exit 0
