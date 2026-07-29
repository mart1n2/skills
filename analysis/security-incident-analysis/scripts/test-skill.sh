#!/usr/bin/env bash
# Portable regression suite for security-incident-analysis (Apple Bash 3.2 / Linux Bash).
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/incident-analysis-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN" "$TMP_ROOT/home"

while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find "$SKILL_DIR/scripts" -type f -name '*.sh' -print0)
jq empty "$SKILL_DIR/config/chains.json"

python3 - "$SKILL_DIR/SKILL.md" <<'PY'
import re
import sys

content = open(sys.argv[1], "r", encoding="utf-8").read()
match = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
if not match:
    raise SystemExit("invalid SKILL.md frontmatter")
frontmatter = match.group(1)
name = re.search(r"^name:\s*(.+)$", frontmatter, re.MULTILINE)
if not name or not re.fullmatch(r"[a-z0-9-]{1,64}", name.group(1).strip()):
    raise SystemExit("invalid skill name")
description = re.search(r"^description:\s*>\n((?:[ \t]+.*\n?)+)", frontmatter, re.MULTILINE)
if not description:
    raise SystemExit("missing folded description")
text = " ".join(line.strip() for line in description.group(1).splitlines())
if not text or len(text) > 1024 or "<" in text or ">" in text:
    raise SystemExit("invalid skill description")
PY

cat > "$MOCK_BIN/cast" <<'MOCK'
#!/usr/bin/env bash
set -u

cmd="${1:-}"; shift || true
first="${1:-}"
rpc=""; block=""
args="$*"
set -- $args
while [ "$#" -gt 0 ]; do
  case "$1" in
    --rpc-url) rpc="${2:-}"; shift 2 ;;
    --block) block="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

case "$cmd" in
  chain-id)
    case "$rpc" in
      *wrong.invalid*) echo 10 ;;
      *mainnet.optimism.io*) echo 10 ;;
      *archive.invalid*|*pruned.invalid*) echo 1 ;;
      *) exit 1 ;;
    esac
    ;;
  balance)
    case "$rpc" in *archive.invalid*|*mainnet.optimism.io*) echo 0 ;; *) exit 1 ;; esac
    ;;
  block-number)
    case "$rpc" in *archive.invalid*) echo 2000000 ;; *) exit 1 ;; esac
    ;;
  to-dec)
    value="${first:-0}"
    printf '%d\n' "$((value))"
    ;;
  to-hex)
    value="${first:-0}"
    printf '0x%x\n' "$value"
    ;;
  tx)
    tx="$first"
    case "$rpc" in *archive.invalid*) ;; *) exit 1 ;; esac
    printf '{"hash":"%s","blockNumber":"0x64","from":"0x1111111111111111111111111111111111111111","to":"0x2222222222222222222222222222222222222222"}\n' "$tx"
    ;;
  receipt)
    tx="$first"
    case "$rpc" in *archive.invalid*) ;; *) exit 1 ;; esac
    printf '{"transactionHash":"%s","status":"0x1","logs":[]}\n' "$tx"
    ;;
  block)
    case "$rpc" in *archive.invalid*) ;; *) exit 1 ;; esac
    printf '{"number":"0x64","hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","timestamp":"0x5f5e100"}\n'
    ;;
  call)
    case "$rpc" in *archive.invalid*) ;; *) exit 1 ;; esac
    case "$block" in
      100|101|102|103|104|200) echo 1000 ;;
      105|106|107|108|109|110) echo 0 ;;
      201) echo 400 ;;
      *) exit 1 ;;
    esac
    ;;
  rpc)
    case "$rpc" in *archive.invalid*) ;; *) exit 1 ;; esac
    amount="$(printf '0x%064x' 600)"
    printf '[{"data":"%s"}]\n' "$amount"
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$MOCK_BIN/cast"

