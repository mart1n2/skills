#!/usr/bin/env bash
set -uo pipefail
# Note: set -e is intentionally omitted because cast calls frequently fail on non-contract addresses.
# Critical filesystem operations below use explicit error checks instead.

# Usage: collect-onchain-data.sh <comma-separated-addresses> <chain> <rpc-url> [output-dir] [audit-workspace-root]
# Collects on-chain state: proxy/admin config, timelock delay, deployment status.
# Output: <output-dir>/onchain.md; retained snapshots live under
# <audit-workspace-root>/tmp/collect-onchain-data/.

ADDRESSES="${1:?Usage: collect-onchain-data.sh <addresses> <chain> <rpc-url>}"
CHAIN="${2:?Missing chain argument}"
RPC_URL="${3:?Missing RPC URL}"
OUTPUT_DIR="${4:-audit-workspace}"
WORKSPACE="${5:-${AUDIT_WORKSPACE_ROOT:-$OUTPUT_DIR}}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

OUTPUT="$OUTPUT_DIR/onchain.md"
mkdir -p "$WORKSPACE" "$OUTPUT_DIR"

# Load .env files (RPC URLs, API keys)
export SKILL_DIR WORKSPACE
source "$(dirname "$0")/load-env.sh"
source "$(dirname "$0")/retention.sh"
audit_archive_existing "$WORKSPACE" "collect-onchain-data" "$OUTPUT" || {
    echo "ERROR: refusing to replace on-chain output without retaining the prior version" >&2
    exit 1
}

# Consistent RPC timeout settings for all cast calls
CAST_TIMEOUT="${CAST_TIMEOUT:-30}"
export CAST_TIMEOUT

if ! command -v cast &>/dev/null; then
    echo "ERROR: cast (foundry) not found in PATH" >&2
    cat > "$OUTPUT" << 'EOF'
# On-Chain Data

**Status**: INCOMPLETE -- `cast` not available. On-chain checks skipped.

Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
EOF
    exit 0
fi

echo "Collecting on-chain data: chain=$CHAIN, addresses=$(echo "$ADDRESSES" | tr ',' ' ' | wc -w | tr -d ' ')"

RPC_OK=1
OBSERVED_START_BLOCK=""
OBSERVED_START_HASH=""
if OBSERVED_START_BLOCK="$(cast block-number --rpc-url "$RPC_URL" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null)" && \
   [ -n "$OBSERVED_START_BLOCK" ]; then
    OBSERVED_START_HASH="$(cast block "$OBSERVED_START_BLOCK" --field hash \
        --rpc-url "$RPC_URL" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null || true)"
else
    RPC_OK=0
fi

redact_rpc_endpoint() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]]; then
        local proto host
        proto="${url%%://*}"
        host="${url#*://}"
        host="${host%%/*}"
        host="${host##*@}"
        echo "${proto}://${host}"
    else
        echo "<redacted>"
    fi
}

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

