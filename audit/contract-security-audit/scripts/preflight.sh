#!/usr/bin/env bash
set -euo pipefail

# Usage: preflight.sh [workspace-dir]
# Detects local tool availability and writes:
#   - <workspace>/tool-resolution.md
#   - <workspace>/tool-resolution.env

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="${1:-audit-workspace}"
mkdir -p "$WORKSPACE"

# Load .env files via shared loader (shell → workspace → active skill → fallbacks)
export SKILL_DIR WORKSPACE
source "$(dirname "$0")/load-env.sh"

OUT_MD="$WORKSPACE/tool-resolution.md"
OUT_ENV="$WORKSPACE/tool-resolution.env"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

source "$(dirname "$0")/retention.sh"
audit_archive_existing "$WORKSPACE" "preflight" "$OUT_MD" "$OUT_ENV" || {
    echo "ERROR: refusing to replace preflight output without retaining the prior version" >&2
    exit 1
}

# --- Extend PATH for common tool locations ---
for dir in \
    "$HOME/.foundry/bin" \
    "$HOME/.local/bin" \
    "$HOME/bin" \
    "$HOME/.cargo/bin" \
    "/opt/homebrew/bin" \
    "/usr/local/bin"; do
    if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
        PATH="$dir:$PATH"
    fi
done
export PATH

check_bin() {
    local bin="$1"
    if command -v "$bin" >/dev/null 2>&1; then
        echo "available|$(command -v "$bin")"
    else
        echo "missing|-"
    fi
}

get_version() {
    local bin="$1"
    local ver=""
    case "$bin" in
        cast)   ver=$(cast --version 2>/dev/null | head -1) ;;
        forge)  ver=$(forge --version 2>/dev/null | head -1) ;;
        jq)     ver=$(jq --version 2>/dev/null | head -1) ;;
        python3) ver=$(python3 --version 2>/dev/null | head -1) ;;
    esac
    echo "${ver:-unknown}"
}

read -r CAST_STATUS CAST_PATH <<<"$(check_bin cast | tr '|' ' ')"
read -r FORGE_STATUS FORGE_PATH <<<"$(check_bin forge | tr '|' ' ')"
read -r JQ_STATUS JQ_PATH <<<"$(check_bin jq | tr '|' ' ')"
read -r PY_STATUS PY_PATH <<<"$(check_bin python3 | tr '|' ' ')"

CAST_VER="-"; [ "$CAST_STATUS" = "available" ] && CAST_VER=$(get_version cast)
FORGE_VER="-"; [ "$FORGE_STATUS" = "available" ] && FORGE_VER=$(get_version forge)
JQ_VER="-"; [ "$JQ_STATUS" = "available" ] && JQ_VER=$(get_version jq)
PY_VER="-"; [ "$PY_STATUS" = "available" ] && PY_VER=$(get_version python3)

TIMEOUT_IMPL="none"
TIMEOUT_PATH="-"
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_IMPL="timeout"
    TIMEOUT_PATH="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_IMPL="gtimeout"
    TIMEOUT_PATH="$(command -v gtimeout)"
fi

HAS_CAST=false
HAS_FORGE=false
HAS_JQ=false
HAS_PYTHON3=false

[ "$CAST_STATUS" = "available" ] && HAS_CAST=true
[ "$FORGE_STATUS" = "available" ] && HAS_FORGE=true
[ "$JQ_STATUS" = "available" ] && HAS_JQ=true
[ "$PY_STATUS" = "available" ] && HAS_PYTHON3=true

# --- ETHERSCAN_API_KEY detection with improved messaging ---
ETHERSCAN_V2_STATUS="not configured"
ETHERSCAN_KEY_SOURCE=""
HAS_ETHERSCAN_V2=false

if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
    HAS_ETHERSCAN_V2=true
    # Determine source
    if printenv ETHERSCAN_API_KEY >/dev/null 2>&1; then
        ETHERSCAN_KEY_SOURCE="environment"
    else
        ETHERSCAN_KEY_SOURCE=".env file"
    fi
    ETHERSCAN_V2_STATUS="configured (source: $ETHERSCAN_KEY_SOURCE)"

    # Warn if key appears too short
    if [ "${#ETHERSCAN_API_KEY}" -lt 10 ]; then
        echo "WARNING: ETHERSCAN_API_KEY appears too short (${#ETHERSCAN_API_KEY} chars) — verify it is valid" >&2
    fi
else
    cat >&2 <<HINT
HINT: ETHERSCAN_API_KEY is not set. Explorer API calls will be limited.
  Set it in one of these locations (checked in order):
    1. Environment variable: export ETHERSCAN_API_KEY=your_key
    2. $WORKSPACE/.env                                     (per-audit)
    3. $SKILL_DIR/.env                                     (active skill)
    4. Active agent global (Hermes, Codex, Claude config root, or OpenClaw when signaled)
    5. ~/.env                                              (user fallback)

  Another agent runtime's skill .env is never loaded implicitly.
HINT
fi

cat >"$OUT_MD" <<EOF
# Tool Resolution

**Collected**: $NOW_UTC

| Tool | Status | Version |
|------|--------|---------|
| cast | $CAST_STATUS | $CAST_VER |
| forge | $FORGE_STATUS | $FORGE_VER |
| jq | $JQ_STATUS | $JQ_VER |
| python3 | $PY_STATUS | $PY_VER |
| timeout | $TIMEOUT_IMPL | - |

