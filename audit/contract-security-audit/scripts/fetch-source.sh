#!/usr/bin/env bash
set -euo pipefail

# Usage: fetch-source.sh <comma-separated-addresses> <chain> <output-dir>
# Fetches verified source code from block explorer APIs.
# Fallback: Sourcify decentralized verification (no API key needed).
# Fallback: GitHub clone if GITHUB_URL env var is set.

ADDRESSES="${1:?Usage: fetch-source.sh <addresses> <chain> <output-dir>}"
CHAIN="${2:?Missing chain argument}"
OUTPUT_DIR="${3:?Missing output directory}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# Load .env files (API keys, RPC URLs)
# Derive WORKSPACE from output-dir (parent of contracts/) so load-env.sh can load $WORKSPACE/.env
WORKSPACE="${WORKSPACE:-$(cd "$OUTPUT_DIR/.." && pwd)}"
export SKILL_DIR WORKSPACE
source "$(dirname "$0")/load-env.sh"

EXPLORER_MAX_TIME="${EXPLORER_MAX_TIME:-25}"
EXPLORER_RETRY_COUNT="${EXPLORER_RETRY_COUNT:-1}"
AUDIT_USER_AGENT="${AUDIT_USER_AGENT:-contract-security-audit-skill/1.0}"

curl_json() {
    local url="$1"
    local max_retries=3
    local attempt=0
    local backoff=1
    local response=""
    local http_code=""

    while [ "$attempt" -lt "$max_retries" ]; do
        response=$(curl \
            --silent \
            --show-error \
            --location \
            --connect-timeout 10 \
            --max-time "$EXPLORER_MAX_TIME" \
            --retry "$EXPLORER_RETRY_COUNT" \
            --retry-delay 1 \
            --retry-all-errors \
            -H "User-Agent: $AUDIT_USER_AGENT" \
            -w '\n%{http_code}' \
            "$url" 2>/dev/null) || { echo ""; return; }

        http_code="${response##*$'\n'}"
        response="${response%$'\n'*}"

        if [ "$http_code" = "429" ] || echo "$response" | grep -qi "rate limit" 2>/dev/null; then
            attempt=$((attempt + 1))
            if [ "$attempt" -lt "$max_retries" ]; then
                echo "Rate limited, backing off ${backoff}s (attempt $attempt/$max_retries)..." >&2
                sleep "$backoff"
                backoff=$((backoff * 2))
                continue
            fi
        fi
        break
    done
    echo "$response"
}

HAS_JQ=0
if command -v jq &>/dev/null; then
    HAS_JQ=1
fi

HAS_PYTHON=0
if command -v python3 &>/dev/null; then
    HAS_PYTHON=1
fi

if [ "$HAS_JQ" -eq 0 ] && [ "$HAS_PYTHON" -eq 0 ]; then
    echo "Error: fetch-source.sh requires either jq or python3 for JSON parsing." >&2
    exit 1
fi

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