is_l2_chain() {
    local chain_lower
    chain_lower="$(to_lower "$1")"

    if command -v jq &>/dev/null && [ -f "$SKILL_DIR/config/chains.json" ]; then
        jq -er --arg c "$chain_lower" '
          ($c | ascii_downcase) as $lc
          | if .[$lc] then .[$lc].is_l2 // false
            else
              ([to_entries[]
                | select((((.value.aliases // []) | map(ascii_downcase) | index($lc)) != null))
                | .value.is_l2] | .[0] // false)
            end
        ' "$SKILL_DIR/config/chains.json" >/dev/null 2>&1
        return $?
    fi

    if command -v python3 &>/dev/null && [ -f "$SKILL_DIR/config/chains.json" ]; then
        python3 - "$SKILL_DIR/config/chains.json" "$chain_lower" <<'PY' >/dev/null 2>&1
import json
import sys

cfg_path, chain = sys.argv[1], sys.argv[2].lower()
with open(cfg_path, "r", encoding="utf-8") as fh:
    cfg = json.load(fh)

value = cfg.get(chain)
if isinstance(value, dict):
    raise SystemExit(0 if value.get("is_l2", False) else 1)

for entry in cfg.values():
    if not isinstance(entry, dict):
        continue
    aliases = [str(a).lower() for a in entry.get("aliases", [])]
    if chain in aliases:
        raise SystemExit(0 if entry.get("is_l2", False) else 1)

raise SystemExit(1)
PY
        return $?
    fi

    case "$chain_lower" in
        optimism|op|arbitrum|arb|base|polygon|matic|scroll|linea|zksync|zksync-era|era|blast|mantle|mode)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

RPC_DISPLAY="$(redact_rpc_endpoint "$RPC_URL")"
MIN_TIMELOCK_SECONDS=172800
MIN_TIMELOCK_LABEL="48h"
if is_l2_chain "$CHAIN"; then
    MIN_TIMELOCK_SECONDS=86400
    MIN_TIMELOCK_LABEL="24h (L2)"
fi

{
    echo "# On-Chain Data: $CHAIN"
    echo ""
    echo "**Collected**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "**RPC**: $RPC_DISPLAY"
    if [ "$RPC_OK" -eq 1 ]; then
        echo "**RPC Status**: reachable"
        echo "**Observation Start Block**: $OBSERVED_START_BLOCK"
        echo "**Observation Start Block Hash**: ${OBSERVED_START_HASH:-UNKNOWN - RPC did not return a hash}"
        echo "**Snapshot Semantics**: calls may span the start/end block interval recorded below; this helper output is not an atomic state snapshot unless the underlying procedure is independently pinned."
    else
        echo "**RPC Status**: unreachable (partial data only)"
    fi
    echo ""
} > "$OUTPUT"

validate_address() {
    [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "WARNING: Invalid address format, skipping: $1" >&2; return 1; }
}

IFS=',' read -ra ADDR_ARRAY <<< "$ADDRESSES"
VALID_ADDRS=()
for _a in "${ADDR_ARRAY[@]}"; do
    _a=$(echo "$_a" | tr -d '[:space:]')
    if [ -n "$_a" ] && validate_address "$_a"; then
        VALID_ADDRS+=("$_a")
    fi
done
if [ "${#VALID_ADDRS[@]}" -gt 0 ]; then
    ADDR_ARRAY=("${VALID_ADDRS[@]}")
else
    ADDR_ARRAY=()
fi
if [ "${#ADDR_ARRAY[@]}" -eq 0 ]; then
    echo "ERROR: No valid addresses provided" >&2
    exit 1
fi
ZERO_ADDR="0000000000000000000000000000000000000000"

# Wrapper for cast calls with consistent timeout
cast_call() {
    cast "$@" --rpc-url "$RPC_URL" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null
}

to_uint() {
    local value
    value="$(echo "$1" | tr -d '[:space:]')"
    [ -z "$value" ] && return 1

    if [[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf "%d" "$value" 2>/dev/null || return 1
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        return 1
    fi
}

decode_slot_address() {
    local slot_raw="$1"
    local slot_hex
    slot_hex="$(echo "${slot_raw#0x}" | tr '[:upper:]' '[:lower:]')"
    [ -z "$slot_hex" ] && return 1

    if [ "${#slot_hex}" -lt 64 ]; then
        slot_hex="$(printf "%064s" "$slot_hex" | tr ' ' '0')"
    elif [ "${#slot_hex}" -gt 64 ]; then
        slot_hex="${slot_hex: -64}"
    fi

    local addr_hex
    addr_hex="${slot_hex:24:40}"
    [ -z "$addr_hex" ] && return 1
    [ "$addr_hex" = "$ZERO_ADDR" ] && return 1
    echo "0x$addr_hex"
}

# --- Proxy Resolution ---
{
    echo "## Proxy Resolution"
    echo ""
    echo "| Address | Type | Implementation |"
    echo "|---------|------|----------------|"
} >> "$OUTPUT"

if [ "$RPC_OK" -eq 1 ]; then
    for addr in "${ADDR_ARRAY[@]}"; do
        addr=$(echo "$addr" | tr -d '[:space:]')
        [ -z "$addr" ] && continue

        # Check EIP-1967 implementation slot (transparent/UUPS proxies).
        IMPL_SLOT=$(cast_call storage "$addr" 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc || echo "0x0")
        IMPL_ADDR="$(decode_slot_address "$IMPL_SLOT" || true)"
        if [ -n "$IMPL_ADDR" ]; then
            echo "| $addr | Proxy (EIP-1967) | $IMPL_ADDR |" >> "$OUTPUT"
        else
            # Check EIP-1967 beacon slot (beacon proxies).
            BEACON_SLOT=$(cast_call storage "$addr" 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50 || echo "0x0")
            BEACON_ADDR="$(decode_slot_address "$BEACON_SLOT" || true)"
            if [ -n "$BEACON_ADDR" ]; then
                BEACON_IMPL=$(cast_call call "$BEACON_ADDR" "implementation()(address)" || echo "unknown")
                echo "| $addr | Beacon Proxy | Beacon: $BEACON_ADDR → Impl: $BEACON_IMPL |" >> "$OUTPUT"
            else
                # Check Diamond proxy (EIP-2535) via facetAddresses()
                FACETS=$(cast_call call "$addr" "facetAddresses()(address[])" || echo "")
                if [ -n "$FACETS" ] && [ "$FACETS" != "[]" ] && [ "$FACETS" != "" ]; then
                    echo "| $addr | Diamond (EIP-2535) | Facets: $FACETS |" >> "$OUTPUT"
                else
                    # Check Minimal proxy (EIP-1167) via bytecode pattern
                    BYTECODE=$(cast_call code "$addr" || echo "")
                    BYTECODE_LOWER="$(echo "$BYTECODE" | tr '[:upper:]' '[:lower:]')"
                    if [[ "$BYTECODE_LOWER" == "0x363d3d373d3d3d363d73"* ]]; then
                        CLONE_IMPL="0x${BYTECODE_LOWER:22:40}"
                        echo "| $addr | Minimal Proxy (EIP-1167) | $CLONE_IMPL |" >> "$OUTPUT"
                    else
                        # Try implementation() call
                        IMPL=$(cast_call call "$addr" "implementation()(address)" || echo "")
                        if [ -n "$IMPL" ] && [ "$IMPL" != "0x$ZERO_ADDR" ]; then
                            echo "| $addr | Proxy | $IMPL |" >> "$OUTPUT"
                        else
                            echo "| $addr | Direct (not proxy) | N/A |" >> "$OUTPUT"
                        fi
                    fi
                fi
            fi
        fi
    done
else
    for addr in "${ADDR_ARRAY[@]}"; do
        addr=$(echo "$addr" | tr -d '[:space:]')
        [ -z "$addr" ] && continue
        echo "| $addr | Unknown | RPC unreachable |" >> "$OUTPUT"
    done
fi

echo "" >> "$OUTPUT"

# --- Helper: Classify an address as EOA, Safe, Timelock, or Contract ---
classify_address() {
    local target="$1"
    [ -z "$target" ] && echo "unknown" && return

    # Check if it has code
    local code
    code=$(cast_call code "$target" | head -c 10)
    if [ -z "$code" ] || [ "$code" = "0x" ]; then
        echo "EOA"
        return
    fi

    # Check Gnosis Safe
    local threshold
    threshold=$(cast_call call "$target" "getThreshold()(uint256)" || echo "")
    if [ -n "$threshold" ] && [ "$threshold" != "0" ]; then
        echo "Safe"
        return
    fi

    # Check Timelock (getMinDelay or delay)
    local min_delay
    min_delay=$(cast_call call "$target" "getMinDelay()(uint256)" || echo "")
    if [ -n "$min_delay" ]; then
        echo "Timelock"
        return
    fi
    local delay
    delay=$(cast_call call "$target" "delay()(uint256)" || echo "")
    if [ -n "$delay" ]; then
        echo "Timelock"
        return
    fi

    # Check AccessManager (OZ v5.x) — canCall(address,address,bytes4) is unique to AccessManager
    if detect_access_manager "$target"; then
        echo "AccessManager"
        return
    fi

    echo "Contract"
}

# --- Helper: Detect OZ v5.x AccessManager ---
detect_access_manager() {
    local target="$1"
    # canCall(address,address,bytes4) returns (bool,uint32) — unique to AccessManager
    local result
    result=$(cast_call call "$target" "canCall(address,address,bytes4)(bool,uint32)" \
        "0x0000000000000000000000000000000000000000" \
        "0x0000000000000000000000000000000000000000" \
        "0x00000000") || return 1
    # If the call succeeded, it's an AccessManager
    [ -n "$result" ] && return 0
    return 1
}

# --- Helper: Resolve owner of an address (returns address or empty) ---
resolve_owner() {
    local target="$1"
    local owner_addr

    owner_addr=$(cast_call call "$target" "owner()(address)" || echo "")
    if [ -n "$owner_addr" ] && [ "$owner_addr" != "0x$ZERO_ADDR" ] && [ "$owner_addr" != "0x0000000000000000000000000000000000000000" ]; then
        echo "$owner_addr"
        return
    fi

    # Try admin() as fallback
    owner_addr=$(cast_call call "$target" "admin()(address)" || echo "")
    if [ -n "$owner_addr" ] && [ "$owner_addr" != "0x$ZERO_ADDR" ] && [ "$owner_addr" != "0x0000000000000000000000000000000000000000" ]; then
        echo "$owner_addr"
        return
    fi

    echo ""
}

# --- Admin / Multisig Detection (with governance chain tracing) ---
{
    echo "## Admin / Multisig Configuration"
    echo ""
} >> "$OUTPUT"

if [ "$RPC_OK" -eq 1 ]; then
    for addr in "${ADDR_ARRAY[@]}"; do
        addr=$(echo "$addr" | tr -d '[:space:]')
        [ -z "$addr" ] && continue

        OWNER=$(cast_call call "$addr" "owner()(address)" || echo "")
        ADMIN=$(cast_call call "$addr" "admin()(address)" || echo "")
        ADMIN_SLOT_RAW=$(cast_call storage "$addr" 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 || echo "0x0")
        ADMIN_SLOT_ADDR="$(decode_slot_address "$ADMIN_SLOT_RAW" || true)"

        CONTROL_ADDR=""
        CONTROL_SOURCE="unresolved"
        if [ -n "$ADMIN_SLOT_ADDR" ]; then
            CONTROL_ADDR="$ADMIN_SLOT_ADDR"
            CONTROL_SOURCE="EIP-1967 admin slot"
        elif [ -n "$ADMIN" ] && [ "$ADMIN" != "0x$ZERO_ADDR" ]; then
            CONTROL_ADDR="$ADMIN"
            CONTROL_SOURCE="admin()"
        elif [ -n "$OWNER" ] && [ "$OWNER" != "0x$ZERO_ADDR" ]; then
            CONTROL_ADDR="$OWNER"
            CONTROL_SOURCE="owner()"
        fi

        {
            echo "### $addr"
            echo "- **owner()**: ${OWNER:-N/A}"
            echo "- **admin()**: ${ADMIN:-N/A}"
            echo "- **EIP-1967 admin slot**: ${ADMIN_SLOT_ADDR:-N/A}"
            echo "- **Effective Control (L0)**: ${CONTROL_ADDR:-unresolved} ($CONTROL_SOURCE)"
        } >> "$OUTPUT"

        if [ -n "$CONTROL_ADDR" ]; then
            # Trace governance chain up to 3 levels deep with cycle detection
            CURRENT="$CONTROL_ADDR"
            CHAIN_SUMMARY="$CONTROL_ADDR"
            TERMINAL_TYPE=""
            VISITED_ADDRS="$CONTROL_ADDR"
            for LEVEL in 1 2 3; do
                ADDR_TYPE=$(classify_address "$CURRENT")
                echo "- **L${LEVEL} ($CURRENT)**: $ADDR_TYPE" >> "$OUTPUT"

                if [ "$ADDR_TYPE" = "EOA" ]; then
                    TERMINAL_TYPE="EOA"
                    break
                elif [ "$ADDR_TYPE" = "Safe" ]; then
                    THRESHOLD=$(cast_call call "$CURRENT" "getThreshold()(uint256)" || echo "?")
                    OWNERS_RAW=$(cast_call call "$CURRENT" "getOwners()(address[])" || echo "")
                    OWNER_COUNT=$(echo "$OWNERS_RAW" | tr ',' '\n' | grep -c "0x" 2>/dev/null || echo "?")
                    echo "  - Threshold: $THRESHOLD of $OWNER_COUNT" >> "$OUTPUT"
                    echo "  - Signers: $OWNERS_RAW" >> "$OUTPUT"
                    TERMINAL_TYPE="Safe ($THRESHOLD/$OWNER_COUNT)"
                    break
                elif [ "$ADDR_TYPE" = "Timelock" ]; then
                    DELAY_RAW=$(cast_call call "$CURRENT" "getMinDelay()(uint256)" || \
                                cast_call call "$CURRENT" "delay()(uint256)" || echo "?")
                    DELAY_VAL=$(to_uint "$DELAY_RAW" 2>/dev/null || echo "?")
                    if [ "$DELAY_VAL" != "?" ]; then
                        DELAY_H=$(echo "$(( DELAY_VAL / 3600 ))h$(( (DELAY_VAL % 3600) / 60 ))m" 2>/dev/null || echo "?")
                        echo "  - Delay: ${DELAY_VAL}s (~${DELAY_H}h)" >> "$OUTPUT"
                    fi
                    CHAIN_SUMMARY="$CHAIN_SUMMARY → Timelock(${DELAY_H:-?}h)"
                    # Trace through timelock to find its admin
                    NEXT=$(resolve_owner "$CURRENT")
                    if [ -n "$NEXT" ] && [ "$NEXT" != "$CURRENT" ]; then
                        # Cycle detection: check if we've visited this address before
                        NEXT_LOWER="$(echo "$NEXT" | tr '[:upper:]' '[:lower:]')"
                        if echo "$VISITED_ADDRS" | tr '[:upper:]' '[:lower:]' | grep -qF "$NEXT_LOWER"; then
                            echo "  - **⚠ CYCLE DETECTED**: $NEXT already visited in governance chain" >> "$OUTPUT"
                            TERMINAL_TYPE="Circular ownership (cycle at $NEXT)"
                            break
                        fi
                        VISITED_ADDRS="$VISITED_ADDRS $NEXT"
                        CURRENT="$NEXT"
                        CHAIN_SUMMARY="$CHAIN_SUMMARY → $NEXT"
                        continue
                    fi
                    TERMINAL_TYPE="Timelock"
                    break
                else
                    NEXT=$(resolve_owner "$CURRENT")
                    if [ -n "$NEXT" ] && [ "$NEXT" != "$CURRENT" ]; then
                        # Cycle detection
                        NEXT_LOWER="$(echo "$NEXT" | tr '[:upper:]' '[:lower:]')"
                        if echo "$VISITED_ADDRS" | tr '[:upper:]' '[:lower:]' | grep -qF "$NEXT_LOWER"; then
                            echo "  - **⚠ CYCLE DETECTED**: $NEXT already visited in governance chain" >> "$OUTPUT"
                            TERMINAL_TYPE="Circular ownership (cycle at $NEXT)"
                            break
                        fi
                        VISITED_ADDRS="$VISITED_ADDRS $NEXT"
                        CURRENT="$NEXT"
                        CHAIN_SUMMARY="$CHAIN_SUMMARY → $NEXT"
                        continue
                    fi
                    TERMINAL_TYPE="Contract (unknown)"
                    break
                fi
            done

            echo "- **Governance Chain**: $CHAIN_SUMMARY" >> "$OUTPUT"
            echo "- **Terminal Authority**: $TERMINAL_TYPE" >> "$OUTPUT"

            if [ "$TERMINAL_TYPE" = "EOA" ]; then
                echo "- **⚠ DEAL BREAKER RISK**: Governance chain terminates at EOA" >> "$OUTPUT"
            fi
        fi
        echo "" >> "$OUTPUT"
    done
else
    {
        echo "- RPC unreachable: admin/multisig configuration could not be queried."
        echo ""
    } >> "$OUTPUT"
fi

# --- Permission Event Logs (AccessControl / Ownable / Auth) ---
{
    echo "## Permission Event Logs"
    echo ""
    echo "Each count below is bound to the queried address and block window stated in its STATUS; PARTIAL or FAILED queries are not zero counts. Raw responses: tmp/collect-onchain-data/<run>/logs/."
    echo ""
} >> "$OUTPUT"

# Event-log collection discipline (references/evm-tools.md, "Counting
# discipline"): a log count is evidence only when every block range in the
# window was actually answered. This fetcher therefore
#   - walks explicit [from,to] windows in chunks with retry/backoff and halves
#     the chunk on provider limits instead of giving up on the whole range;
#   - never turns a failed range into "0 events": the first output line is a
#     STATUS record naming the window, the request count and any FAILED ranges;
#   - starts at the contract creation block when the node can serve historical
#     code (binary search over eth_getCode), else at block 0 under a request
#     budget, and reports the uncovered remainder;
#   - retains every raw response under tmp/collect-onchain-data/<run>/logs/.
# Override the defaults for a provider's limits (for example LOG_CHUNK_BLOCKS=10000
# on free tiers that cap eth_getLogs at 10k blocks).
LOG_CHUNK_BLOCKS="${LOG_CHUNK_BLOCKS:-100000}"
LOG_MIN_CHUNK_BLOCKS="${LOG_MIN_CHUNK_BLOCKS:-2000}"
LOG_RETRIES="${LOG_RETRIES:-3}"
LOG_RETRY_DELAY="${LOG_RETRY_DELAY:-2}"
LOG_MAX_REQUESTS="${LOG_MAX_REQUESTS:-400}"
LOG_INCOMPLETE_QUERIES=0
LOG_RUN_DIR=""
if LOG_RUN_DIR="$(audit_create_retained_run_dir "$WORKSPACE" "collect-onchain-data" "logs" 2>/dev/null)" && [ -n "$LOG_RUN_DIR" ]; then
    mkdir -p "$LOG_RUN_DIR/logs" 2>/dev/null || LOG_RUN_DIR=""
fi

# Binary-search the first block at which the address has code. Needs an archive
# capable node; prints nothing (caller falls back to block 0) on any RPC error.
find_creation_block() {
    local addr="$1"
    local latest="$2"
    local cache="${LOG_RUN_DIR:-}/creation-$addr.txt"
    if [ -n "$LOG_RUN_DIR" ] && [ -s "$cache" ]; then
        cat "$cache"
        return 0
    fi
    local lo=0 hi="$latest" mid code
    # Two probes decide whether historical code is served at all.
    code="$(cast code "$addr" --block "$hi" --rpc-url "$RPC_URL" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null)" || return 1
    [ -n "$code" ] && [ "$code" != "0x" ] || return 1
    code="$(cast code "$addr" --block 0 --rpc-url "$RPC_URL" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null)" || return 1
    while [ "$lo" -lt "$hi" ]; do
        mid=$(( (lo + hi) / 2 ))
        code="$(cast code "$addr" --block "$mid" --rpc-url "$RPC_URL" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null)" || return 1
        if [ -n "$code" ] && [ "$code" != "0x" ]; then
            hi="$mid"
        else
            lo=$((mid + 1))
        fi
    done
    [ -n "$LOG_RUN_DIR" ] && printf '%s\n' "$lo" > "$cache" 2>/dev/null
    printf '%s\n' "$lo"
}

# Prints one STATUS line followed by the raw `cast logs` output.
#   STATUS=COMPLETE|PARTIAL|FAILED from=<block> to=<block> requests=<n> failed_ranges=<a-b,...|none> uncovered=<a-b|none>
fetch_event_logs() {
    local addr="$1"
    local topic0="$2"
    local rpc="$3"
    local to="${OBSERVED_START_BLOCK:-}"
    [ -n "$to" ] || to="$(cast block-number --rpc-url "$rpc" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null || echo "")"
    if [ -z "$to" ]; then
        printf 'STATUS=FAILED from=? to=? requests=0 failed_ranges=all uncovered=all\n'
        return 1
    fi
    local from
    from="$(find_creation_block "$addr" "$to" 2>/dev/null || echo 0)"
    [ -n "$from" ] || from=0
    local chunk="$LOG_CHUNK_BLOCKS" cur="$from" end requests=0 attempt ok failed="" uncovered="none" result
    local body errfile range_error provider_cap
    body="$(mktemp "${TMPDIR:-/tmp}/contract-audit-logs.XXXXXX")" || return 1
    errfile="$(mktemp "${TMPDIR:-/tmp}/contract-audit-logs-err.XXXXXX")" || { rm -f "$body"; return 1; }
    while [ "$cur" -le "$to" ]; do
        end=$((cur + chunk - 1))
        [ "$end" -gt "$to" ] && end="$to"
        if [ "$requests" -ge "$LOG_MAX_REQUESTS" ]; then
            uncovered="$cur-$to"
            break
        fi
        attempt=0
        ok=0
        range_error=0
        while [ "$attempt" -lt "$LOG_RETRIES" ]; do
            requests=$((requests + 1))
            if result="$(cast logs --from-block "$cur" --to-block "$end" --address "$addr" "$topic0" \
                    --rpc-url "$rpc" --rpc-timeout "$CAST_TIMEOUT" 2>"$errfile")"; then
                ok=1
                [ -n "$result" ] && printf '%s\n' "$result" >> "$body"
                break
            fi
            # A provider window/result cap is deterministic: shrink at once
            # instead of retrying the same range. Only transport errors retry.
            if grep -Eiq 'range|limit|too (many|large)|exceed|more than|10000|results' "$errfile"; then
                range_error=1
                # Use the provider's stated cap when it names one
                # ("range 100000 exceeds limit of 10000").
                provider_cap="$(grep -Eio 'limit of [0-9]+|max(imum)? (block )?range( is| of)? [0-9]+|[0-9]+ block(s)? range' "$errfile" \
                    | grep -Eo '[0-9]+' | head -1)"
                if [ -n "$provider_cap" ] && [ "$provider_cap" -ge "$LOG_MIN_CHUNK_BLOCKS" ] 2>/dev/null \
                   && [ "$provider_cap" -lt "$chunk" ]; then
                    chunk="$provider_cap"
                else
                    chunk=$((chunk / 2))
                fi
                [ "$chunk" -lt "$LOG_MIN_CHUNK_BLOCKS" ] && chunk="$LOG_MIN_CHUNK_BLOCKS"
                break
            fi
            attempt=$((attempt + 1))
            sleep $((LOG_RETRY_DELAY * attempt))
        done
        if [ "$ok" -eq 1 ]; then
            cur=$((end + 1))
        elif [ "$range_error" -eq 1 ] && [ "$end" -gt $((cur + LOG_MIN_CHUNK_BLOCKS - 1)) ]; then
            : # chunk was resized above; retry the same start block with the smaller window
        elif [ "$chunk" -gt "$LOG_MIN_CHUNK_BLOCKS" ]; then
            chunk=$((chunk / 2))
            [ "$chunk" -lt "$LOG_MIN_CHUNK_BLOCKS" ] && chunk="$LOG_MIN_CHUNK_BLOCKS"
        else
            failed="${failed:+$failed,}$cur-$end"
            cur=$((end + 1))
        fi
    done
    rm -f "$errfile"
    # COMPLETE: every block in [from,to] answered. PARTIAL: some answered, some
    # failed or not queried (budget). FAILED: nothing answered at all.
    local status="COMPLETE" covered="$from-$to"
    if [ -n "$failed" ] || [ "$uncovered" != "none" ]; then
        status="PARTIAL"
        if [ "$uncovered" != "none" ]; then
            covered="$from-$((cur - 1))"
        fi
        if [ "$cur" -le "$from" ] && [ "$uncovered" != "none" ]; then
            status="FAILED"
            covered="none"
        elif [ -n "$failed" ] && [ "$uncovered" = "none" ] && [ "$failed" = "$from-$to" ]; then
            status="FAILED"
            covered="none"
        fi
    fi
    printf 'STATUS=%s from=%s to=%s covered=%s requests=%s failed_ranges=%s uncovered=%s\n' \
        "$status" "$from" "$to" "$covered" "$requests" "${failed:-none}" "$uncovered"
    cat "$body"
    if [ -n "$LOG_RUN_DIR" ]; then
        {
            printf 'STATUS=%s from=%s to=%s covered=%s requests=%s failed_ranges=%s uncovered=%s\n' \
                "$status" "$from" "$to" "$covered" "$requests" "${failed:-none}" "$uncovered"
            cat "$body"
        } > "$LOG_RUN_DIR/logs/$addr-$topic0.txt" 2>/dev/null
    fi
    rm -f "$body"
    [ "$status" != "FAILED" ]
}

count_log_entries() {
    # grep -c prints 0 itself when nothing matches (and exits 1), so no fallback
    # echo: that would print a second line.
    echo "$1" | grep -c "^- address:" 2>/dev/null || true
}

last_log_entry() {
    echo "$1" | grep -A6 "^- address:" | tail -7
}

# Writes one event section to $OUTPUT.
#   report_event_logs <addr> <topic0> <label> <style> [heading-prefix] [intro]
# style: last | list20 | head:N   heading-prefix: "**" (bold line) or "###"
report_event_logs() {
    local addr="$1" topic0="$2" label="$3" style="$4" prefix="${5:-**}" intro="${6:-}"
    local raw header body status failed uncovered count note open close
    raw="$(fetch_event_logs "$addr" "$topic0" "$RPC_URL" 2>/dev/null || true)"
    header="${raw%%
*}"
    body="${raw#*
}"
    [ "$body" = "$raw" ] && body=""
    status="$(printf '%s\n' "$header" | sed -n 's/^STATUS=\([A-Z]*\).*/\1/p')"
    covered="$(printf '%s\n' "$header" | sed -n 's/.* covered=\([^ ]*\).*/\1/p')"
    failed="$(printf '%s\n' "$header" | sed -n 's/.*failed_ranges=\([^ ]*\).*/\1/p')"
    uncovered="$(printf '%s\n' "$header" | sed -n 's/.*uncovered=\([^ ]*\).*/\1/p')"
    count="$(count_log_entries "$body")"
    # fetch_event_logs runs in a command substitution, so the incomplete-query
    # counter is maintained here, in the parent shell.
    [ "$status" = "COMPLETE" ] || LOG_INCOMPLETE_QUERIES=$((LOG_INCOMPLETE_QUERIES + 1))
    case "$status" in
        COMPLETE) note=" (blocks ${covered})" ;;
        PARTIAL)
            note=" (PARTIAL: counted over blocks ${covered}; failed ranges ${failed:-none}; not queried ${uncovered:-none}. A zero or low count is not evidence of absence; raise LOG_MAX_REQUESTS or use a provider with a larger eth_getLogs window to close the gap)" ;;
        *)
            count="unknown"
            note=" (FAILED: no block range was answered; count unknown, not zero)" ;;
    esac
    if [ "$prefix" = "###" ]; then
        open="### $label: $count events$note"
    else
        open="**$label**: $count events$note"
    fi
    {
        echo "$open"
        [ -n "$intro" ] && { echo ""; echo "$intro"; }
        if [ "$count" != "unknown" ] && [ "$count" -gt 0 ] 2>/dev/null; then
            case "$style" in
                last)
                    echo ""
                    echo "Last event:"
                    echo '```'
                    last_log_entry "$body"
                    echo '```'
                    ;;
                list20)
                    if [ "$count" -le 20 ]; then
                        echo '```'
                        echo "$body"
                        echo '```'
                    else
                        echo ""
                        echo "Last 5 events:"
                        echo '```'
                        echo "$body" | grep -A6 "^- address:" | tail -35
                        echo '```'
                    fi
                    ;;
                head:*)
                    echo '```'
                    echo "$body" | head -"${style#head:}"
                    echo '```'
                    ;;
            esac
        fi
        [ "$prefix" = "###" ] && echo ""
    } >> "$OUTPUT"
}

