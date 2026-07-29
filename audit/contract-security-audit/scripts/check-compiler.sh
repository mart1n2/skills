#!/usr/bin/env bash
set -uo pipefail

# Usage: check-compiler.sh <contracts-dir> [workspace]
# Extracts pragma/version directives from Solidity and Vyper files,
# cross-references source directives against a curated advisory-hint table and
# outputs structured review leads. A pragma is not the production compiler and
# a version-family match is not proof that an advisory's trigger is present.
#
# CVE database: config/compiler-cves.json (update when new CVEs are published).
# The JSON file is a deliberately incomplete discovery aid. The official
# compiler advisory lists and the pinned production build remain authoritative.

CONTRACTS_DIR="${1:?Usage: check-compiler.sh <contracts-dir> [workspace]}"
WORKSPACE="${2:-$(dirname "$CONTRACTS_DIR")}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$WORKSPACE/compiler-check.md"
CVE_CONFIG="$SKILL_DIR/config/compiler-cves.json"

if [ ! -d "$CONTRACTS_DIR" ]; then
    echo "ERROR: contracts directory not found: $CONTRACTS_DIR" >&2
    exit 1
fi

source "$(dirname "$0")/retention.sh"
audit_archive_existing "$WORKSPACE" "check-compiler" "$OUTPUT" || {
    echo "ERROR: refusing to replace compiler output without retaining the prior version" >&2
    exit 1
}

# Read CVE database update date and determine if JSON-driven checks are possible
CVE_UPDATED="unknown"
USE_JSON_CVE=0
if [ -f "$CVE_CONFIG" ]; then
    if command -v jq &>/dev/null; then
        CVE_UPDATED=$(jq -r '._updated // "unknown"' "$CVE_CONFIG" 2>/dev/null || echo "unknown")
        USE_JSON_CVE=1
    elif command -v python3 &>/dev/null; then
        CVE_UPDATED=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("_updated","unknown"))' "$CVE_CONFIG" 2>/dev/null || echo "unknown")
    fi
fi

{
    echo "# Compiler Version Check"
    echo ""
    echo "**Collected**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "**Curated advisory hints**: config/compiler-cves.json (last updated: $CVE_UPDATED)"
    echo "**Semantics**: REVIEW means a source-directive version hint matched; UNASSESSED means no curated match or insufficient parser support. Neither is a finding or clean bill of health."
    echo ""
    echo "| File | Language | Version | Status | Notes |"
    echo "|------|----------|---------|--------|-------|"
} > "$OUTPUT"

TOTAL=0
REVIEW=0
UNASSESSED=0