lookup_chain_field() {
    local chain="$1"
    local field="$2"
    local config_file="$3"

    if [ "$HAS_JQ" -eq 1 ]; then
        jq -r --arg c "$chain" --arg f "$field" '
          ($c | ascii_downcase) as $lc
          | if .[$lc] then .[$lc][$f] // empty
            else
              ([to_entries[]
                | select((((.value.aliases // []) | map(ascii_downcase) | index($lc)) != null))
                | .value[$f]] | .[0] // empty)
            end
        ' "$config_file" 2>/dev/null
        return 0
    fi

    python3 - "$config_file" "$chain" "$field" <<'PY'
import json
import sys

config_file, chain, field = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
try:
    with open(config_file, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    print("")
    raise SystemExit(0)

if chain in cfg and isinstance(cfg[chain], dict):
    print(cfg[chain].get(field, ""))
    raise SystemExit(0)

for _, value in cfg.items():
    if not isinstance(value, dict):
        continue
    aliases = [str(a).lower() for a in value.get("aliases", [])]
    if chain in aliases:
        print(value.get(field, ""))
        raise SystemExit(0)

print("")
PY
}

get_explorer_config() {
    local chain
    chain="$(to_lower "$1")"
    local config_file="$SKILL_DIR/config/chains.json"

    if [ ! -f "$config_file" ]; then
        echo "Error: chains.json not found at $config_file. Cannot resolve chain '$chain'." >&2
        return 1
    fi

    local api_url key_env explorer_type
    api_url="$(lookup_chain_field "$chain" "explorer_api" "$config_file")"
    key_env="$(lookup_chain_field "$chain" "explorer_key_env" "$config_file")"
    explorer_type="$(lookup_chain_field "$chain" "explorer_type" "$config_file")"
    explorer_type="${explorer_type:-etherscan}"
    if [ -n "$api_url" ]; then
        echo "$api_url" "$key_env" "$explorer_type"
        return 0
    fi

    echo "Error: Chain '$chain' not found in chains.json. Check config/chains.json for supported chains and aliases." >&2
    return 1
}

fetch_blockscout_contract() {
    local addr="$1"
    local api_url="$2"
    local out_dir="$3"

    local url="${api_url%/}/api/v2/smart-contracts/${addr}"
    local response
    response="$(curl_json "$url")"

    if [ -z "$response" ]; then
        echo "  $addr ... EMPTY RESPONSE (blockscout)"
        return 1
    fi

    local contract_name source_code is_verified
    if [ "$HAS_JQ" -eq 1 ]; then
        is_verified=$(echo "$response" | jq -r '.is_verified // false' 2>/dev/null)
        contract_name=$(echo "$response" | jq -r '.name // "Unknown"' 2>/dev/null)
    elif [ "$HAS_PYTHON" -eq 1 ]; then
        is_verified=$(printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(str(d.get("is_verified",False)).lower())')
        contract_name=$(printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("name","Unknown"))')
    fi

    if [ "$is_verified" != "true" ]; then
        echo "  $addr ... UNVERIFIED (blockscout)"
        echo "$addr: UNVERIFIED" >> "$out_dir/../verification-status.txt"
        return 1
    fi

    contract_name="$(safe_filename "$contract_name")"
    [ -z "$contract_name" ] && contract_name="Unknown"

    echo "  $addr ... $contract_name OK (blockscout)"
    echo "$addr: VERIFIED ($contract_name)" >> "$out_dir/../verification-status.txt"

    local addr_namespace
    addr_namespace="$(echo "$addr" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    [ -z "$addr_namespace" ] && addr_namespace="addr_unknown"
    mkdir -p "$out_dir/$addr_namespace"

    if [ "$HAS_JQ" -eq 1 ]; then
        local has_sources
        has_sources=$(echo "$response" | jq -e '.additional_sources | length > 0' >/dev/null 2>&1 && echo "yes" || echo "no")
        if [ "$has_sources" = "yes" ]; then
            echo "$response" | jq -r '.source_code // ""' 2>/dev/null > "$out_dir/$addr_namespace/${contract_name}.sol"
            echo "$response" | jq -c '.additional_sources[]?' 2>/dev/null | while IFS= read -r source_item; do
                fpath="$(printf '%s' "$source_item" | jq -r '.file_path // ""' 2>/dev/null)"
                [ -z "$fpath" ] && continue
                if ! is_safe_relative_path "$fpath"; then
                    echo "Warning: skipping unsafe Blockscout source path '$fpath'" >&2
                    continue
                fi
                src="$(printf '%s' "$source_item" | jq -r '.source_code // ""' 2>/dev/null)"
                mkdir -p "$out_dir/$addr_namespace/$(dirname "$fpath")" 2>/dev/null || true
                printf '%s\n' "$src" > "$out_dir/$addr_namespace/$fpath"
                echo "  Saved: $fpath"
            done
        else
            source_code=$(echo "$response" | jq -r '.source_code // ""' 2>/dev/null)
            echo "$source_code" > "$out_dir/$addr_namespace/${contract_name}.sol"
            echo "  Saved: $addr_namespace/${contract_name}.sol"
        fi
    else
        printf '%s' "$response" | python3 -c '
import json
import pathlib
import sys

base = pathlib.Path(sys.argv[1])
contract_name = sys.argv[2]
data = json.load(sys.stdin)

def safe_relative(value):
    if not isinstance(value, str) or not value or value.startswith("/"):
        return False
    parts = value.split("/")
    return all(part not in ("", ".", "..") for part in parts)

base.mkdir(parents=True, exist_ok=True)
(base / (contract_name + ".sol")).write_text(
    str(data.get("source_code", "")), encoding="utf-8"
)
print("  Saved: " + base.name + "/" + contract_name + ".sol")

for item in data.get("additional_sources") or []:
    if not isinstance(item, dict):
        continue
    rel = item.get("file_path", "")
    if not safe_relative(rel):
        print("Warning: skipping unsafe Blockscout source path " + repr(rel), file=sys.stderr)
        continue
    destination = base.joinpath(*rel.split("/"))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(str(item.get("source_code", "")), encoding="utf-8")
    print("  Saved: " + rel)
' "$out_dir/$addr_namespace" "$contract_name"
    fi
}

get_etherscan_v2_config() {
    local chain="$1"
    local config_file="$SKILL_DIR/config/chains.json"
    local chain_id=""

    if [ -f "$config_file" ]; then
        chain_id="$(lookup_chain_field "$chain" "chain_id" "$config_file")"
    fi

    if [ -z "$chain_id" ] || [ "$chain_id" = "0" ] || [ "$chain_id" = "null" ]; then
        return 1
    fi

    local v2_key="${ETHERSCAN_API_KEY:-}"
    if [ -z "$v2_key" ]; then
        return 1
    fi

    echo "https://api.etherscan.io/v2/api?chainid=${chain_id}" "$v2_key"
    return 0
}

response_field() {
    local response="$1"
    local field="$2"

    if [ "$HAS_JQ" -eq 1 ]; then
        case "$field" in
            status)
                echo "$response" | jq -r '.status // "0"' 2>/dev/null
                ;;
            message)
                echo "$response" | jq -r '.message // "Unknown error"' 2>/dev/null
                ;;
            contract_name)
                echo "$response" | jq -r '.result[0].ContractName // "Unknown"' 2>/dev/null
                ;;
            source_code)
                echo "$response" | jq -r '.result[0].SourceCode // ""' 2>/dev/null
                ;;
            *)
                echo ""
                ;;
        esac
        return 0
    fi

    printf '%s' "$response" | python3 -c '
import json
import sys

DEFAULTS = {"status": "0", "message": "Unknown error", "contract_name": "Unknown", "source_code": ""}
field = sys.argv[1]
raw = sys.stdin.read().strip()

if not raw:
    print(DEFAULTS.get(field, ""))
    raise SystemExit(0)

try:
    data = json.loads(raw)
except (json.JSONDecodeError, ValueError) as e:
    print(DEFAULTS.get(field, ""), end="")
    print(f"JSON parse error for field {field}: {e}", file=sys.stderr)
    raise SystemExit(0)

if not isinstance(data, dict):
    print(DEFAULTS.get(field, ""))
    raise SystemExit(0)

result = data.get("result")

if field == "status":
    print(str(data.get("status", "0")))
    raise SystemExit(0)

if field == "message":
    msg = data.get("message")
    if msg:
        print(msg)
    elif isinstance(result, str):
        print(result)
    else:
        print("Unknown error")
    raise SystemExit(0)

if not isinstance(result, list) or not result or not isinstance(result[0], dict):
    print(DEFAULTS.get(field, ""))
    raise SystemExit(0)

entry = result[0]
if field == "contract_name":
    print(entry.get("ContractName", "Unknown"))
elif field == "source_code":
    print(entry.get("SourceCode", ""))
else:
    print("")
' "$field"
}

is_multifile_source() {
    local source_code="$1"

    if [ "$HAS_JQ" -eq 1 ]; then
        echo "$source_code" | jq -e '.sources and (.sources | type == "object")' >/dev/null 2>&1
        return $?
    fi

    printf '%s' "$source_code" | python3 -c '
import json
import sys

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(1)

sources = data.get("sources")
raise SystemExit(0 if isinstance(sources, dict) else 1)
'
}

save_multifile_source() {
    local source_code="$1"
    local out_dir="$2"
    mkdir -p "$out_dir"

    if [ "$HAS_JQ" -eq 1 ]; then
        while IFS= read -r filename; do
            [ -z "$filename" ] && continue
            if ! is_safe_relative_path "$filename"; then
                echo "Warning: skipping unsafe source path '$filename'" >&2
                continue
            fi
            local content
            content=$(echo "$source_code" | jq -r --arg f "$filename" '.sources[$f].content // empty')
            if [ -n "$content" ]; then
                mkdir -p "$out_dir/$(dirname "$filename")" 2>/dev/null || true
                echo "$content" > "$out_dir/$filename"
                echo "  Saved: $filename"
            fi
        done < <(echo "$source_code" | jq -r '.sources // {} | to_entries[] | .key' 2>/dev/null)
        return 0
    fi

    printf '%s' "$source_code" | python3 -c '
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1]).resolve()
raw = sys.stdin.read()
data = json.loads(raw)
sources = data.get("sources", {})
written = 0

for filename, meta in sources.items():
    content = ""
    if isinstance(meta, dict):
        content = meta.get("content", "")
    elif isinstance(meta, str):
        content = meta
    if not content:
        continue

    rel_path = Path(filename)
    if rel_path.is_absolute() or any(part in ("", ".", "..") for part in rel_path.parts):
        print(f"Warning: skipping unsafe source path '{filename}'", file=sys.stderr)
        continue

    full_path = (out_dir / rel_path).resolve()
    try:
        full_path.relative_to(out_dir)
    except ValueError:
        print(f"Warning: skipping escaping path '{filename}'", file=sys.stderr)
        continue

    full_path.parent.mkdir(parents=True, exist_ok=True)
    with open(full_path, "w", encoding="utf-8") as fh:
        fh.write(content)
    print(f"  Saved: {filename}")
    written += 1

if written == 0:
    raise SystemExit(1)
' "$out_dir"
}