OT_TOPIC="0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0"
RG_TOPIC="0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d"
RR_TOPIC="0xf6391f5c32d9c69d2a47ea670b442974b53935d1edc7fd64eb21e047a839171b"
RAC_TOPIC="0xbd79b86ffe0ab8e8776151514217cd7cacd52c909f66475c3af44e129f0b00ff"

# AccessManager (OZ v5.x) event topics
AM_TFRU_TOPIC="0x890e839457e04a3aae51bfccb2c80666a70596e4db8a2999e759b8e54a05e3f0"  # TargetFunctionRoleUpdated(address,bytes4,uint64)
AM_OPSCHED_TOPIC="0x40cdc8e5e35e14bdf7bf939b2e910cc2c41dd6766924135dde1bece37e4c0edb"  # OperationScheduled(bytes32,uint48,address,address,bytes)
AM_RGCHANGE_TOPIC="0xce793a3dbbcb2e1a3ae1389e1ca99391a8b6bccea0e55a35df39bb21282b4b29"  # RoleGuardianChanged(uint64,uint64)
AM_TGTCLOSED_TOPIC="0x044086693c0e06e11d1399f5b8b56a47c5dcc99159685f0aee044b4adaaea4e4"  # TargetClosed(address,bool)

if [ "$RPC_OK" -eq 1 ]; then
    for addr in "${ADDR_ARRAY[@]}"; do
        addr=$(echo "$addr" | tr -d '[:space:]')
        [ -z "$addr" ] && continue

        echo "### $addr" >> "$OUTPUT"
        echo "" >> "$OUTPUT"

        echo "Queried address: $addr. Events emitted by another contract (for example a separate access manager or token) are not counted here." >> "$OUTPUT"
        echo "" >> "$OUTPUT"
        report_event_logs "$addr" "$OT_TOPIC" "OwnershipTransferred" last
        report_event_logs "$addr" "$RG_TOPIC" "RoleGranted" list20
        report_event_logs "$addr" "$RR_TOPIC" "RoleRevoked" list20
        report_event_logs "$addr" "$RAC_TOPIC" "RoleAdminChanged" head:42

        echo "" >> "$OUTPUT"
    done