## Explorer API

| Config | Status |
|--------|--------|
| Etherscan V2 (unified) | $ETHERSCAN_V2_STATUS |

\`ETHERSCAN_API_KEY\` enables Etherscan V2 API (single key, all chains). Chain-specific keys serve as fallback.

## Capabilities

- **On-chain queries**: $([ "$CAST_STATUS" = "available" ] && echo "yes (cast)" || echo "NO — install Foundry")
- **Optional Foundry execution**: $([ "$FORGE_STATUS" = "available" ] && echo "available (forge)" || echo "unavailable — choose another sound verification method or install forge only if needed")
- **JSON-backed bundled helpers**: $([ "$JQ_STATUS" = "available" ] && echo "available (jq)" || { [ "$PY_STATUS" = "available" ] && echo "available (python3)" || echo "unavailable — use another review/verification method, or install jq/python3 before invoking those helpers"; })
- **Event log scanning**: $([ "$CAST_STATUS" = "available" ] && echo "yes" || echo "NO") (requires cast + reliable RPC)
EOF

cat >"$OUT_ENV" <<EOF
HAS_CAST=$HAS_CAST
HAS_FORGE=$HAS_FORGE
HAS_JQ=$HAS_JQ
HAS_PYTHON3=$HAS_PYTHON3
HAS_ETHERSCAN_V2=$HAS_ETHERSCAN_V2
TIMEOUT_IMPL=$TIMEOUT_IMPL
EOF

# --- Public RPC detection ---
# Warn when RPC env vars are not set (will fall back to public defaults)
PUBLIC_RPC_WARNING=""
RPC_ENVS="ETH_RPC_URL ARBITRUM_RPC_URL OPTIMISM_RPC_URL BASE_RPC_URL POLYGON_RPC_URL BSC_RPC_URL AVALANCHE_RPC_URL"
UNSET_RPC_COUNT=0
for rpc_var in $RPC_ENVS; do
    if [ -z "${!rpc_var:-}" ]; then
        UNSET_RPC_COUNT=$((UNSET_RPC_COUNT + 1))
    fi
done
if [ "$UNSET_RPC_COUNT" -gt 3 ]; then
    PUBLIC_RPC_WARNING="WARNING: Most chain RPC env vars are unset. Public RPCs will be used as fallback — these are rate-limited and may fail on eth_getLogs queries needed for permission event scanning. Set dedicated RPC URLs (Alchemy, Infura, QuickNode) for reliable audits."
    echo "$PUBLIC_RPC_WARNING" >&2
fi

# Append RPC warning to markdown report if applicable
if [ -n "$PUBLIC_RPC_WARNING" ]; then
    {
        echo ""
        echo "## RPC Configuration"
        echo ""
        echo "**⚠ $PUBLIC_RPC_WARNING**"
        echo ""
        echo "Set RPC env vars in \`.env\` or shell environment:"
        echo '```'
        echo "ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
        echo "ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY"
        echo '```'
    } >> "$OUT_MD"
fi

# --- Bundled-helper capability assessment ---
# No individual helper is a universal audit prerequisite. Missing tools only
# constrain helpers that actually need them; they do not constrain discovery or
# validation methods and do not determine whether a claim is true. Forge is one
# optional verification technique, and jq/python3 are only needed by JSON-backed
# bundled helpers.
AUDIT_MODE="full"
MISSING_OPTIONAL=""

if [ "$HAS_JQ" = "false" ] && [ "$HAS_PYTHON3" = "false" ]; then
    MISSING_OPTIONAL="${MISSING_OPTIONAL}jq/python3(JSON-helpers-unavailable) "
fi

if [ "$HAS_CAST" = "false" ]; then
    MISSING_OPTIONAL="${MISSING_OPTIONAL}cast(reduced-onchain-confidence) "
fi
if [ "$HAS_FORGE" = "false" ]; then
    MISSING_OPTIONAL="${MISSING_OPTIONAL}forge(optional-Foundry-execution-unavailable) "
fi
if [ "$HAS_ETHERSCAN_V2" = "false" ]; then
    MISSING_OPTIONAL="${MISSING_OPTIONAL}ETHERSCAN_API_KEY(chain-keys-fallback) "
fi

if [ -n "$MISSING_OPTIONAL" ]; then
    AUDIT_MODE="degraded"
fi

# Append audit mode to env file
echo "AUDIT_MODE=$AUDIT_MODE" >> "$OUT_ENV"

# Append audit mode to markdown report
{
    echo ""
    echo "## Bundled Helper Capability Mode"
    echo ""
    echo "**Mode**: \`$AUDIT_MODE\`"
    if [ -n "$MISSING_OPTIONAL" ]; then
        echo "**Unavailable or reduced helper capabilities**: $MISSING_OPTIONAL"
        echo "This does not block the audit or restrict discovery/validation methods."
    fi
    if [ "$AUDIT_MODE" = "full" ]; then
        echo "All tracked bundled helper capabilities are available."
    fi
} >> "$OUT_MD"

echo "=== Preflight ==="
echo "cast=$CAST_STATUS forge=$FORGE_STATUS jq=$JQ_STATUS python3=$PY_STATUS etherscan_v2=$HAS_ETHERSCAN_V2"
echo "mode=$AUDIT_MODE"
echo "Output: $OUT_MD, $OUT_ENV"
exit 0