safe_filename() {
    local name="$1"
    echo "$name" | tr -cs 'A-Za-z0-9._-' '_'
}

redact_url_credentials() {
    local url="$1"
    if [[ "$url" == *"://"* ]]; then
        local proto rest
        proto="${url%%://*}"
        rest="${url#*://}"
        rest="${rest##*@}"
        echo "${proto}://${rest}"
    else
        echo "$url"
    fi
}

is_safe_relative_path() {
    local rel="$1"
    [ -z "$rel" ] && return 1
    case "$rel" in
        /*) return 1 ;;
    esac
    IFS='/' read -ra parts <<< "$rel"
    for p in "${parts[@]}"; do
        if [ "$p" = "." ] || [ "$p" = ".." ]; then
            return 1
        fi
    done
    return 0
}

fetch_single_contract() {
    local addr="$1"
    local api_url="$2"
    local api_key="$3"
    local out_dir="$4"

    local sep="?"
    [[ "$api_url" == *"?"* ]] && sep="&"
    local url="${api_url}${sep}module=contract&action=getsourcecode&address=${addr}"
    if [ -n "$api_key" ]; then
        url="${url}&apikey=${api_key}"
    fi

    local response
    response="$(curl_json "$url")"

    if [ -z "$response" ]; then
        echo "  $addr ... EMPTY RESPONSE"
        return 1
    fi

    local status
    status=$(response_field "$response" "status")
    if [ "$status" != "1" ]; then
        local msg
        msg=$(response_field "$response" "message")
        echo "  $addr ... FAILED ($msg)"
        return 1
    fi

    local contract_name source_code
    contract_name=$(response_field "$response" "contract_name")
    source_code=$(response_field "$response" "source_code")

    if [ -z "$source_code" ] || [ "$source_code" = "" ]; then
        echo "  $addr ... UNVERIFIED"
        echo "$addr: UNVERIFIED" >> "$out_dir/../verification-status.txt"
        return 1
    fi

    echo "  $addr ... $contract_name OK"
    echo "$addr: VERIFIED ($contract_name)" >> "$out_dir/../verification-status.txt"

    local addr_namespace
    addr_namespace="$(echo "$addr" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    [ -z "$addr_namespace" ] && addr_namespace="addr_unknown"

    # Handle multi-file source (JSON format starting with {{ or {)
    if [[ "$source_code" == "{{"* ]]; then
        source_code="${source_code#\{}"
        source_code="${source_code%\}}"
    fi

    if is_multifile_source "$source_code"; then
        save_multifile_source "$source_code" "$out_dir/$addr_namespace"
    else
        local filename
        filename="$(safe_filename "${contract_name}_${addr_namespace}.sol")"
        mkdir -p "$out_dir/$addr_namespace"
        echo "$source_code" > "$out_dir/$addr_namespace/$filename"
        echo "  Saved: $addr_namespace/$filename"
    fi
}

fetch_sourcify_contract() {
    local addr="$1"
    local chain_id="$2"
    local out_dir="$3"

    local url="https://sourcify.dev/server/v2/contract/${chain_id}/${addr}?fields=all"
    local response
    response=$(curl \
        --silent \
        --show-error \
        --location \
        --connect-timeout 10 \
        --max-time "$EXPLORER_MAX_TIME" \
        --retry "$EXPLORER_RETRY_COUNT" \
        --retry-delay 1 \
        --retry-all-errors \
        -H "User-Agent: $AUDIT_USER_AGENT" \
        -w '\n%{http_code}' \
        "$url" 2>/dev/null) || { echo "  $addr ... SOURCIFY CONNECTION FAILED"; return 1; }

    local http_code="${response##*$'\n'}"
    response="${response%$'\n'*}"

    if [ "$http_code" != "200" ]; then
        echo "  $addr ... SOURCIFY NOT FOUND (HTTP $http_code)"
        return 1
    fi

    if [ -z "$response" ]; then
        echo "  $addr ... SOURCIFY EMPTY RESPONSE"
        return 1
    fi

    local addr_namespace
    addr_namespace="$(echo "$addr" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    [ -z "$addr_namespace" ] && addr_namespace="addr_unknown"
    mkdir -p "$out_dir/$addr_namespace"

    # Parse Sourcify response and save .sol/.vy files
    # Sourcify v2 returns:
    # { "match": "full"|"partial"|null, "sources": { "contracts/X.sol": { "content": "..." }, ... }, ... }
    if [ "$HAS_PYTHON" -eq 1 ]; then
        printf '%s' "$response" | python3 -c '
import json, sys
from pathlib import Path

out_dir = Path(sys.argv[1]).resolve()
addr_ns = sys.argv[2]
data = json.loads(sys.stdin.read())
sources = data.get("sources") or {}
written = 0
for rel, meta in sources.items():
    if not (rel.endswith(".sol") or rel.endswith(".vy")):
        continue
    content = (meta or {}).get("content") or ""
    if not content:
        continue
    rel_path = Path(rel)
    if rel_path.is_absolute() or any(p in ("", ".", "..") for p in rel_path.parts):
        print("Warning: skipping unsafe Sourcify path " + rel, file=sys.stderr)
        continue
    dest = (out_dir / addr_ns / rel_path).resolve()
    try:
        dest.relative_to(out_dir / addr_ns)
    except ValueError:
        continue
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content, encoding="utf-8")
    print("  Saved (sourcify): " + rel)
    written += 1
if written == 0:
    raise SystemExit(1)
print("  " + sys.argv[3] + " ... OK (sourcify, " + str(written) + " files)")
' "$out_dir" "$addr_namespace" "$addr" || {
            echo "  $addr ... SOURCIFY NO .sol/.vy FILES"
            return 1
        }
    elif [ "$HAS_JQ" -eq 1 ]; then
        local file_count=0
        local sourcify_files
        sourcify_files=$(echo "$response" | jq -r '
            .sources // {}
            | to_entries[]
            | select(.key | test("\\.(sol|vy)$"))
            | .key
        ' 2>/dev/null)

        while IFS= read -r rel_path; do
            [ -z "$rel_path" ] && continue
            if ! is_safe_relative_path "$rel_path"; then
                echo "Warning: skipping unsafe Sourcify path '$rel_path'" >&2
                continue
            fi
            local content
            content=$(echo "$response" | jq -r --arg rp "$rel_path" '
                .sources[$rp].content // ""
            ' 2>/dev/null)
            [ -z "$content" ] && continue
            mkdir -p "$out_dir/$addr_namespace/$(dirname "$rel_path")" 2>/dev/null || true
            printf '%s' "$content" > "$out_dir/$addr_namespace/$rel_path"
            echo "  Saved (sourcify): $rel_path"
            file_count=$((file_count + 1))
        done <<< "$sourcify_files"

        if [ "$file_count" -eq 0 ]; then
            echo "  $addr ... SOURCIFY NO .sol/.vy FILES"
            return 1
        fi
        echo "  $addr ... OK (sourcify, $file_count files)"
    fi

    echo "$addr: VERIFIED via Sourcify" >> "$out_dir/../verification-status.txt"
    return 0
}

CHAIN_NORMALIZED="$(to_lower "$CHAIN")"

# --- Etherscan V2 API (preferred: single key, all chains) ---
V2_API_URL=""
V2_API_KEY=""
if read -r V2_API_URL V2_API_KEY < <(get_etherscan_v2_config "$CHAIN_NORMALIZED" 2>/dev/null); then
    [ -z "$V2_API_URL" ] && V2_API_URL="" && V2_API_KEY=""
fi

# --- Chain-specific explorer API (fallback) ---
read -r CHAIN_API_URL KEY_ENV EXPLORER_TYPE < <(get_explorer_config "$CHAIN_NORMALIZED")
EXPLORER_TYPE="${EXPLORER_TYPE:-etherscan}"
CHAIN_API_KEY=""
if [ -n "${KEY_ENV:-}" ] && [ -n "${!KEY_ENV:-}" ]; then
    CHAIN_API_KEY="${!KEY_ENV}"
fi

# --- Resolve chain_id for Sourcify fallback ---
CHAIN_ID=""
config_file="$SKILL_DIR/config/chains.json"
if [ -f "$config_file" ]; then
    CHAIN_ID="$(lookup_chain_field "$CHAIN_NORMALIZED" "chain_id" "$config_file")"
fi
if [ -z "$CHAIN_ID" ] || [ "$CHAIN_ID" = "0" ] || [ "$CHAIN_ID" = "null" ]; then
    CHAIN_ID=""
fi

# Determine primary and fallback API
if [ -n "$V2_API_URL" ] && [ -n "$V2_API_KEY" ] && [ "$EXPLORER_TYPE" = "etherscan" ]; then
    API_URL="$V2_API_URL"
    API_KEY="$V2_API_KEY"
    FALLBACK_API_URL="$CHAIN_API_URL"
    FALLBACK_API_KEY="$CHAIN_API_KEY"
    echo "API: Etherscan V2 (fallback: chain-specific, Sourcify)"
else
    API_URL="$CHAIN_API_URL"
    API_KEY="$CHAIN_API_KEY"
    FALLBACK_API_URL=""
    FALLBACK_API_KEY=""
    if [ "$EXPLORER_TYPE" = "blockscout" ]; then
        echo "API: Blockscout (fallback: Sourcify)"
    elif [ -z "$API_KEY" ]; then
        echo "WARNING: No API key. Set ETHERSCAN_API_KEY or ${KEY_ENV:-chain-specific key}. (Sourcify available as fallback)"
    else
        echo "API: chain-specific explorer (fallback: Sourcify)"
    fi
fi

source "$(dirname "$0")/retention.sh"

# Fetch into a fresh retained run directory. Existing contracts and status remain
# untouched unless this run produces source successfully and is promoted below.
FINAL_OUTPUT_DIR="$OUTPUT_DIR"
FINAL_PARENT_DIR="$(cd "$(dirname "$FINAL_OUTPUT_DIR")" && pwd -P)"
FINAL_STATUS_FILE="$FINAL_PARENT_DIR/verification-status.txt"
LEGACY_GITHUB_DIR="$FINAL_PARENT_DIR/github-source"
if ! FETCH_RUN_DIR="$(audit_create_retained_run_dir "$WORKSPACE" "fetch-source" "run")"; then
    echo "ERROR: cannot create a safe retained fetch run directory" >&2
    exit 1
fi
OUTPUT_DIR="$FETCH_RUN_DIR/contracts"
mkdir -p "$OUTPUT_DIR"
> "$FETCH_RUN_DIR/verification-status.txt"

validate_address() {
    [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "WARNING: Invalid address format, skipping: $1" >&2; return 1; }
}

FETCH_FAILED=0
if [ -n "${GITHUB_URL:-}" ] && [ -n "${GITHUB_REF:-}" ]; then
    echo "Exact GITHUB_REF supplied; acquiring the pinned repository revision before any explorer fallback."
else
    IFS=',' read -ra ADDR_ARRAY <<< "$ADDRESSES"
    for addr in "${ADDR_ARRAY[@]}"; do
        addr=$(echo "$addr" | tr -d '[:space:]')
        if [ -n "$addr" ] && validate_address "$addr"; then
            addr_ok=0
            if [ "$EXPLORER_TYPE" = "blockscout" ]; then
                fetch_blockscout_contract "$addr" "$API_URL" "$OUTPUT_DIR" && addr_ok=1
            else
                if fetch_single_contract "$addr" "$API_URL" "$API_KEY" "$OUTPUT_DIR"; then
                    addr_ok=1
                elif [ -n "$FALLBACK_API_URL" ]; then
                    echo "  Retrying $addr with chain-specific explorer API..."
                    fetch_single_contract "$addr" "$FALLBACK_API_URL" "$FALLBACK_API_KEY" "$OUTPUT_DIR" && addr_ok=1
                fi
            fi
            # Sourcify fallback (no API key needed)
            if [ "$addr_ok" -eq 0 ] && [ -n "$CHAIN_ID" ]; then
                echo "  Retrying $addr with Sourcify..."
                fetch_sourcify_contract "$addr" "$CHAIN_ID" "$OUTPUT_DIR" && addr_ok=1
            fi
            if [ "$addr_ok" -eq 0 ]; then
                FETCH_FAILED=$((FETCH_FAILED + 1))
            fi
            sleep 0.5  # rate limit courtesy
        fi
    done
fi

SOL_COUNT=$(find "$OUTPUT_DIR" -name "*.sol" 2>/dev/null | wc -l | tr -d '[:space:]')
VY_COUNT=$(find "$OUTPUT_DIR" -name "*.vy" 2>/dev/null | wc -l | tr -d '[:space:]')
FILE_COUNT=$((SOL_COUNT + VY_COUNT))

echo ""
echo "=== Fetch Summary ==="
echo "Source files: $FILE_COUNT ($SOL_COUNT .sol, $VY_COUNT .vy)"
echo "Failed addresses: $FETCH_FAILED"

if [ "$FILE_COUNT" -eq 0 ] && [ -n "${GITHUB_URL:-}" ]; then
    # Validate GITHUB_URL is an HTTPS URL to prevent local path or SSH injection
    GITHUB_SOURCE_DIR="$FETCH_RUN_DIR/github-source"
    GITHUB_FETCH_OK=0
    GITHUB_RESOLVED_REF=""
    if [[ "$GITHUB_URL" != https://* ]]; then
        echo "ERROR: GITHUB_URL must be an HTTPS URL (got: $(redact_url_credentials "$GITHUB_URL"))" >&2
    elif ! command -v git >/dev/null 2>&1; then
        echo "ERROR: git is required for GITHUB_URL fallback." >&2
    elif [ -n "${GITHUB_REF:-}" ]; then
        if ! printf '%s\n' "$GITHUB_REF" | grep -Eq '^[0-9a-fA-F]{40}$'; then
            echo "ERROR: GITHUB_REF must be a full 40-hex commit SHA for an auditable source snapshot." >&2
        elif git init -q "$GITHUB_SOURCE_DIR" 2>/dev/null && \
             git -C "$GITHUB_SOURCE_DIR" remote add origin "$GITHUB_URL" 2>/dev/null && \
             git -C "$GITHUB_SOURCE_DIR" fetch -q --depth 1 origin "$GITHUB_REF" 2>/dev/null && \
             git -C "$GITHUB_SOURCE_DIR" checkout -q --detach FETCH_HEAD 2>/dev/null; then
            GITHUB_RESOLVED_REF="$(git -C "$GITHUB_SOURCE_DIR" rev-parse HEAD 2>/dev/null || true)"
            if [ "$(printf '%s' "$GITHUB_RESOLVED_REF" | tr '[:upper:]' '[:lower:]')" = \
                 "$(printf '%s' "$GITHUB_REF" | tr '[:upper:]' '[:lower:]')" ]; then
                GITHUB_FETCH_OK=1
            else
                echo "ERROR: fetched GitHub revision does not match GITHUB_REF." >&2
            fi
        else
            echo "ERROR: failed to fetch exact GITHUB_REF from $(redact_url_credentials "$GITHUB_URL")." >&2
        fi
    elif git clone -q --depth 1 -- "$GITHUB_URL" "$GITHUB_SOURCE_DIR" 2>/dev/null; then
        GITHUB_RESOLVED_REF="$(git -C "$GITHUB_SOURCE_DIR" rev-parse HEAD 2>/dev/null || true)"
        if printf '%s\n' "$GITHUB_RESOLVED_REF" | grep -Eq '^[0-9a-fA-F]{40}$'; then
            GITHUB_FETCH_OK=1
        else
            echo "ERROR: GitHub checkout did not resolve to a full commit SHA." >&2
        fi
    else
        echo "GitHub clone failed." >&2
    fi

    if [ "$GITHUB_FETCH_OK" -eq 1 ]; then
        {
            echo "repository=$(redact_url_credentials "$GITHUB_URL")"
            echo "requested_ref=${GITHUB_REF:-HEAD at acquisition time}"
            echo "resolved_commit=$GITHUB_RESOLVED_REF"
            echo "deployment_association=NOT ASSESSED - repository source is not deployment verification"
        } > "$FETCH_RUN_DIR/github-revision.txt"
        echo "GitHub source: ACQUIRED revision $GITHUB_RESOLVED_REF (deployment association NOT ASSESSED)" \
            >> "$FETCH_RUN_DIR/verification-status.txt"
        if [ -d "$GITHUB_SOURCE_DIR/contracts" ]; then
            cp -R "$GITHUB_SOURCE_DIR/contracts/." "$OUTPUT_DIR/"
        elif [ -d "$GITHUB_SOURCE_DIR/src" ]; then
            cp -R "$GITHUB_SOURCE_DIR/src/." "$OUTPUT_DIR/"
        else
            echo "ERROR: GitHub repository has neither contracts/ nor src/." >&2
        fi
    fi
    SOL_COUNT=$(find "$OUTPUT_DIR" -name "*.sol" 2>/dev/null | wc -l | tr -d '[:space:]')
    VY_COUNT=$(find "$OUTPUT_DIR" -name "*.vy" 2>/dev/null | wc -l | tr -d '[:space:]')
    FILE_COUNT=$((SOL_COUNT + VY_COUNT))
    echo "After GitHub fallback: $FILE_COUNT files ($SOL_COUNT .sol, $VY_COUNT .vy)"
fi

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "ERROR: No source code retrieved."
    echo "ACTION: Provide a GitHub URL and optional full GITHUB_REF, or place source files in $FINAL_OUTPUT_DIR/. Failed-run data remains at $FETCH_RUN_DIR/." >&2
    exit 1
fi

if [ -n "$(find "$OUTPUT_DIR" -type l -print -quit 2>/dev/null)" ]; then
    echo "ERROR: fetched source contains symlinks; refusing promotion into the canonical contracts directory." >&2
    echo "Inspect the retained run at $FETCH_RUN_DIR and materialize required files explicitly." >&2
    exit 1
fi

# Only a successful fresh run may replace the canonical current source. Archive
# all prior current artifacts first and fail closed if the snapshot cannot be made.
audit_archive_existing "$WORKSPACE" "fetch-source" \
    "$FINAL_OUTPUT_DIR" \
    "$FINAL_STATUS_FILE" \
    "$LEGACY_GITHUB_DIR" || {
    echo "ERROR: refusing to replace source output without retaining the prior version" >&2
    exit 1
}

# Stage copies beside the canonical outputs so the retained fresh run remains
# complete and each promotion rename stays on the workspace filesystem. Move the
# prior source/status aside as one rollback generation; if either new rename
# fails, the EXIT guard restores the entire previous generation.
PROMOTION_SUFFIX=0
while :; do
    PROMOTION_TOKEN="$$"
    if [ "$PROMOTION_SUFFIX" -gt 0 ]; then
        PROMOTION_TOKEN="$$-$PROMOTION_SUFFIX"
    fi
    STAGED_OUTPUT_DIR="$FINAL_OUTPUT_DIR.promote-$PROMOTION_TOKEN-new"
    NEW_STATUS_FILE="$FINAL_STATUS_FILE.promote-$PROMOTION_TOKEN-new"
    OLD_OUTPUT_DIR="$FINAL_OUTPUT_DIR.promote-$PROMOTION_TOKEN-old"
    OLD_STATUS_FILE="$FINAL_STATUS_FILE.promote-$PROMOTION_TOKEN-old"
    OLD_LEGACY_GITHUB_DIR="$LEGACY_GITHUB_DIR.promote-$PROMOTION_TOKEN-old"
    if [ ! -e "$STAGED_OUTPUT_DIR" ] && [ ! -L "$STAGED_OUTPUT_DIR" ] && \
       [ ! -e "$NEW_STATUS_FILE" ] && [ ! -L "$NEW_STATUS_FILE" ] && \
       [ ! -e "$OLD_OUTPUT_DIR" ] && [ ! -L "$OLD_OUTPUT_DIR" ] && \
       [ ! -e "$OLD_STATUS_FILE" ] && [ ! -L "$OLD_STATUS_FILE" ] && \
       [ ! -e "$OLD_LEGACY_GITHUB_DIR" ] && [ ! -L "$OLD_LEGACY_GITHUB_DIR" ]; then
        break
    fi
    PROMOTION_SUFFIX=$((PROMOTION_SUFFIX + 1))
done

OLD_OUTPUT_MOVED=0
OLD_STATUS_MOVED=0
OLD_LEGACY_MOVED=0
NEW_OUTPUT_PROMOTED=0
NEW_STATUS_PROMOTED=0
PROMOTION_ACTIVE=1

restore_fetch_generation() {
    restore_failed=0
    PROMOTION_ACTIVE=0

    if [ "$NEW_STATUS_PROMOTED" -eq 1 ]; then
        rm -f "$FINAL_STATUS_FILE" || restore_failed=1
    fi
    if [ "$NEW_OUTPUT_PROMOTED" -eq 1 ]; then
        rm -rf "$FINAL_OUTPUT_DIR" || restore_failed=1
    fi
    if [ "$OLD_OUTPUT_MOVED" -eq 1 ]; then
        if ! mv "$OLD_OUTPUT_DIR" "$FINAL_OUTPUT_DIR"; then
            echo "ERROR: failed to restore prior canonical source from $OLD_OUTPUT_DIR" >&2
            restore_failed=1
        fi
    fi
    if [ "$OLD_STATUS_MOVED" -eq 1 ]; then
        if ! mv "$OLD_STATUS_FILE" "$FINAL_STATUS_FILE"; then
            echo "ERROR: failed to restore prior verification status from $OLD_STATUS_FILE" >&2
            restore_failed=1
        fi
    fi
    if [ "$OLD_LEGACY_MOVED" -eq 1 ]; then
        if ! mv "$OLD_LEGACY_GITHUB_DIR" "$LEGACY_GITHUB_DIR"; then
            echo "ERROR: failed to restore prior legacy GitHub source from $OLD_LEGACY_GITHUB_DIR" >&2
            restore_failed=1
        fi
    fi

    rm -rf "$STAGED_OUTPUT_DIR"
    rm -f "$NEW_STATUS_FILE"
    return "$restore_failed"
}

fetch_promotion_exit_guard() {
    promotion_status=$?
    if [ "$PROMOTION_ACTIVE" -eq 1 ]; then
        echo "ERROR: source promotion did not commit; restoring the prior current generation" >&2
        restore_fetch_generation || \
            echo "ERROR: automatic rollback was incomplete; retained rollback paths are reported above" >&2
    fi
    return "$promotion_status"
}

trap fetch_promotion_exit_guard EXIT
trap 'exit 1' HUP INT TERM

if ! cp -pR "$OUTPUT_DIR" "$STAGED_OUTPUT_DIR"; then
    echo "ERROR: cannot stage fresh source; current source remains unchanged" >&2
    exit 1
fi
if ! cp -p "$FETCH_RUN_DIR/verification-status.txt" "$NEW_STATUS_FILE"; then
    echo "ERROR: cannot stage fresh verification status; current source remains unchanged" >&2
    exit 1
fi

if [ -e "$FINAL_OUTPUT_DIR" ] || [ -L "$FINAL_OUTPUT_DIR" ]; then
    if ! mv "$FINAL_OUTPUT_DIR" "$OLD_OUTPUT_DIR"; then
        echo "ERROR: cannot prepare prior source for transactional promotion" >&2
        exit 1
    fi
    OLD_OUTPUT_MOVED=1
fi
if [ -e "$FINAL_STATUS_FILE" ] || [ -L "$FINAL_STATUS_FILE" ]; then
    if ! mv "$FINAL_STATUS_FILE" "$OLD_STATUS_FILE"; then
        echo "ERROR: cannot prepare prior verification status for transactional promotion" >&2
        exit 1
    fi
    OLD_STATUS_MOVED=1
fi
if [ -e "$LEGACY_GITHUB_DIR" ] || [ -L "$LEGACY_GITHUB_DIR" ]; then
    if ! mv "$LEGACY_GITHUB_DIR" "$OLD_LEGACY_GITHUB_DIR"; then
        echo "ERROR: cannot prepare prior legacy GitHub source for transactional promotion" >&2
        exit 1
    fi
    OLD_LEGACY_MOVED=1
fi

if ! mv "$STAGED_OUTPUT_DIR" "$FINAL_OUTPUT_DIR"; then
    echo "ERROR: failed to promote fresh source; retained run remains at $FETCH_RUN_DIR" >&2
    exit 1
fi
NEW_OUTPUT_PROMOTED=1
if ! mv "$NEW_STATUS_FILE" "$FINAL_STATUS_FILE"; then
    echo "ERROR: verification-status promotion failed; rolling back source and status together" >&2
    exit 1
fi
NEW_STATUS_PROMOTED=1

PROMOTION_ACTIVE=0
trap - EXIT HUP INT TERM

# The previous generation is already preserved in the complete retention
# snapshot. Remove only these same-filesystem rollback names after both new
# artifacts have committed.
rm -rf "$OLD_OUTPUT_DIR" "$OLD_LEGACY_GITHUB_DIR"
rm -f "$OLD_STATUS_FILE"

{
    echo "promoted_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "canonical_source=$FINAL_OUTPUT_DIR"
    echo "verification_status=$FINAL_STATUS_FILE"
    echo "source_files=$FILE_COUNT"
    echo "solidity_files=$SOL_COUNT"
    echo "vyper_files=$VY_COUNT"
    if [ -n "${GITHUB_RESOLVED_REF:-}" ]; then
        echo "github_resolved_commit=$GITHUB_RESOLVED_REF"
    fi
} > "$FETCH_RUN_DIR/promotion-manifest.txt"

OUTPUT_DIR="$FINAL_OUTPUT_DIR"
echo "Promoted fresh source to: $OUTPUT_DIR"

exit 0
