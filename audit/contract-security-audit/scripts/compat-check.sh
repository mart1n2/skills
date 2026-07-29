#!/usr/bin/env bash
# Validate the shared skill runtime before creating audit artifacts.
# Compatible with Apple Bash 3.2 and GNU Bash on Linux.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

pass() { printf '[ok] %s\n' "$1"; }
fail() { printf '[fail] %s\n' "$1" >&2; FAIL=1; }
warn() { printf '[warn] %s\n' "$1" >&2; }

case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin) OS_NAME="macos" ;;
    Linux)  OS_NAME="linux" ;;
    *)      OS_NAME="unsupported" ;;
esac

if [ "$OS_NAME" = "unsupported" ]; then
    fail "OS must be macOS or Linux"
else
    pass "OS=$OS_NAME"
fi

if [ -z "${BASH_VERSION:-}" ]; then
    fail "run this script with bash, not sh/zsh"
elif [ "${BASH_VERSINFO[0]}" -lt 3 ] || { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
    fail "Bash 3.2+ required (found $BASH_VERSION)"
else
    pass "bash=$BASH_VERSION"
fi

for cmd in bash find grep sed awk sort tr wc head tail cmp; do
    if command -v "$cmd" >/dev/null 2>&1; then
        pass "tool=$cmd"
    else
        fail "missing required tool: $cmd"
    fi
done

if command -v curl >/dev/null 2>&1; then
    pass "optional-tool=curl (source/RPC fetch enabled)"
else
    warn "optional tool curl is unavailable; local/source-provided audits still work, but network fetch scripts are unavailable"
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/contract-audit-compat.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
mkdir -p "$TMP_ROOT/include" "$TMP_ROOT/exclude"
printf 'mint   (\n' > "$TMP_ROOT/include/sample.sol"
printf 'mint   (\n' > "$TMP_ROOT/exclude/sample.sol"

GREP_OUTPUT="$(grep -RIn --exclude-dir=exclude -E '\bmint\s*\(' "$TMP_ROOT" 2>/dev/null || true)"
case "$GREP_OUTPUT" in
    *include/sample.sol* ) pass "grep=recursive/exclude-dir/extended-regex" ;;
    * ) warn "grep lacks behavior used by the optional atlas-inventory.sh helper; use another coverage method or install a compatible grep before invoking that helper" ;;
esac

if command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    pass "json-parser=available"
else
    warn "jq/python3 unavailable; JSON-backed helpers will fail when invoked, but source/manual/proof-based review remains available"
fi

if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
    pass "sha256-tool=available"
else
    fail "shasum (macOS) or sha256sum (Linux) is required for triage artifact verification"
fi

if [ -n "${HERMES_SESSION_ID:-}" ]; then
    PLATFORM="hermes"
    EXPECTED_DIR="${HERMES_HOME:-$HOME/.hermes}/skills/contract-security-audit"
elif [ -n "${CODEX_SHELL:-}" ]; then
    PLATFORM="codex"
    EXPECTED_DIR="${CODEX_HOME:-$HOME/.codex}/skills/contract-security-audit"
else
    PLATFORM="claude-or-standalone"
    EXPECTED_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/contract-security-audit"
fi
pass "agent=$PLATFORM"

if [ "$SKILL_DIR" = "$EXPECTED_DIR" ]; then
    pass "skill-dir=$SKILL_DIR"
elif [ -n "${CONTRACT_AUDIT_SKILL_DIR:-}" ] && [ "$SKILL_DIR" = "$CONTRACT_AUDIT_SKILL_DIR" ]; then
    pass "skill-dir=explicit-override:$SKILL_DIR"
else
    printf '[warn] skill-dir=%s (default for %s is %s; source-tree execution is allowed)\n' \
        "$SKILL_DIR" "$PLATFORM" "$EXPECTED_DIR" >&2
fi

if [ ! -f "$SKILL_DIR/SKILL.md" ] || \
   [ ! -f "$SKILL_DIR/config/chains.json" ] || \
   [ ! -f "$SKILL_DIR/references/methodology.md" ] || \
   [ ! -f "$SKILL_DIR/references/triage.md" ] || \
   [ ! -s "$SKILL_DIR/templates/audit-report.md" ] || \
   [ ! -s "$SKILL_DIR/templates/external-audit-report.md" ] || \
   [ ! -s "$SKILL_DIR/scripts/retention.sh" ] || \
   [ ! -f "$SKILL_DIR/scripts/triage-index.sh" ] || \
   [ ! -f "$SKILL_DIR/scripts/triage-check.sh" ]; then
    fail "skill tree is incomplete: $SKILL_DIR"
else
    pass "skill-tree=complete"
fi

if [ "$FAIL" -ne 0 ]; then
    printf 'Compatibility check failed.\n' >&2
    exit 1
fi

printf 'Compatibility check passed.\n'