cat > "$TMP_ROOT/chains.json" <<'JSON'
[
  {
    "name": "Ethereum Mainnet",
    "chainId": 1,
    "rpc": [
      "wss://skip.invalid",
      "https://bad.invalid",
      "https://wrong.invalid",
      "https://pruned.invalid",
      "https://archive.invalid",
      "https://templated.invalid/v3/${INFURA_API_KEY}"
    ]
  }
]
JSON

TX="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
VICTIM="0x2222222222222222222222222222222222222222"
TOKEN="0x3333333333333333333333333333333333333333"
QUERY_RPC='https://archive.invalid/?a=1&b=2'

# Chainlist selection skips unreachable, wrong-chain, and pruned endpoints.
(
  export PATH="$MOCK_BIN:$PATH" HOME="$TMP_ROOT/home"
  export RPC_URL="" ETH_RPC_URL=""
  export CHAINLIST_URL="file://$TMP_ROOT/chains.json" RPC_PROBE_TIMEOUT=1
  bash "$SKILL_DIR/scripts/preflight.sh" ethereum "$TMP_ROOT/preflight-chainlist"
  source "$TMP_ROOT/preflight-chainlist/tool-resolution.env"
  test "$RPC_URL" = "https://archive.invalid"
  test "$RPC_SOURCE" = "chainlist"
  test "$ARCHIVE_OK" = "yes"
  test "$AUDIT_MODE" != "blocked"
)

# Direct overrides win and remain safe to source even with query parameters.
(
  export PATH="$MOCK_BIN:$PATH" HOME="$TMP_ROOT/home"
  export RPC_URL="$QUERY_RPC" ETH_RPC_URL=""
  bash "$SKILL_DIR/scripts/preflight.sh" ethereum "$TMP_ROOT/preflight-explicit"
  unset RPC_URL
  source "$TMP_ROOT/preflight-explicit/tool-resolution.env"
  test "$RPC_URL" = "$QUERY_RPC"
  test "$RPC_SOURCE" = "environment:RPC_URL"
)

# Per-chain environment variables are honored before discovery.
(
  export PATH="$MOCK_BIN:$PATH" HOME="$TMP_ROOT/home"
  export RPC_URL="" ETH_RPC_URL="$QUERY_RPC"
  bash "$SKILL_DIR/scripts/preflight.sh" ethereum "$TMP_ROOT/preflight-chain-env"
  source "$TMP_ROOT/preflight-chain-env/tool-resolution.env"
  test "$RPC_URL" = "$QUERY_RPC"
  test "$RPC_SOURCE" = "environment:ETH_RPC_URL"
)

# If Chainlist is unavailable, use the chain's configured official/public RPC.
(
  export PATH="$MOCK_BIN:$PATH" HOME="$TMP_ROOT/home"
  export RPC_URL="" OPTIMISM_RPC_URL=""
  export CHAINLIST_URL="file://$TMP_ROOT/missing-chainlist.json"
  bash "$SKILL_DIR/scripts/preflight.sh" optimism "$TMP_ROOT/preflight-official"
  source "$TMP_ROOT/preflight-official/tool-resolution.env"
  test "$RPC_URL" = "https://mainnet.optimism.io"
  test "$RPC_SOURCE" = "config-default"
)

# Reachable-but-pruned RPCs fail closed.
(
  export PATH="$MOCK_BIN:$PATH" HOME="$TMP_ROOT/home"
  export RPC_URL="https://pruned.invalid" ETH_RPC_URL=""
  if bash "$SKILL_DIR/scripts/preflight.sh" ethereum "$TMP_ROOT/preflight-pruned" >/dev/null 2>&1; then
    echo "preflight accepted a non-archival RPC" >&2
    exit 1
  fi
  source "$TMP_ROOT/preflight-pruned/tool-resolution.env"
  test "$AUDIT_MODE" = "blocked"
  test "$ARCHIVE_OK" = "no"
)