else
    echo "RPC unreachable: permission event logs skipped." >> "$OUTPUT"
    echo "" >> "$OUTPUT"
fi

# --- AccessManager State (OZ v5.x) ---
# Collect state for addresses classified as AccessManager during admin detection
if [ "$RPC_OK" -eq 1 ]; then
    for addr in "${ADDR_ARRAY[@]}"; do
        addr=$(echo "$addr" | tr -d '[:space:]')
        [ -z "$addr" ] && continue

        # Only process if this address is an AccessManager
        if ! detect_access_manager "$addr"; then
            continue
        fi

        {
            echo "## AccessManager State: $addr"
            echo ""
        } >> "$OUTPUT"

        report_event_logs "$addr" "$AM_TFRU_TOPIC" "TargetFunctionRoleUpdated" head:100 "###" \
            "Maps (target, selector) → roleId. Use to reconstruct the permission map."
        report_event_logs "$addr" "$AM_OPSCHED_TOPIC" "OperationScheduled" head:100 "###" \
            "Pending timelocked operations. Cross-reference with OperationExecuted to find unexecuted ops."
        report_event_logs "$addr" "$AM_RGCHANGE_TOPIC" "RoleGuardianChanged" head:50 "###" \
            "Guardian assignment for roles. Guardians can cancel scheduled operations."
        report_event_logs "$addr" "$AM_TGTCLOSED_TOPIC" "TargetClosed" head:50 "###" \
            "Closed targets block all function calls regardless of role."
    done