# JSON-driven CVE checker using jq (when available)
check_version_from_json() {
    local lang="$1" major="$2" minor="$3" patch="$4"
    if [ "$USE_JSON_CVE" -eq 0 ]; then return 1; fi
    local result
    result=$(jq -r --argjson maj "$major" --argjson min "$minor" --argjson pat "$patch" \
        --arg lang "$lang" '
        .[$lang] // [] | map(
            # Check simple match object
            if .match then
                ((.match.major // -1) as $m |
                 (.match.minor // -1) as $mi |
                 (.match.minor_lt // 999) as $mlt |
                 (.match.patch_gte // 0) as $pge |
                 (.match.patch_lte // 999) as $ple |
                 (.match.patch_lt // 999) as $plt |
                 if (($m == -1 or $m == $maj) and
                     ($mi == -1 or $mi == $min) and
                     ($mlt == 999 or $min < $mlt) and
                     $pat >= $pge and $pat <= $ple and $pat < $plt)
                 then .description + " [" + .id + "]"
                 else empty end)
            # Check match_ranges (OR of multiple ranges)
            elif .match_ranges then
                ([.match_ranges[] |
                    ((.major // -1) as $m |
                     (.minor // -1) as $mi |
                     (.patch_gte // 0) as $pge |
                     (.patch_lte // 999) as $ple |
                     if (($m == -1 or $m == $maj) and ($mi == -1 or $mi == $min) and $pat >= $pge and $pat <= $ple)
                     then true else false end)
                ] | any) as $matched |
                if $matched then .description + " [" + .id + "]"
                else empty end
            else empty end
        ) | if length > 0 then "REVIEW|" + join("; ") else empty end
    ' "$CVE_CONFIG" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    return 1
}

parse_version() {
    local ver="$1"
    local clean="${ver#^}"
    clean="${clean#>=}"
    clean="${clean#=}"
    clean="${clean%%[[:space:]]*}"
    local major minor patch
    local IFS='.'
    read -r major minor patch <<< "$clean"
    patch="${patch%%[^0-9]*}"
    echo "${major:-0} ${minor:-0} ${patch:-0}"
}

check_solidity_version() {
    local ver="$1"
    local major minor patch
    IFS=' ' read -r major minor patch <<< "$(parse_version "$ver")"

    # Curated matches are review leads only: pragma ranges may select a
    # different production compiler, and advisory conditions are not evaluated.
    if check_version_from_json "solidity" "$major" "$minor" "$patch"; then return; fi
    echo "UNASSESSED|No curated match from the available parser; resolve the exact production compiler/settings and check the official Solidity bugs list"
}

check_vyper_version() {
    local ver="$1"
    local major minor patch
    IFS=' ' read -r major minor patch <<< "$(parse_version "$ver")"

    # Curated matches are review leads only; exact release and source trigger
    # still have to be checked against the official advisory.
    if check_version_from_json "vyper" "$major" "$minor" "$patch"; then return; fi
    echo "UNASSESSED|No curated match from the available parser; resolve the exact production compiler/settings and check the official Vyper advisories"
}

while IFS= read -r -d '' file; do
    TOTAL=$((TOTAL + 1))
    rel="${file#"$CONTRACTS_DIR"/}"
    pragma=$(grep -m1 'pragma solidity' "$file" 2>/dev/null || echo "")
    if [ -n "$pragma" ]; then
        ver=$(echo "$pragma" | sed 's/.*pragma solidity[[:space:]]*//' | sed 's/;.*//' | tr -d '[:space:]')
        IFS='|' read -r status notes <<< "$(check_solidity_version "$ver")"
        echo "| $rel | Solidity | $ver | $status | $notes |" >> "$OUTPUT"
        case "$status" in
            REVIEW) REVIEW=$((REVIEW + 1)) ;;
            *) UNASSESSED=$((UNASSESSED + 1)) ;;
        esac
    else
        echo "| $rel | Solidity | not found | UNASSESSED | No source directive; resolve the production compiler from build/deployment evidence |" >> "$OUTPUT"
        UNASSESSED=$((UNASSESSED + 1))
    fi
done < <(find "$CONTRACTS_DIR" -name "*.sol" -print0 2>/dev/null)

while IFS= read -r -d '' file; do
    TOTAL=$((TOTAL + 1))
    rel="${file#"$CONTRACTS_DIR"/}"
    ver=""
    ver_line=$(grep -m1 -E '(# @version|#pragma version)' "$file" 2>/dev/null || echo "")
    if [ -n "$ver_line" ]; then
        ver=$(echo "$ver_line" | sed 's/.*@version[[:space:]]*//' | sed 's/.*#pragma version[[:space:]]*//' | tr -d '[:space:]')
        IFS='|' read -r status notes <<< "$(check_vyper_version "$ver")"
        echo "| $rel | Vyper | $ver | $status | $notes |" >> "$OUTPUT"
        case "$status" in
            REVIEW) REVIEW=$((REVIEW + 1)) ;;
            *) UNASSESSED=$((UNASSESSED + 1)) ;;
        esac
    else
        echo "| $rel | Vyper | not found | UNASSESSED | No version directive; resolve the production compiler from build/deployment evidence |" >> "$OUTPUT"
        UNASSESSED=$((UNASSESSED + 1))
    fi
done < <(find "$CONTRACTS_DIR" -name "*.vy" -print0 2>/dev/null)

{
    echo ""
    echo "## Summary"
    echo ""
    echo "- **Total files**: $TOTAL"
    echo "- **Curated review leads**: $REVIEW"
    echo "- **Unassessed by curated hints**: $UNASSESSED"
    if [ "$REVIEW" -gt 0 ]; then
        echo ""
        echo "**Next step**: resolve the exact production build and advisory trigger conditions. Do not promote a version-family match to a finding."
    fi
} >> "$OUTPUT"

echo "=== Compiler Check ==="
echo "Files: $TOTAL (review=$REVIEW unassessed=$UNASSESSED)"
echo "Output: $OUTPUT"
exit 0