# Intake validates, atomically writes, and refuses to overwrite evidence.
(
  export PATH="$MOCK_BIN:$PATH" HOME="$TMP_ROOT/home"
  bash "$SKILL_DIR/scripts/intake.sh" "$TX" "$VICTIM" ethereum "$TMP_ROOT/preflight-explicit" >/dev/null
  jq -e . "$TMP_ROOT/preflight-explicit/evidence/tx.json" \
    "$TMP_ROOT/preflight-explicit/evidence/receipt.json" \
    "$TMP_ROOT/preflight-explicit/evidence/block.json" >/dev/null
  source "$TMP_ROOT/preflight-explicit/run.env"
  test "$RPC_URL" = "$QUERY_RPC"
  test "$BLOCK" = 100
  if bash "$SKILL_DIR/scripts/intake.sh" "$TX" "$VICTIM" ethereum "$TMP_ROOT/preflight-explicit" >/dev/null 2>&1; then
    echo "intake overwrote frozen evidence" >&2
    exit 1
  fi
)

# Failed intake leaves no zero-byte evidence artifacts.
(
  export PATH="$MOCK_BIN:$PATH" HOME="$TMP_ROOT/home" RPC_URL="https://bad.invalid"
  if bash "$SKILL_DIR/scripts/intake.sh" "$TX" "$VICTIM" ethereum "$TMP_ROOT/intake-fail" >/dev/null 2>&1; then
    echo "intake accepted an unreachable RPC" >&2
    exit 1
  fi
  test ! -e "$TMP_ROOT/intake-fail/evidence/tx.json"
  test ! -e "$TMP_ROOT/intake-fail/evidence/receipt.json"
)

# Drain bisection and loss reconciliation both fail closed on RPC errors.
(
  export PATH="$MOCK_BIN:$PATH"
  if RPC_URL="https://bad.invalid" bash "$SKILL_DIR/scripts/find-drain-block.sh" \
      "$TOKEN" "$VICTIM" 100 110 500 >/dev/null 2>&1; then
    echo "drain bisection accepted missing balances" >&2
    exit 1
  fi
  if RPC_URL="https://bad.invalid" bash "$SKILL_DIR/scripts/reconcile-loss.sh" \
      "$TOKEN" "$VICTIM" 200 201 200 201 >/dev/null 2>&1; then
    echo "loss reconciliation accepted missing RPC data" >&2
    exit 1
  fi
)

(
  export PATH="$MOCK_BIN:$PATH" RPC_URL="https://archive.invalid"
  bash "$SKILL_DIR/scripts/find-drain-block.sh" \
    "$TOKEN" "$VICTIM" 100 110 500 > "$TMP_ROOT/find.out"
  grep -q 'DROP between block 104 .* and 105 ' "$TMP_ROOT/find.out"
  bash "$SKILL_DIR/scripts/reconcile-loss.sh" \
    "$TOKEN" "$VICTIM" 200 201 200 201 > "$TMP_ROOT/loss.out"
  grep -q 'Method A total (base units): 600' "$TMP_ROOT/loss.out"
  grep -q 'Method B delta (base units): 600' "$TMP_ROOT/loss.out"
  grep -q 'residual (B - A):          0' "$TMP_ROOT/loss.out"
)

if grep -Fq -- '--no-commit' "$SKILL_DIR/references/incident-methodology.md"; then
  echo "obsolete Foundry flag remains in methodology" >&2
  exit 1
fi
if grep -Fq '"toBlock":"latest"' "$SKILL_DIR/references/incident-methodology.md"; then
  echo "unpinned evidence query remains in methodology" >&2
  exit 1
fi
grep -Fq 'cast calldata-decode "someFn(uint256,address)" 0xCALLDATA' \
  "$SKILL_DIR/references/incident-methodology.md"

if command -v forge >/dev/null 2>&1; then
  forge fmt --check "$SKILL_DIR/templates/poc/ForkReplay.t.sol"
fi

echo "security-incident-analysis smoke tests passed."