fi

# --- Timelock Detection ---
{
    echo "## Timelock Configuration"
    echo ""
} >> "$OUTPUT"

if [ "$RPC_OK" -eq 1 ]; then
    for addr in "${ADDR_ARRAY[@]}"; do
        addr=$(echo "$addr" | tr -d '[:space:]')
        [ -z "$addr" ] && continue

        # Try common timelock interfaces
        MIN_DELAY_RAW=$(cast_call call "$addr" "getMinDelay()(uint256)" || echo "")
        HAS_MIN_DELAY=0
        MIN_DELAY=""
        if MIN_DELAY="$(to_uint "$MIN_DELAY_RAW")"; then
            HAS_MIN_DELAY=1
            DELAY_HOURS="$(( MIN_DELAY / 3600 ))h$(( (MIN_DELAY % 3600) / 60 ))m"
            {
                echo "### $addr"
                echo "- **Min Delay**: ${MIN_DELAY}s (~${DELAY_HOURS}h)"
                if [ "$MIN_DELAY" -eq 0 ] 2>/dev/null; then
                    echo "- **⚠ WARNING**: Delay is 0s (deal-breaker risk)"
                elif [ "$MIN_DELAY" -lt "$MIN_TIMELOCK_SECONDS" ] 2>/dev/null; then
                    echo "- **⚠ WARNING**: Delay < ${MIN_TIMELOCK_LABEL}"
                else
                    echo "- **Status**: ✓ Adequate (≥${MIN_TIMELOCK_LABEL})"
                fi
                echo ""
            } >> "$OUTPUT"
        fi

        DELAY_RAW=$(cast_call call "$addr" "delay()(uint256)" || echo "")
        if [ "$HAS_MIN_DELAY" -eq 0 ] && DELAY="$(to_uint "$DELAY_RAW")"; then
            DELAY_HOURS="$(( DELAY / 3600 ))h$(( (DELAY % 3600) / 60 ))m"
            {
                echo "### $addr"
                echo "- **Delay**: ${DELAY}s (~${DELAY_HOURS}h)"
                if [ "$DELAY" -eq 0 ] 2>/dev/null; then
                    echo "- **⚠ WARNING**: Delay is 0s (deal-breaker risk)"
                elif [ "$DELAY" -lt "$MIN_TIMELOCK_SECONDS" ] 2>/dev/null; then
                    echo "- **⚠ WARNING**: Delay < ${MIN_TIMELOCK_LABEL}"
                else
                    echo "- **Status**: ✓ Adequate (≥${MIN_TIMELOCK_LABEL})"
                fi
                echo ""
            } >> "$OUTPUT"
        fi
    done
else
    {
        echo "- RPC unreachable: timelock configuration could not be queried."
        echo ""
    } >> "$OUTPUT"
fi

# --- Contract Deployment Status ---
{
    echo "## Contract Deployment Status"
    echo ""
    echo "| Address | Status |"
    echo "|---------|--------|"
} >> "$OUTPUT"

for addr in "${ADDR_ARRAY[@]}"; do
    addr=$(echo "$addr" | tr -d '[:space:]')
    [ -z "$addr" ] && continue

    if [ "$RPC_OK" -eq 0 ]; then
        echo "| $addr | Unknown (RPC unreachable) |" >> "$OUTPUT"
        continue
    fi

    # Get code to verify it's a contract.
    CODE=$(cast_call code "$addr" | head -c 10)
    if [ -n "$CODE" ] && [ "$CODE" != "0x" ]; then
        echo "| $addr | Deployed contract (code present) |" >> "$OUTPUT"
    else
        echo "| $addr | Not a contract |" >> "$OUTPUT"
    fi
done

echo "" >> "$OUTPUT"

# --- Collection Summary ---
STATUS="complete"
[ "$RPC_OK" -eq 0 ] && STATUS="partial (RPC unreachable)"
[ "$RPC_OK" -eq 1 ] && [ "$LOG_INCOMPLETE_QUERIES" -gt 0 ] && STATUS="partial ($LOG_INCOMPLETE_QUERIES incomplete log queries)"

{
    echo "## Collection Summary"
    echo ""
    if [ "$RPC_OK" -eq 1 ]; then
        OBSERVED_END_BLOCK="$(cast block-number --rpc-url "$RPC_URL" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null || true)"
        OBSERVED_END_HASH=""
        if [ -n "$OBSERVED_END_BLOCK" ]; then
            OBSERVED_END_HASH="$(cast block "$OBSERVED_END_BLOCK" --field hash \
                --rpc-url "$RPC_URL" --rpc-timeout "$CAST_TIMEOUT" 2>/dev/null || true)"
        fi
        echo "- Observation start: block $OBSERVED_START_BLOCK / ${OBSERVED_START_HASH:-hash unavailable}"
        echo "- Observation end: block ${OBSERVED_END_BLOCK:-unavailable} / ${OBSERVED_END_HASH:-hash unavailable}"
        echo "- Fidelity: non-atomic observation window unless a separate pinned procedure establishes one-state correspondence"
        echo ""
    fi
    echo "| Section | Status |"
    echo "|---------|--------|"
    if [ "$RPC_OK" -eq 1 ]; then
        echo "| Proxy resolution | done |"
        echo "| Admin/multisig | done |"
        if [ "$LOG_INCOMPLETE_QUERIES" -gt 0 ]; then
            echo "| Permission events | INCOMPLETE ($LOG_INCOMPLETE_QUERIES log queries partial or failed; see per-address STATUS notes) |"
        else
            echo "| Permission events | done |"
        fi
        echo "| Timelock | done |"
        echo "| Deployment status | done |"
    else
        echo "| Proxy resolution | skipped |"
        echo "| Admin/multisig | skipped |"
        echo "| Permission events | skipped |"
        echo "| Timelock | skipped |"
        echo "| Deployment status | partial |"
    fi
    echo ""
    echo "Token distribution and TVL data are fetched separately via DeFiLlama/Dune."
} >> "$OUTPUT"

echo "=== On-chain collection $STATUS ==="
echo "Output: $OUTPUT"
exit 0
