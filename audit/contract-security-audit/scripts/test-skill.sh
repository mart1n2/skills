#!/usr/bin/env bash
# Portable smoke suite for local development and CI (Apple Bash 3.2 / Linux Bash).

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/contract-audit-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

test_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

bash "$SKILL_DIR/scripts/compat-check.sh"

while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(find "$SKILL_DIR" -type f -name '*.sh' -print0)

if command -v jq >/dev/null 2>&1; then
    jq empty "$SKILL_DIR/config/chains.json" "$SKILL_DIR/config/compiler-cves.json"
else
    python3 - "$SKILL_DIR/config/chains.json" "$SKILL_DIR/config/compiler-cves.json" <<'PY'
import json
import sys
for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as handle:
        json.load(handle)
PY
fi

if [ "$(sed -n '1p' "$SKILL_DIR/SKILL.md")" != "---" ]; then
    printf 'invalid SKILL.md frontmatter opening delimiter\n' >&2
    exit 1
fi

has_closed_frontmatter() {
    awk '
        NR == 1 {
            if ($0 != "---") exit 1
            next
        }
        $0 == "---" { closed = 1; exit }
        /^#/ { exit 1 }
        END { if (!closed) exit 1 }
    ' "$1"
}

if ! has_closed_frontmatter "$SKILL_DIR/SKILL.md"; then
    printf 'invalid SKILL.md frontmatter closing delimiter\n' >&2
    exit 1
fi

# Regression: an opening delimiter without a closing delimiter must fail even
# if name/description-like lines remain parseable by the lightweight checks.
awk '
    NR == 1 { print; next }
    !removed && $0 == "---" { removed = 1; next }
    { print }
' "$SKILL_DIR/SKILL.md" > "$TMP_ROOT/unclosed-SKILL.md"
if has_closed_frontmatter "$TMP_ROOT/unclosed-SKILL.md"; then
    printf 'unclosed SKILL.md frontmatter unexpectedly passed validation\n' >&2
    exit 1
fi

SKILL_NAME="$(awk '
    NR == 1 && $0 == "---" { frontmatter = 1; next }
    frontmatter && $0 == "---" { exit }
    frontmatter && /^name:[[:space:]]*/ {
        sub(/^name:[[:space:]]*/, "")
        print
        exit
    }
' "$SKILL_DIR/SKILL.md")"
if ! printf '%s\n' "$SKILL_NAME" | grep -Eq '^[a-z0-9-]{1,64}$'; then
    printf 'invalid skill name\n' >&2
    exit 1
fi

SKILL_DESCRIPTION="$(awk '
    NR == 1 && $0 == "---" { frontmatter = 1; next }
    frontmatter && $0 == "---" { exit }
    frontmatter && /^description:[[:space:]]*>[[:space:]]*$/ { description = 1; next }
    description && /^[ \t]+/ {
        sub(/^[ \t]+/, "")
        printf "%s ", $0
        next
    }
    description { exit }
' "$SKILL_DIR/SKILL.md")"
if [ -z "$SKILL_DESCRIPTION" ] || [ "$(printf '%s' "$SKILL_DESCRIPTION" | wc -c | tr -d '[:space:]')" -gt 1024 ]; then
    printf 'invalid skill description length\n' >&2
    exit 1
fi
case "$SKILL_DESCRIPTION" in
    *'<'*|*'>'*) printf 'invalid character in skill description\n' >&2; exit 1 ;;
esac

mkdir -p "$TMP_ROOT/env-workspace"
printf 'AUDIT_ENV_PRIORITY_TEST=workspace\n' > "$TMP_ROOT/env-workspace/.env"
(
    unset AUDIT_ENV_PRIORITY_TEST
    export WORKSPACE="$TMP_ROOT/env-workspace"
    export SKILL_DIR
    source "$SKILL_DIR/scripts/load-env.sh"
    test "$AUDIT_ENV_PRIORITY_TEST" = "workspace"
)
(
    export AUDIT_ENV_PRIORITY_TEST="shell"
    export WORKSPACE="$TMP_ROOT/env-workspace"
    export SKILL_DIR
    source "$SKILL_DIR/scripts/load-env.sh"
    test "$AUDIT_ENV_PRIORITY_TEST" = "shell"
)

# Claude supports a custom configuration root. Verify both runtime discovery
# and global .env loading honor CLAUDE_CONFIG_DIR.
CUSTOM_CLAUDE="$TMP_ROOT/claude-config"
CUSTOM_SKILL="$CUSTOM_CLAUDE/skills/contract-security-audit"
mkdir -p "$CUSTOM_SKILL/scripts" "$CUSTOM_SKILL/config" \
    "$CUSTOM_SKILL/references" "$CUSTOM_SKILL/templates"
CUSTOM_CLAUDE="$(cd "$CUSTOM_CLAUDE" && pwd)"
CUSTOM_SKILL="$CUSTOM_CLAUDE/skills/contract-security-audit"
cp "$SKILL_DIR/scripts/compat-check.sh" "$CUSTOM_SKILL/scripts/compat-check.sh"
for required in \
    SKILL.md \
    config/chains.json \
    references/methodology.md \
    references/triage.md \
    templates/audit-report.md \
    templates/external-audit-report.md \
    scripts/retention.sh \
    scripts/triage-index.sh \
    scripts/triage-check.sh; do
    printf 'fixture\n' > "$CUSTOM_SKILL/$required"
done
CLAUDE_COMPAT_OUTPUT="$(
    unset HERMES_SESSION_ID CODEX_SHELL
    export CLAUDE_CONFIG_DIR="$CUSTOM_CLAUDE"
    bash "$CUSTOM_SKILL/scripts/compat-check.sh" 2>&1
)"
if ! printf '%s\n' "$CLAUDE_COMPAT_OUTPUT" | grep -Fq "[ok] skill-dir=$CUSTOM_SKILL"; then
    printf 'CLAUDE_CONFIG_DIR skill discovery regression\n' >&2
    exit 1
fi
printf 'AUDIT_CLAUDE_CONFIG_TEST=custom-root\n' > "$CUSTOM_CLAUDE/.env"
(
    unset AUDIT_CLAUDE_CONFIG_TEST HERMES_SESSION_ID CODEX_SHELL
    export CLAUDE_CONFIG_DIR="$CUSTOM_CLAUDE"
    export SKILL_DIR
    source "$SKILL_DIR/scripts/load-env.sh"
    test "$AUDIT_CLAUDE_CONFIG_TEST" = "custom-root"
)

# Codex global configuration follows CODEX_HOME just as Claude follows its
# custom configuration root.
CUSTOM_CODEX="$TMP_ROOT/codex-home"
mkdir -p "$CUSTOM_CODEX"
printf 'AUDIT_CODEX_CONFIG_TEST=custom-codex-root\n' > "$CUSTOM_CODEX/.env"
(
    unset AUDIT_CODEX_CONFIG_TEST HERMES_SESSION_ID
    export CODEX_SHELL=1
    export CODEX_HOME="$CUSTOM_CODEX"
    export SKILL_DIR
    source "$SKILL_DIR/scripts/load-env.sh"
    test "$AUDIT_CODEX_CONFIG_TEST" = "custom-codex-root"
)

for spec in "evm-demo ethereum" "solana-demo solana" "sui-demo sui"; do
    protocol="${spec% *}"
    chain="${spec#* }"
    (
        cd "$TMP_ROOT"
        bash "$SKILL_DIR/scripts/init-workspace.sh" "$protocol" "$chain"
        for artifact in scope.md target-lock.md orientation.md model.md findings.md coverage.md; do
            test -s "audit-workspace/$protocol/$artifact"
        done
        grep -Fq '## Target Identity' "audit-workspace/$protocol/target-lock.md"
        grep -Fq '## Target Artifact Manifest' "audit-workspace/$protocol/target-lock.md"
        grep -Fq '| T-01 | TBD | N/A | TBD |' "audit-workspace/$protocol/target-lock.md"
        test -d "audit-workspace/$protocol/atlas"
        test -d "audit-workspace/$protocol/tmp"
        test -d "audit-workspace/$protocol/reports"
        grep -Fq 'Do not automatically clean or prune workspace data.' \
            "audit-workspace/$protocol/README.md"
        grep -Fq 'internal reference report by default' \
            "audit-workspace/$protocol/README.md"
        grep -Fq 'external-format report only on an explicit' \
            "audit-workspace/$protocol/README.md"
        grep -Fq 'public release still requires explicit authorization' \
            "audit-workspace/$protocol/README.md"
        printf 'retain-me\n' > "audit-workspace/$protocol/tmp/retention-sentinel"
        bash "$SKILL_DIR/scripts/init-workspace.sh" "$protocol" "$chain" >/dev/null
        grep -Fq 'retain-me' "audit-workspace/$protocol/tmp/retention-sentinel"
        for artifact in \
            triage/candidates.md \
            triage/known-issues.md \
            triage/candidates/_template.md \
            triage/reproducers/_template.md \
            triage/validation/_template.md; do
            test -s "audit-workspace/$protocol/$artifact"
        done
        bash "$SKILL_DIR/scripts/triage-check.sh" --bootstrap "audit-workspace/$protocol"
    )
done

grep -Fq 'Use `templates/audit-report.md` by default.' "$SKILL_DIR/SKILL.md"
grep -Fq 'Generate `templates/external-audit-report.md` only when the user explicitly asks' \
    "$SKILL_DIR/SKILL.md"

INTERNAL_REPORT_TEMPLATE="$SKILL_DIR/templates/audit-report.md"
test -s "$INTERNAL_REPORT_TEMPLATE"
for marker in \
    'DEFAULT INTERNAL REFERENCE REPORT TEMPLATE' \
    'Use this file for the default audit output' \
    'must not be delivered externally' \
    'Generate' \
    'external-audit-report.md'; do
    grep -Fq "$marker" "$INTERNAL_REPORT_TEMPLATE"
done

EXTERNAL_REPORT_TEMPLATE="$SKILL_DIR/templates/external-audit-report.md"
test -s "$EXTERNAL_REPORT_TEMPLATE"
for marker in \
    'only when the user explicitly requests an external' \
    'It is not the default' \
    'Generating the report does not authorize client delivery or public release' \
    '## 1. Executive Summary' \
    '## 3. Assessment Scope' \
    '## 8. Detailed Findings' \
    'Fixed - Verified' \
    'FINAL RELEASE CHECKLIST'; do
    grep -Fq "$marker" "$EXTERNAL_REPORT_TEMPLATE"
done

# Bundled helpers must snapshot prior audit-relevant outputs inside workspace/tmp
# before replacing their current summaries.
RETENTION_WS="$TMP_ROOT/retention-workspace"
mkdir -p "$RETENTION_WS/old-directory"
printf 'old-file\n' > "$RETENTION_WS/current.md"
printf 'old-directory-file\n' > "$RETENTION_WS/old-directory/data.txt"
source "$SKILL_DIR/scripts/retention.sh"
audit_archive_existing "$RETENTION_WS" "retention-unit" \
    "$RETENTION_WS/current.md" "$RETENTION_WS/old-directory"
grep -R -Fq 'old-file' "$RETENTION_WS/tmp/retention-unit"
grep -R -Fq 'old-directory-file' "$RETENTION_WS/tmp/retention-unit"
test -s "$RETENTION_WS/current.md"
test -s "$RETENTION_WS/old-directory/data.txt"

RETENTION_SYMLINK_WS="$TMP_ROOT/retention-symlink"
mkdir -p "$RETENTION_SYMLINK_WS"
printf 'external-sentinel\n' > "$TMP_ROOT/external-sentinel.txt"
ln -s "$TMP_ROOT/external-sentinel.txt" "$RETENTION_SYMLINK_WS/current.md"
if audit_archive_existing "$RETENTION_SYMLINK_WS" "retention-symlink" \
    "$RETENTION_SYMLINK_WS/current.md" >/dev/null 2>&1; then
    printf 'Symlinked managed output unexpectedly passed retention checks.\n' >&2
    exit 1
fi
grep -Fq 'external-sentinel' "$TMP_ROOT/external-sentinel.txt"

RETENTION_FAIL_WS="$TMP_ROOT/retention-fail-closed"
mkdir -p "$RETENTION_FAIL_WS/contracts"
printf 'contract X {}\n' > "$RETENTION_FAIL_WS/contracts/X.sol"
printf 'compiler-current-sentinel\n' > "$RETENTION_FAIL_WS/compiler-check.md"
printf 'tmp-path-blocker\n' > "$RETENTION_FAIL_WS/tmp"
if bash "$SKILL_DIR/scripts/check-compiler.sh" \
    "$RETENTION_FAIL_WS/contracts" "$RETENTION_FAIL_WS" >/dev/null 2>&1; then
    printf 'Compiler helper replaced output after retention failure.\n' >&2
    exit 1
fi
grep -Fq 'compiler-current-sentinel' "$RETENTION_FAIL_WS/compiler-check.md"

RETENTION_HELPER_LINK_WS="$TMP_ROOT/retention-helper-link"
RETENTION_HELPER_EXTERNAL="$TMP_ROOT/retention-helper-external"
mkdir -p "$RETENTION_HELPER_LINK_WS/tmp" "$RETENTION_HELPER_EXTERNAL"
printf 'preflight-current-sentinel\n' > "$RETENTION_HELPER_LINK_WS/tool-resolution.md"
ln -s "$RETENTION_HELPER_EXTERNAL" "$RETENTION_HELPER_LINK_WS/tmp/preflight"
if bash "$SKILL_DIR/scripts/preflight.sh" "$RETENTION_HELPER_LINK_WS" >/dev/null 2>&1; then
    printf 'Preflight followed an external retention-helper symlink.\n' >&2
    exit 1
fi
grep -Fq 'preflight-current-sentinel' "$RETENTION_HELPER_LINK_WS/tool-resolution.md"
test -z "$(find "$RETENTION_HELPER_EXTERNAL" -mindepth 1 -print -quit)"

# A failed fresh source run must not count or replace stale canonical files.
FETCH_STALE_WS="$TMP_ROOT/fetch-stale"
mkdir -p "$FETCH_STALE_WS/contracts"
printf 'contract OldSource {}\n' > "$FETCH_STALE_WS/contracts/Old.sol"
printf 'old-verification-status\n' > "$FETCH_STALE_WS/verification-status.txt"
if bash "$SKILL_DIR/scripts/fetch-source.sh" \
    invalid-address ethereum "$FETCH_STALE_WS/contracts" >/dev/null 2>&1; then
    printf 'Invalid fresh fetch incorrectly succeeded from stale source files.\n' >&2
    exit 1
fi
grep -Fq 'contract OldSource' "$FETCH_STALE_WS/contracts/Old.sol"
grep -Fq 'old-verification-status' "$FETCH_STALE_WS/verification-status.txt"
test -d "$FETCH_STALE_WS/tmp/fetch-source"

# A symlinked fetch run root must fail before any data is written externally.
FETCH_LINK_WS="$TMP_ROOT/fetch-link"
FETCH_LINK_EXTERNAL="$TMP_ROOT/fetch-link-external"
mkdir -p "$FETCH_LINK_WS/contracts" "$FETCH_LINK_WS/tmp" "$FETCH_LINK_EXTERNAL"
ln -s "$FETCH_LINK_EXTERNAL" "$FETCH_LINK_WS/tmp/fetch-source"
if bash "$SKILL_DIR/scripts/fetch-source.sh" \
    invalid-address ethereum "$FETCH_LINK_WS/contracts" >/dev/null 2>&1; then
    printf 'Fetch followed an external retained-run symlink.\n' >&2
    exit 1
fi
test -z "$(find "$FETCH_LINK_EXTERNAL" -mindepth 1 -print -quit)"

# Exact GITHUB_REF acquisition must use the requested full commit, not repository
# HEAD. Fake network/git commands keep this regression deterministic and offline.
FETCH_GIT_BIN="$TMP_ROOT/fetch-git-bin"
FETCH_GIT_WS="$TMP_ROOT/fetch-github-ref"
FETCH_GIT_REF="1111111111111111111111111111111111111111"
mkdir -p "$FETCH_GIT_BIN" "$FETCH_GIT_WS/contracts" "$FETCH_GIT_WS/github-source"
printf 'contract WrongHead {}\n' > "$FETCH_GIT_WS/contracts/Head.sol"
printf 'legacy-github-source\n' > "$FETCH_GIT_WS/github-source/legacy.txt"
cat > "$FETCH_GIT_BIN/curl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$FETCH_GIT_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -eu
case "$1" in
    init)
        if [ "${2:-}" = "-q" ]; then repo="$3"; else repo="$2"; fi
        mkdir -p "$repo/.git"
        ;;
    -C)
        repo="$2"
        shift 2
        case "$1" in
            remote) ;;
            fetch)
                requested=""
                for arg in "$@"; do requested="$arg"; done
                printf '%s\n' "$requested" > "$repo/.requested-ref"
                ;;
            checkout)
                mkdir -p "$repo/src"
                printf 'contract RequestedRef {}\n' > "$repo/src/Requested.sol"
                ;;
            rev-parse)
                cat "$repo/.requested-ref"
                ;;
            *) exit 2 ;;
        esac
        ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$FETCH_GIT_BIN/curl" "$FETCH_GIT_BIN/git"
env PATH="$FETCH_GIT_BIN:/usr/bin:/bin" \
    GITHUB_URL="https://example.invalid/repository" \
    GITHUB_REF="$FETCH_GIT_REF" \
    /bin/bash "$SKILL_DIR/scripts/fetch-source.sh" \
    0x1111111111111111111111111111111111111111 ethereum \
    "$FETCH_GIT_WS/contracts" >/dev/null
test -s "$FETCH_GIT_WS/contracts/Requested.sol"
test ! -e "$FETCH_GIT_WS/contracts/Head.sol"
test ! -e "$FETCH_GIT_WS/github-source"
grep -Fq "$FETCH_GIT_REF" "$FETCH_GIT_WS/verification-status.txt"
grep -R -Fq "resolved_commit=$FETCH_GIT_REF" "$FETCH_GIT_WS/tmp/fetch-source"
grep -R -Fq 'legacy-github-source' "$FETCH_GIT_WS/tmp/fetch-source"

# Promotion is a source+status generation transaction. Inject failure into each
# new-generation rename and prove the prior current pair remains intact.
cat > "$FETCH_GIT_BIN/mv" <<'EOF'
#!/usr/bin/env bash
set -u
source_path="${1:-}"
destination_path="${2:-}"
case "${FETCH_FAIL_KIND:-}" in
    source)
        case "$source_path:$destination_path" in
            *contracts.promote-*-new:*/contracts) exit 1 ;;
        esac
        ;;
    status)
        case "$source_path:$destination_path" in
            *verification-status.txt.promote-*-new:*/verification-status.txt) exit 1 ;;
        esac
        ;;
esac
exec /bin/mv "$@"
EOF
chmod +x "$FETCH_GIT_BIN/mv"

for promotion_failure in source status; do
    FETCH_PROMOTION_WS="$TMP_ROOT/fetch-promotion-$promotion_failure"
    mkdir -p "$FETCH_PROMOTION_WS/contracts"
    printf 'contract PriorCurrent {}\n' > "$FETCH_PROMOTION_WS/contracts/Prior.sol"
    printf 'prior-current-status\n' > "$FETCH_PROMOTION_WS/verification-status.txt"
    if env PATH="$FETCH_GIT_BIN:/usr/bin:/bin" \
        FETCH_FAIL_KIND="$promotion_failure" \
        GITHUB_URL="https://example.invalid/repository" \
        GITHUB_REF="$FETCH_GIT_REF" \
        /bin/bash "$SKILL_DIR/scripts/fetch-source.sh" \
        0x1111111111111111111111111111111111111111 ethereum \
        "$FETCH_PROMOTION_WS/contracts" >/dev/null 2>&1; then
        printf '%s promotion failure unexpectedly succeeded.\n' "$promotion_failure" >&2
        exit 1
    fi
    grep -Fq 'contract PriorCurrent' "$FETCH_PROMOTION_WS/contracts/Prior.sol"
    test ! -e "$FETCH_PROMOTION_WS/contracts/Requested.sol"
    grep -Fq 'prior-current-status' "$FETCH_PROMOTION_WS/verification-status.txt"
    grep -R -Fq 'contract RequestedRef' "$FETCH_PROMOTION_WS/tmp/fetch-source"
    test -z "$(find "$FETCH_PROMOTION_WS" -maxdepth 1 \
        \( -name '*.promote-*-old' -o -name '*.promote-*-new' \) -print -quit)"
done

for retaining_helper in \
    preflight.sh \
    fetch-source.sh \
    collect-onchain-data.sh \
    check-compiler.sh \
    atlas-inventory.sh; do
    grep -Fq 'audit_archive_existing' "$SKILL_DIR/scripts/$retaining_helper"
done

PREFLIGHT_WS="$TMP_ROOT/preflight-retention"
bash "$SKILL_DIR/scripts/preflight.sh" "$PREFLIGHT_WS" >/dev/null
printf 'preflight-retention-marker\n' >> "$PREFLIGHT_WS/tool-resolution.md"
bash "$SKILL_DIR/scripts/preflight.sh" "$PREFLIGHT_WS" >/dev/null
grep -R -Fq 'preflight-retention-marker' "$PREFLIGHT_WS/tmp/preflight"

ONCHAIN_WS="$TMP_ROOT/onchain-retention"
mkdir -p "$ONCHAIN_WS/evidence"
env PATH=/usr/bin:/bin /bin/bash "$SKILL_DIR/scripts/collect-onchain-data.sh" \
    0x1111111111111111111111111111111111111111 ethereum http://127.0.0.1:1 \
    "$ONCHAIN_WS/evidence" "$ONCHAIN_WS" >/dev/null
printf 'onchain-retention-marker\n' >> "$ONCHAIN_WS/evidence/onchain.md"
env PATH=/usr/bin:/bin /bin/bash "$SKILL_DIR/scripts/collect-onchain-data.sh" \
    0x1111111111111111111111111111111111111111 ethereum http://127.0.0.1:1 \
    "$ONCHAIN_WS/evidence" "$ONCHAIN_WS" >/dev/null
grep -R -Fq 'onchain-retention-marker' "$ONCHAIN_WS/tmp/collect-onchain-data"

# Chain aliases resolve through chains.json and are recorded canonically.
(
    cd "$TMP_ROOT"
    bash "$SKILL_DIR/scripts/init-workspace.sh" alias-demo eth >/dev/null
    grep -Fq '| Chain | ethereum |' audit-workspace/alias-demo/scope.md
    grep -Fq '# Audit Workspace: alias-demo (ethereum)' audit-workspace/alias-demo/README.md

    # Reusing a protocol name for a different chain must fail without rewriting
    # the existing README/scope into a split-brain workspace.
    if bash "$SKILL_DIR/scripts/init-workspace.sh" alias-demo solana >/dev/null 2>&1; then
        printf 'cross-chain workspace reinitialization unexpectedly succeeded\n' >&2
        exit 1
    fi
    grep -Fq '| Chain | ethereum |' audit-workspace/alias-demo/scope.md
    grep -Fq '# Audit Workspace: alias-demo (ethereum)' audit-workspace/alias-demo/README.md

    # README-only workspaces remain chain-bound; init must not create a conflicting
    # scope beside an existing chain declaration.
    mkdir -p audit-workspace/readme-only
    printf '# Audit Workspace: readme-only (solana)\n' \
        > audit-workspace/readme-only/README.md
    if bash "$SKILL_DIR/scripts/init-workspace.sh" readme-only ethereum >/dev/null 2>&1; then
        printf 'README-only cross-chain reinitialization unexpectedly succeeded\n' >&2
        exit 1
    fi
    test ! -e audit-workspace/readme-only/scope.md

    # A pre-existing malformed scope cannot be silently blessed by bootstrap.
    mkdir -p audit-workspace/malformed-scope
    printf '# Scope without a Chain row\n' \
        > audit-workspace/malformed-scope/scope.md
    if bash "$SKILL_DIR/scripts/init-workspace.sh" malformed-scope ethereum >/dev/null 2>&1; then
        printf 'Malformed existing scope unexpectedly passed initialization\n' >&2
        exit 1
    fi
    test ! -e audit-workspace/malformed-scope/README.md
)

# Populate final-mode scope and closure fields for the EVM triage fixtures.
printf 'contract Vault {}\n' \
    > "$TMP_ROOT/audit-workspace/evm-demo/contracts/Vault.sol"
VAULT_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/contracts/Vault.sol")"
cat > "$TMP_ROOT/audit-workspace/evm-demo/scope.md" <<'EOF'
# Scope — Phase 0

## Target Identity

| Field | Value |
|-------|-------|
| Protocol | evm-demo |
| Chain | ethereum |
| Source repository / package | git@github.com:example/evm-demo.git |
| Source revision | commit-abc123 |
| Deployment / program / package IDs | N/A |
| Deployed bytecode / package hash | N/A |
| Production build/profile or target-identity procedure | release optimizer=true |
| Compiler / toolchain | solc 0.8.24 |
| Configuration / state anchor | source-revision=commit-abc123 |

## In Scope

- `contracts/Vault.sol` at `commit-abc123`.

## Out of Scope

- Live deployment behavior; this initial fixture is a source/logic audit.

## Narrow Work Units

| ID | Attack surface / invariant | Owner | Status | Evidence / candidate links |
|----|----------------------------|-------|--------|----------------------------|
EOF
cat > "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md" <<EOF
# Target Lock

## Target Identity

| Field | Value |
|-------|-------|
| Protocol | evm-demo |
| Chain | ethereum |
| Source repository / package | git@github.com:example/evm-demo.git |
| Source revision | commit-abc123 |
| Deployment / program / package IDs | N/A |
| Deployed bytecode / package hash | N/A |
| Production build/profile or target-identity procedure | release optimizer=true |
| Compiler / toolchain | solc 0.8.24 |
| Configuration / state anchor | source-revision=commit-abc123 |

## Target Artifact Manifest

| Target ID | Workspace path | SHA-256 | Role / scope significance |
|-----------|----------------|---------|---------------------------|
| T-01 | contracts/Vault.sol | $VAULT_HASH | Primary scoped contract source |
EOF
TARGET_LOCK_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md")"
test "${#TARGET_LOCK_HASH}" -eq 64
# A source/logic audit with no deployed finding may explicitly have no
# deployment identifiers. This must not be mistaken for an incomplete target.
for identity_file in scope.md target-lock.md; do
    grep -Fq '| Deployment / program / package IDs | N/A |' \
        "$TMP_ROOT/audit-workspace/evm-demo/$identity_file"
    grep -Fq '| Deployed bytecode / package hash | N/A |' \
        "$TMP_ROOT/audit-workspace/evm-demo/$identity_file"
done
cat > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" <<'EOF'
# Coverage & Closure

## Objective Artifact Reconciliation

| Artifact class | Expected | Reviewed / resolved | Open | Evidence |
|----------------|----------|---------------------|------|----------|
| In-scope target artifacts | 1 | 1 | 0 | pinned target fixture |
| Candidates dispositioned | 0 | 0 | 0 | generated candidate index |
| Candidates with verification evidence | 0 | 0 | 0 | verification manifest directory |
| Independent validations | 0 | 0 | 0 | validation directory |
| Material candidate verdicts | 0 | 0 | 0 | candidate closure-class reconciliation |
| Human-accepted findings | 0 | 0 | 0 | findings.md reconciliation |

## Method-Defined Security Coverage

| Coverage obligation / surface | Status | Evidence / method | Residual blind spots / limitation |
|-------------------------------|--------|-------------------|------------------------------------|
| Fixture contract security obligations | COVERED | manual fixture review plus checker regression evidence | no material blind spots identified in this fixture |

## Candidate Limitations

| Candidate | Materiality | Status | Blocker / open proof obligation | Required next step | Report verdict |
|-----------|-------------|--------|---------------------------------|--------------------|----------------|

## Open Assumptions and Blocked Checks

| ID | Question / blocker | Affected scope or funds | Required next step | Reported as limitation? |
|----|--------------------|-------------------------|--------------------|-------------------------|
EOF

# Orientation/model scaffolds, executable PoCs, and the bundled Atlas are all
# optional. A truth-complete final closure must remain valid without them.
rm -rf \
    "$TMP_ROOT/audit-workspace/evm-demo/orientation.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/model.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/poc" \
    "$TMP_ROOT/audit-workspace/evm-demo/atlas"
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo"

# Target artifacts are content-addressed. Mutating a listed source without
# updating and revalidating its lock must fail closed.
cp "$TMP_ROOT/audit-workspace/evm-demo/contracts/Vault.sol" \
    "$TMP_ROOT/audit-workspace/evm-demo/contracts/Vault.sol.locked"
printf 'contract Mutated {}\n' \
    >> "$TMP_ROOT/audit-workspace/evm-demo/contracts/Vault.sol"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >"$TMP_ROOT/target-mutation.log" 2>&1; then
    printf 'Mutated target artifact unexpectedly passed final triage checks.\n' >&2
    exit 1
fi
grep -Fq 'T-01 SHA-256 does not match contracts/Vault.sol' \
    "$TMP_ROOT/target-mutation.log"
mv "$TMP_ROOT/audit-workspace/evm-demo/contracts/Vault.sol.locked" \
    "$TMP_ROOT/audit-workspace/evm-demo/contracts/Vault.sol"
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo"

# Arbitrary regular files under contracts/ are not silently counted as scoped
# targets; only explicit target-lock manifest rows define the count.
printf 'contract Unlisted {}\n' \
    > "$TMP_ROOT/audit-workspace/evm-demo/contracts/Unlisted.sol"
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo"
rm "$TMP_ROOT/audit-workspace/evm-demo/contracts/Unlisted.sol"

# A second explicitly locked target does change the objective scope count and
# therefore exposes stale closure accounting.
printf 'contract ListedSecond {}\n' \
    > "$TMP_ROOT/audit-workspace/evm-demo/contracts/ListedSecond.sol"
SECOND_TARGET_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/contracts/ListedSecond.sol")"
cp "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md.one-target"
awk -v digest="$SECOND_TARGET_HASH" '
    { print }
    /^\| T-01 / {
        print "| T-02 | contracts/ListedSecond.sol | " digest " | Second explicitly scoped contract source |"
    }
' "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md.one-target" \
    > "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >"$TMP_ROOT/second-target-count.log" 2>&1; then
    printf 'Unreconciled second locked target unexpectedly passed final triage checks.\n' >&2
    exit 1
fi
grep -Fq 'coverage row In-scope target artifacts must reconcile to actual artifact count 2' \
    "$TMP_ROOT/second-target-count.log"
mv "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md.one-target" \
    "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md"
rm "$TMP_ROOT/audit-workspace/evm-demo/contracts/ListedSecond.sol"
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo"

# A nested source symlink is not a pinned target artifact, even when it points
# back into the same contracts tree.
mkdir -p "$TMP_ROOT/audit-workspace/evm-demo/contracts/nested"
ln -s ../Vault.sol \
    "$TMP_ROOT/audit-workspace/evm-demo/contracts/nested/LinkedVault.sol"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >"$TMP_ROOT/nested-source-symlink.log" 2>&1; then
    printf 'Nested source symlink unexpectedly passed final triage checks.\n' >&2
    exit 1
fi
grep -Fq 'in-scope target artifacts must be regular workspace files, not symlinks' \
    "$TMP_ROOT/nested-source-symlink.log"
rm "$TMP_ROOT/audit-workspace/evm-demo/contracts/nested/LinkedVault.sol"
rmdir "$TMP_ROOT/audit-workspace/evm-demo/contracts/nested"
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo"

run_adversarial_triage_tests() {
expect_triage_failure() {
    message="$1"
    expected="${2:-}"
    failure_log="$TMP_ROOT/triage-failure.log"
    if bash "$SKILL_DIR/scripts/triage-check.sh" \
        "$TMP_ROOT/audit-workspace/evm-demo" >"$failure_log" 2>&1; then
        printf '%s\n' "$message" >&2
        exit 1
    fi
    if [ -n "$expected" ] && ! grep -Fq "$expected" "$failure_log"; then
        printf '%s Expected error containing: %s\n' "$message" "$expected" >&2
        sed -n '1,80p' "$failure_log" >&2
        exit 1
    fi
}

# Evidence fidelity and current exposure are separate axes. A historical or
# remediated deployed-state receipt remains CONFIRMED-DEPLOYED even when the
# selected current state is no longer exposed.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.exposure-valid"
sed 's/- Current deployment: confirmed exploitable/- Current deployment: not exposed at pinned state/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.exposure-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.exposure-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Conversely, a current exposure claim requires deployed-target evidence;
# source-logic or reconstruction fidelity cannot establish present exposure.
for non_deployed_verdict in CONFIRMED-LOGIC CONFIRMED-RECONSTRUCTION; do
    cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
        "$TMP_ROOT/audit-workspace/evm-demo/findings.md.exposure-grade-valid"
    sed \
        -e 's/- Current deployment: confirmed exploitable/- Current deployment: plausibly exposed/' \
        -e "s/- Evidence verdict: CONFIRMED-DEPLOYED/- Evidence verdict: $non_deployed_verdict/" \
        "$TMP_ROOT/audit-workspace/evm-demo/findings.md.exposure-grade-valid" \
        > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
    expect_triage_failure \
        "Current exposure paired with $non_deployed_verdict unexpectedly passed." \
        'makes a deployment-state claim without CONFIRMED-DEPLOYED evidence'
    mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.exposure-grade-valid" \
        "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
done

# CONFIRMED-DEPLOYED cannot bind arbitrary substantive strings as an EVM
# deployment identity; native address/hash shape is a minimum mechanical gate.
for identity_file in scope.md target-lock.md; do
    cp "$TMP_ROOT/audit-workspace/evm-demo/$identity_file" \
        "$TMP_ROOT/audit-workspace/evm-demo/$identity_file.native-valid"
    sed 's/0x1111111111111111111111111111111111111111/0x1234/g' \
        "$TMP_ROOT/audit-workspace/evm-demo/$identity_file.native-valid" \
        > "$TMP_ROOT/audit-workspace/evm-demo/$identity_file"
done
expect_triage_failure 'Short EVM deployment address unexpectedly passed.' \
    'CONFIRMED-DEPLOYED EVM identity requires a 20-byte deployment address'
for identity_file in scope.md target-lock.md; do
    mv "$TMP_ROOT/audit-workspace/evm-demo/$identity_file.native-valid" \
        "$TMP_ROOT/audit-workspace/evm-demo/$identity_file"
done

# Every accepted-claim layer must bind the exact current target lock. A stale
# digest in any one layer is independently fatal.
for lock_bound_file in \
    triage/candidates/C-02.md \
    triage/reproducers/C-02.md \
    triage/validation/C-02.md \
    findings.md; do
    lock_bound_path="$TMP_ROOT/audit-workspace/evm-demo/$lock_bound_file"
    cp "$lock_bound_path" "$lock_bound_path.lock-valid"
    sed "s/$TARGET_LOCK_HASH/0000000000000000000000000000000000000000000000000000000000000000/" \
        "$lock_bound_path.lock-valid" > "$lock_bound_path"
    expect_triage_failure "Stale target-lock digest in $lock_bound_file unexpectedly passed." \
        'SHA-256 does not match'
    mv "$lock_bound_path.lock-valid" "$lock_bound_path"
done
bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null

# The method-defined section must contain at least one substantive row, but its
# surface names are deliberately not prescribed.
cp "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.rows-valid"
sed '/^| Fixture contract security obligations |/d' \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.rows-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
expect_triage_failure 'Empty method-defined coverage unexpectedly passed.' \
    'method-defined coverage table requires at least one substantive row'
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.rows-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"

# Placeholder-like coverage evidence must fail even when padded with prose.
cp "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.evidence-valid"
awk -F '|' '
    function trim(value) { sub(/^[ \t]+/, "", value); sub(/[ \t]+$/, "", value); return value }
    trim($2) == "In-scope target artifacts" {
        print "| In-scope target artifacts | 1 | 1 | 0 | TBD count later |"
        next
    }
    { print }
' "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.evidence-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
expect_triage_failure 'TBD-prefixed coverage evidence unexpectedly passed.' \
    'coverage row In-scope target artifacts requires substantive evidence'
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.evidence-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"

# Canonical parent directories cannot be external symlinks.
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates" \
    "$TMP_ROOT/candidates-outside"
ln -s "$TMP_ROOT/candidates-outside" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates"
expect_triage_failure 'Symlinked candidate directory unexpectedly passed.' \
    'canonical workspace path must not traverse a symlink'
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates"
mv "$TMP_ROOT/candidates-outside" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates"

# Dynamic verification and validation manifests must also be regular files.
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    "$TMP_ROOT/C-02-reproducer-outside.md"
ln -s "$TMP_ROOT/C-02-reproducer-outside.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
expect_triage_failure 'Symlinked verification manifest unexpectedly passed.' \
    'verification manifest must be a regular workspace file, not a symlink'
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
mv "$TMP_ROOT/C-02-reproducer-outside.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"

mv "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md" \
    "$TMP_ROOT/C-02-validation-outside.md"
ln -s "$TMP_ROOT/C-02-validation-outside.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md"
expect_triage_failure 'Symlinked validation manifest unexpectedly passed.' \
    'validation record must be a regular workspace file, not a symlink'
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md"
mv "$TMP_ROOT/C-02-validation-outside.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md"

# Evidence grade is a structured claim and must match target fidelity.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.fidelity-valid"
sed 's/- Target fidelity: DEPLOYED/- Target fidelity: LOGIC/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.fidelity-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
expect_triage_failure 'Manifest verdict/fidelity contradiction unexpectedly passed.' \
    "Evidence verdict 'CONFIRMED-DEPLOYED' contradicts Target fidelity 'LOGIC'"
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.fidelity-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"

# Finding fields reject disguised deployment claims, placeholders, and section
# bleed across a later same-level heading.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.enum-valid"
sed 's/- Current deployment: confirmed exploitable/- Current deployment: currently live and confirmed drainable/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.enum-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
expect_triage_failure 'Free-form current-deployment claim unexpectedly passed.' \
    'invalid Current deployment enum'
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.enum-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fields-valid"
sed 's/- Mechanism: permissionless deposit bypasses the conservation check/- Mechanism: unknown/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fields-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
expect_triage_failure 'Placeholder accepted-finding mechanism unexpectedly passed.' \
    'requires exactly one non-placeholder field: Mechanism'
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fields-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.sections-valid"
awk '
    { print }
    !inserted && /^## F-01/ { print "## Appendix"; inserted = 1 }
' "$TMP_ROOT/audit-workspace/evm-demo/findings.md.sections-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
expect_triage_failure 'Finding fields after an Appendix heading unexpectedly bled into F-01.' \
    'requires exactly one non-placeholder field: Candidate ID / dedup key'
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.sections-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.heading-valid"
sed 's/^## F-01 /## F-01evil /' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.heading-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
expect_triage_failure 'Malformed F-ID heading unexpectedly passed.' \
    'malformed finding heading'
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.heading-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Candidate filenames and IDs use exact C-NN grammar.
sed 's/C-02/C-02evil/g' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02evil.md"
if bash "$SKILL_DIR/scripts/triage-index.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >"$TMP_ROOT/index-id.log" 2>&1; then
    printf 'Malformed candidate ID unexpectedly passed index generation.\n' >&2
    exit 1
fi
grep -Fq 'candidate ID and filename must use matching exact C-NN grammar' \
    "$TMP_ROOT/index-id.log"
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02evil.md"

# A coherent manifest grade still cannot disagree with the accepted finding.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.grade-valid"
sed \
    -e 's/- Evidence verdict: CONFIRMED-DEPLOYED/- Evidence verdict: CONFIRMED-LOGIC/' \
    -e 's/- Target fidelity: DEPLOYED/- Target fidelity: LOGIC/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.grade-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
expect_triage_failure 'Finding/manifest evidence-grade mismatch unexpectedly passed.' \
    "does not match manifest verdict 'CONFIRMED-LOGIC'"
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.grade-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"

# The escape hatch for chain-specific anchors is still structured and versioned.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.anchor-valid"
sed \
    -e 's/- State anchor kind: BLOCK/- State anchor kind: OTHER-PINNED/' \
    -e 's/- State anchor value: 22000000/- State anchor value: mainnet/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.anchor-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
expect_triage_failure 'Generic unversioned state anchor unexpectedly passed.' \
    'OTHER-PINNED State anchor value must use a named immutable/versioned anchor'
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.anchor-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"

# Non-numeric anchor kinds still require native immutable identifier formats;
# a prose token must not masquerade as a transaction receipt.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.transaction-valid"
sed \
    -e 's/- State anchor kind: BLOCK/- State anchor kind: TRANSACTION/' \
    -e 's/- State anchor value: 22000000/- State anchor value: banana/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.transaction-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
expect_triage_failure 'Unstructured transaction anchor unexpectedly passed.' \
    'EVM TRANSACTION anchor must be a 32-byte transaction hash'
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.transaction-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"

# Artifact-count coverage rows cannot be manually reset after acceptance.
cp "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.count-valid"
sed '/^| Human-accepted findings |/ s/| 1 | 1 | 0 |/| 0 | 0 | 0 |/' \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.count-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
expect_triage_failure 'Human-accepted finding count mismatch unexpectedly passed.' \
    'coverage row Human-accepted findings must reconcile to actual artifact count 1'
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.count-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"

# Engagement-defined severity labels are accepted; the independent MATERIAL
# closure class, rather than a hard-coded vocabulary, drives the clean-verdict gate.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md.severity-valid"
sed 's/- Potential severity \/ materiality: High \/ MATERIAL/- Potential severity \/ materiality: catastrophic \/ MATERIAL/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md.severity-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md.severity-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null

# Candidate terminal dispositions require a substantive reason/evidence field.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md.disposition-valid"
sed '/^- Disposition reason \/ evidence:/d' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md.disposition-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md"
expect_triage_failure 'Missing candidate disposition unexpectedly passed triage checks.'
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md.disposition-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md"

# Verification packages are method-neutral, but target/reachability/proof facts
# remain part of the machine-enforced contract.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.contract-valid"
sed \
    -e '/^- Actor initial conditions and capital\/capability acquisition:/d' \
    -e '/^- Preconditions checked:/d' \
    -e '/^- Action sequence or proof derivation:/d' \
    -e '/^- Evidence method:/d' \
    -e '/^- Production-state deviations:/d' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.contract-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
expect_triage_failure 'Incomplete verification evidence contract unexpectedly passed.'
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.contract-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"

# A correct link elsewhere in findings.md cannot satisfy a different F-NN
# section whose own evidence link is wrong.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.section-valid"
awk '
    !inserted && /^## F-01/ {
        print "- Verification evidence: triage/reproducers/C-02.md"
        inserted = 1
    }
    { print }
' "$TMP_ROOT/audit-workspace/evm-demo/findings.md.section-valid" | \
    sed '/^## F-01/,$ s#^- Verification evidence: triage/reproducers/C-02.md#- Verification evidence: triage/reproducers/C-99.md#' \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
expect_triage_failure 'Cross-section verification link unexpectedly passed triage checks.'
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.section-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Confirmed deployment language cannot be paired with logic-only evidence.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.deployment-valid"
sed 's/- Evidence verdict: CONFIRMED-DEPLOYED/- Evidence verdict: CONFIRMED-LOGIC/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.deployment-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
expect_triage_failure 'Deployment/evidence contradiction unexpectedly passed triage checks.'
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.deployment-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Final scope and coverage require substantive, numeric closure.
cp "$TMP_ROOT/audit-workspace/evm-demo/scope.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/scope.md.substantive"
sed 's#| Source repository / package | git@github.com:example/evm-demo.git |#| Source repository / package | N/A |#' \
    "$TMP_ROOT/audit-workspace/evm-demo/scope.md.substantive" \
    > "$TMP_ROOT/audit-workspace/evm-demo/scope.md"
expect_triage_failure 'N/A-only scope unexpectedly passed final triage checks.'
mv "$TMP_ROOT/audit-workspace/evm-demo/scope.md.substantive" \
    "$TMP_ROOT/audit-workspace/evm-demo/scope.md"

cp "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.numeric"
sed '/^| In-scope target artifacts |/ s/| 1 | 1 | 0 |/| unknown | 1 | unknown |/' \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.numeric" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
expect_triage_failure 'Unknown coverage counts unexpectedly passed final triage checks.'
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.numeric" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"

# Workspace-relative evidence must not escape through a symlink.
mv "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol" "$TMP_ROOT/C-02-outside.t.sol"
ln -s "$TMP_ROOT/C-02-outside.t.sol" \
    "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol"
expect_triage_failure 'Symlinked external reproducer unexpectedly passed triage checks.'
rm "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol"
mv "$TMP_ROOT/C-02-outside.t.sol" \
    "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol"

# Contradictory validator conclusions cannot be hidden behind a nominal human
# ACCEPTED marker.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md.valid"
sed \
    -e 's/PASS — reachable/UNREACHABLE — not reachable/' \
    -e 's/PASS — net gain/FAILED — net gain/' \
    -e 's/NOVEL —/DUPLICATE —/' \
    -e 's/INDEPENDENTLY-VALIDATED/REJECTED/' \
    -e 's#ACCEPTED / human-auditor / 2026-07-13#ACCEPTED#' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md.valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Contradictory validation conclusions unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md.valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md"

# State anchors must be pinned even when "latest" appears after a chain name.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.pinned"
sed 's/- State anchor value: 22000000/- State anchor value: latest/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.pinned" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Unpinned latest state anchor unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.pinned" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"

# Accepted findings require the complete schema, not just a candidate link.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.complete"
sed '/^- Original severity: High$/d' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.complete" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Incomplete accepted-finding schema unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.complete" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Deployment-state claims require an immutable state anchor in the finding.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.anchored"
sed 's#^- Deployment/state anchor:.*#- Deployment/state anchor: NOT ASSESSED - unavailable#' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.anchored" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Deployment exposure without an immutable state anchor unexpectedly passed.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.anchored" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Fixed - Verified requires an exact remediation baseline and substantive retest.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.open"
sed 's/^- Current remediation status: Open$/- Current remediation status: Fixed - Verified/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.open" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Fixed - Verified without remediation/retest evidence unexpectedly passed.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.open" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fixed-components"
FIX_REVISION="git:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
printf 'remediation revision %s\n' "$FIX_REVISION" \
    > "$TMP_ROOT/audit-workspace/evm-demo/evidence/remediation-baseline.md"
printf 'target-faithful retest: original mechanism closed; positive control functioning\n' \
    > "$TMP_ROOT/audit-workspace/evm-demo/evidence/fix.log"
FIX_BASELINE_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/evidence/remediation-baseline.md")"
FIX_RETEST_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/evidence/fix.log")"
FIX_BASELINE_RECORD="revision=$FIX_REVISION; manifest=evidence/remediation-baseline.md; sha256=$FIX_BASELINE_HASH"
FIX_RETEST_RECORD="reviewer=human-auditor; date=2026-07-14; method=unrestricted target-faithful review; evidence=evidence/fix.log; sha256=$FIX_RETEST_HASH; result=ORIGINAL MECHANISM CLOSED"
sed \
    -e 's/^- Current remediation status: Open$/- Current remediation status: Fixed - Verified/' \
    -e "s|^- Remediation baseline:.*$|- Remediation baseline: $FIX_BASELINE_RECORD|" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fixed-components" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Fixed - Verified with no substantive retest unexpectedly passed.\n' >&2
    exit 1
fi

sed \
    -e 's/^- Current remediation status: Open$/- Current remediation status: Fixed - Verified/' \
    -e "s|^- Retest:.*$|- Retest: $FIX_RETEST_RECORD|" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fixed-components" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Fixed - Verified with no exact remediation baseline unexpectedly passed.\n' >&2
    exit 1
fi

# Generic labels are not sufficient evidence for a Fixed - Verified state.
sed \
    -e 's/^- Current remediation status: Open$/- Current remediation status: Fixed - Verified/' \
    -e 's/^- Remediation baseline:.*$/- Remediation baseline: reviewed patch/' \
    -e 's/^- Retest:.*$/- Retest: PASS/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fixed-components" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Fixed - Verified with generic patch/PASS labels unexpectedly passed.\n' >&2
    exit 1
fi

INVALID_DATE_RETEST_RECORD="reviewer=human-auditor; date=2026-99-99; method=unrestricted target-faithful review; evidence=evidence/fix.log; sha256=$FIX_RETEST_HASH; result=ORIGINAL MECHANISM CLOSED"
sed \
    -e 's/^- Current remediation status: Open$/- Current remediation status: Fixed - Verified/' \
    -e "s|^- Remediation baseline:.*$|- Remediation baseline: $FIX_BASELINE_RECORD|" \
    -e "s|^- Retest:.*$|- Retest: $INVALID_DATE_RETEST_RECORD|" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fixed-components" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Fixed - Verified with an impossible calendar date unexpectedly passed.\n' >&2
    exit 1
fi

BAD_RETEST_RECORD="reviewer=human-auditor; date=2026-07-14; method=unrestricted target-faithful review; evidence=evidence/fix.log; sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd; result=ORIGINAL MECHANISM CLOSED"
sed \
    -e 's/^- Current remediation status: Open$/- Current remediation status: Fixed - Verified/' \
    -e "s|^- Remediation baseline:.*$|- Remediation baseline: $FIX_BASELINE_RECORD|" \
    -e "s|^- Retest:.*$|- Retest: $BAD_RETEST_RECORD|" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fixed-components" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Fixed - Verified with a mismatched retained evidence hash unexpectedly passed.\n' >&2
    exit 1
fi

sed \
    -e 's/^- Current remediation status: Open$/- Current remediation status: Fixed - Verified/' \
    -e "s|^- Remediation baseline:.*$|- Remediation baseline: $FIX_BASELINE_RECORD|" \
    -e "s|^- Retest:.*$|- Retest: $FIX_RETEST_RECORD|" \
    -e 's/^- Residual risk:.*$/- Residual risk: NO RESIDUAL RISK IDENTIFIED within the stated retest scope/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fixed-components" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.fixed-components" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Remediation status is a closed enum; ad hoc labels must not enter reports.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.status-valid"
sed 's/^- Current remediation status: Open$/- Current remediation status: Closed/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.status-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Invalid remediation status unexpectedly passed.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.status-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Unknown deployment applicability may carry an explicit reasoned NOT ASSESSED
# anchor, and a scoped no-residual-risk statement is substantive report data.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.deployed-valid"
sed \
    -e 's/^- Current deployment: confirmed exploitable$/- Current deployment: unknown/' \
    -e 's#^- Deployment/state anchor:.*#- Deployment/state anchor: NOT ASSESSED - no live deployment in review scope#' \
    -e 's/^- Residual risk: Full original impact remains$/- Residual risk: NO RESIDUAL RISK IDENTIFIED within the stated retest scope/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.deployed-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.deployed-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Reproducer artifacts must exist and their recorded digest must match.
mv "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol" \
    "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol.saved"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Missing reproducer artifact unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol.saved" \
    "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol"

cp "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.hash-valid"
sed "s/$POC_HASH/0000/" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.hash-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Incorrect reproducer digest unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md.hash-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md"

# Final mode cannot leave a complete candidate in a non-terminal state.
sed \
    -e 's/C-02/C-04/g' \
    -e 's/missing-check|asset-conservation|withdrawal/proposed|invariant|sink/' \
    -e 's/HUMAN-ACCEPTED/PROPOSED/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-04.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Non-terminal final candidate unexpectedly passed triage checks.\n' >&2
    exit 1
fi
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-04.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null

# The accepted finding dedup key must match its candidate and known-issue entry.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.dedup-valid"
sed 's/missing-check|asset-conservation|withdrawal/other|invariant|sink/' \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.dedup-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Mismatched finding dedup key unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.dedup-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

cp "$TMP_ROOT/audit-workspace/evm-demo/triage/known-issues.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/known-issues.md.complete"
sed '/missing-check\\|asset-conservation\\|withdrawal/d' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/known-issues.md.complete" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/known-issues.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Missing known-issue canonical entry unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/known-issues.md.complete" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/known-issues.md"

# Two accepted candidates cannot share one dedup key.
sed 's/C-02/C-03/g' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-03.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
sed 's/- Candidate: C-02/- Candidate: C-03/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-03.md"
sed 's/- Candidate: C-02/- Candidate: C-03/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-03.md"
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.one-canonical"
cat >> "$TMP_ROOT/audit-workspace/evm-demo/findings.md" <<EOF
## F-02 — Duplicate Accepted Key
- Candidate ID / dedup key: C-03 / missing-check|asset-conservation|withdrawal
- Target lock SHA-256: $TARGET_LOCK_HASH
- Target artifact IDs: T-01
- Discovery context / classification: optional manual review / access control
- Target locator: contracts/Vault.sol:42
- Reachability chain / evidence: deposit -> W-01 -> S-01
- Mechanism: same root cause as F-01
- Invariant violated: INV-1 assets remain conserved
- Original severity: High
- Current remediation status: Open
- Current deployment: confirmed exploitable
- Deployment/state anchor: ethereum Vault deployment at block 22000000 / block hash 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- Evidence verdict: CONFIRMED-DEPLOYED
- Verification evidence: triage/reproducers/C-03.md
- Independent validation: triage/validation/C-03.md
- Cost versus impact: 100 USDC versus 1000 USDC loss
- Human decision: ACCEPTED / human-auditor / 2026-07-13
- Client response: NOT PROVIDED as of 2026-07-13
- Remediation baseline: NOT PROVIDED - finding remains open
- Retest: NOT YET RETESTED - finding remains open
- Residual risk: Full original impact remains
- Disclosure handling: CLIENT-CONFIDENTIAL / human-auditor / 2026-07-13
EOF
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Duplicate HUMAN-ACCEPTED dedup keys unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.one-canonical" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-03.md" \
   "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-03.md" \
   "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-03.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null

# Duplicate schema fields are contradictory merge artifacts and must fail closed
# in both the generated index and the acceptance checker.
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md.single"
printf '%s\n' '- Status: REJECTED' \
    >> "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md"
if bash "$SKILL_DIR/scripts/triage-index.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Duplicate candidate Status unexpectedly passed index generation.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md.single" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md"

cp "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md.single"
printf '%s\n' '- Actor/reachability verdict: FAIL — contradictory duplicate' \
    >> "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md"
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Duplicate validation verdict unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md.single" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md"

# INCONCLUSIVE is a structured closure state. A material unresolved candidate
# must carry one OPEN/PARTIAL row and force an INCOMPLETE report verdict.
sed \
    -e 's/C-02/C-05/g' \
    -e 's/missing-check|asset-conservation|withdrawal/unresolved-state|asset-conservation|withdrawal/' \
    -e 's/- Coverage limitation: N\/A/- Coverage limitation: coverage.md Candidate Limitations C-05/' \
    -e 's/- Status: HUMAN-ACCEPTED/- Status: INCONCLUSIVE/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-05.md"
cp "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.inconclusive-valid"
sed \
    -e '/^| Candidates dispositioned |/ s/| 1 | 1 | 0 |/| 2 | 2 | 0 |/' \
    -e '/^| Material candidate verdicts |/ s/| 1 | 1 | 0 |/| 2 | 2 | 0 |/' \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.inconclusive-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
expect_triage_failure 'INCONCLUSIVE candidate without structured row unexpectedly passed.' \
    'candidate limitation table requires exactly one row for C-05'
awk '
    !inserted && /^## Open Assumptions and Blocked Checks/ {
        print "| C-05 | High / MATERIAL | OPEN | production state unavailable | obtain pinned state evidence | COMPLETE |"
        print ""
        inserted = 1
    }
    { print }
' "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.tmp"
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.tmp" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
expect_triage_failure 'MATERIAL INCONCLUSIVE candidate with COMPLETE verdict unexpectedly passed.' \
    'requires report verdict INCOMPLETE'
sed 's/| COMPLETE |$/| INCOMPLETE |/' \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.tmp"
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.tmp" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-05.md"
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.inconclusive-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null

# DUPLICATE must name an existing, non-self canonical record and the known-issue
# ledger must bind the same dedup key to that canonical.
sed \
    -e 's/C-02/C-06/g' \
    -e 's/- Canonical candidate \/ finding: N\/A/- Canonical candidate \/ finding: C-02/' \
    -e 's/- Status: HUMAN-ACCEPTED/- Status: DUPLICATE/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-06.md"
cp "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.duplicate-valid"
sed \
    -e '/^| Candidates dispositioned |/ s/| 1 | 1 | 0 |/| 2 | 2 | 0 |/' \
    -e '/^| Material candidate verdicts |/ s/| 1 | 1 | 0 |/| 2 | 2 | 0 |/' \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.duplicate-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
cp "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-06.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-06.md.canonical-valid"
sed 's/- Canonical candidate \/ finding: C-02/- Canonical candidate \/ finding: C-06/' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-06.md.canonical-valid" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-06.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
expect_triage_failure 'Self-referential duplicate canonical unexpectedly passed.' \
    'DUPLICATE canonical reference cannot point to itself'
mv "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-06.md.canonical-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-06.md"
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-06.md"
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.duplicate-valid" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null

bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo"
}

# A finding cannot link to a candidate that does not exist.
cp "$TMP_ROOT/audit-workspace/evm-demo/findings.md" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md.clean"
cat >> "$TMP_ROOT/audit-workspace/evm-demo/findings.md" <<EOF
## F-99 — Missing Candidate
- Candidate ID / dedup key: C-99 / missing|candidate|link
- Target lock SHA-256: $TARGET_LOCK_HASH
- Target artifact IDs: T-01
- Target locator: contracts/Missing.sol:1
- Reachability chain / evidence: entry -> sink
- Mechanism: complete but phantom candidate link
- Invariant violated: INV-99
- Original severity: High
- Current remediation status: Open
- Current deployment: unknown
- Deployment/state anchor: NOT ASSESSED - missing candidate target
- Evidence verdict: CONFIRMED-LOGIC
- Verification evidence: triage/reproducers/C-99.md
- Independent validation: triage/validation/C-99.md
- Cost versus impact: material
- Human decision: ACCEPTED / human-auditor / 2026-07-13
- Client response: NOT PROVIDED as of 2026-07-13
- Remediation baseline: NOT PROVIDED - finding remains open
- Retest: NOT YET RETESTED - finding remains open
- Residual risk: Full original impact remains
- Disclosure handling: CLIENT-CONFIDENTIAL / human-auditor / 2026-07-13
EOF
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Finding linked to a missing candidate unexpectedly passed triage checks.\n' >&2
    exit 1
fi
mv "$TMP_ROOT/audit-workspace/evm-demo/findings.md.clean" \
    "$TMP_ROOT/audit-workspace/evm-demo/findings.md"

# Acceptance checker must fail closed when a candidate is promoted without a
# complete contract, reproducer, independent validator, and human decision.
sed 's/C-NN/C-01/g' \
    "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/_template.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-01.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
if bash "$SKILL_DIR/scripts/triage-check.sh" \
    "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null 2>&1; then
    printf 'Incomplete candidate unexpectedly passed triage acceptance checks.\n' >&2
    exit 1
fi
rm "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-01.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo"

# A complete producer/validator/human handoff must pass.
# A deployed claim, unlike the no-finding logic fixture above, must bind
# concrete deployment identifiers and deployed code hashes.
for identity_file in scope.md target-lock.md; do
    sed \
        -e 's#^| Deployment / program / package IDs |.*|$#| Deployment / program / package IDs | 0x1111111111111111111111111111111111111111 |#' \
        -e 's#^| Deployed bytecode / package hash |.*|$#| Deployed bytecode / package hash | 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa |#' \
        -e 's#^| Configuration / state anchor |.*|$#| Configuration / state anchor | block=22000000 |#' \
        "$TMP_ROOT/audit-workspace/evm-demo/$identity_file" \
        > "$TMP_ROOT/audit-workspace/evm-demo/$identity_file.tmp"
    mv "$TMP_ROOT/audit-workspace/evm-demo/$identity_file.tmp" \
        "$TMP_ROOT/audit-workspace/evm-demo/$identity_file"
done
TARGET_LOCK_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/target-lock.md")"
cat > "$TMP_ROOT/audit-workspace/evm-demo/triage/candidates/C-02.md" <<EOF
# C-02 — Test Candidate
- Candidate ID: C-02
- Target lock SHA-256: $TARGET_LOCK_HASH
- Target artifact IDs: T-01
- Target component: Vault
- Target revision: commit-abc123
- Deployment / package / program: 0x1111111111111111111111111111111111111111
- Production build / configuration: release optimizer=true
- Threat actor / entry: untrusted caller via deposit(uint256)
- Required actor capabilities: permissionless caller with borrowed capital
- Invariant: assets remain conserved
- Mechanism and reachability evidence: deposit -> W-01 -> S-01
- Claimed impact / success criterion: attacker net gain and vault net loss
- Falsification / control: patched build makes gain assertion fail
- Verification manifest: triage/reproducers/C-02.md
- Dedup key: missing-check|asset-conservation|withdrawal
- Known-issue search: no match in known-issues ledger or prior findings
- Producer: hunter-a
- Producer context / timestamp: codex / 2026-07-13T00:00:00Z
- Source and verification artifact hashes: source=abc evidence=def
- Cost versus impact: 100 USDC capital versus 1000 USDC vault loss
- Potential severity / materiality: High / MATERIAL
- Coverage limitation: N/A
- Canonical candidate / finding: N/A
- Status: HUMAN-ACCEPTED
- Disposition reason / evidence: clean independent replay passed
EOF

mkdir -p "$TMP_ROOT/audit-workspace/evm-demo/poc"
printf 'contract CandidateC02 {}\n' \
    > "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol"
printf 'reproducer pass: attacker +100, vault -100\n' \
    > "$TMP_ROOT/audit-workspace/evm-demo/evidence/C-02.log"
printf 'negative control pass: gain assertion failed on patched build\n' \
    > "$TMP_ROOT/audit-workspace/evm-demo/evidence/C-02-negative.log"
printf 'validator clean replay pass\n' \
    > "$TMP_ROOT/audit-workspace/evm-demo/evidence/C-02-validator.log"

POC_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/poc/C-02.t.sol")"
EVIDENCE_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/evidence/C-02.log")"
NEGATIVE_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/evidence/C-02-negative.log")"
VALIDATION_HASH="$(test_sha256 "$TMP_ROOT/audit-workspace/evm-demo/evidence/C-02-validator.log")"

cat > "$TMP_ROOT/audit-workspace/evm-demo/triage/reproducers/C-02.md" <<EOF
# Verification Manifest — C-02
- Candidate: C-02
- Target lock SHA-256: $TARGET_LOCK_HASH
- Target artifact IDs: T-01
- Target/source revision and artifact hash: commit-abc123 / 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- Production build/profile or target-identity procedure: release optimizer=true / forge build and compare bytecode
- Chain, deployment/configuration, dependencies: ethereum / 0x1111111111111111111111111111111111111111 / block=22000000 / forge-std commit-1
- Evidence verdict: CONFIRMED-DEPLOYED
- Target fidelity: DEPLOYED
- Target fidelity basis: verified bytecode and configuration at the pinned block match the scoped target
- State anchor kind: BLOCK
- State anchor value: 22000000
- Producer context and evidence revision: hunter-a / evidence-def
- Toolchain/OS versions: Foundry 1.0 / Linux Bash 5
- Actor initial conditions and capital/capability acquisition: fresh address / flash loan
- Preconditions checked: vault active and liquid
- Action sequence or proof derivation: deposit -> accounting write -> unauthorized withdrawal
- Evidence method: source-level proof backed by a deterministic regression test
- Primary verification artifact path: poc/C-02.t.sol
- Primary verification artifact SHA-256: $POC_HASH
- Exact command or review procedure: inspect the source derivation; optionally run forge test --match-test test_C_02
- Claimed impact / success criterion: attacker +100 and vault -100
- Primary evidence path: evidence/C-02.log
- Primary evidence SHA-256: $EVIDENCE_HASH
- Falsification / control procedure and expected discriminator: inspect/run patched variant; gain claim must fail
- Falsification / control evidence path: evidence/C-02-negative.log
- Falsification / control evidence SHA-256: $NEGATIVE_HASH
- Production-state deviations: none; exact pinned-state replay
- Repeatability / proof-review result: source proof independently followable; executable companion passed twice
EOF

cat > "$TMP_ROOT/audit-workspace/evm-demo/triage/validation/C-02.md" <<EOF
# Independent Validation — C-02
- Candidate: C-02
- Target lock SHA-256: $TARGET_LOCK_HASH
- Target artifact IDs: T-01
- Validator: validator-b
- Validator context / timestamp: claude / 2026-07-13T01:00:00Z
- Independent from producer: yes
- Independent verification procedure: independently trace source path; optionally forge clean && forge test --match-test test_C_02
- Target identity / production configuration: ethereum / commit-abc123 / 0x1111111111111111111111111111111111111111 / 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa / release optimizer=true / block=22000000
- Independent verification result: PASS — source derivation and executable companion agree
- Evidence verdict: CONFIRMED-DEPLOYED
- Target fidelity verdict: PASS — deployed bytecode, configuration, and block anchor independently matched
- Actor/reachability verdict: PASS — reachable from permissionless deposit
- Impossible-state review: PASS — no direct storage mutation or hidden privilege
- Impact criterion and falsification result: PASS — net gain/loss established; patched build fails
- Dedup disposition: NOVEL — no known root-cause/invariant/sink match
- Actor cost versus impact: 100 USDC versus 1000 USDC loss
- Recommendation: INDEPENDENTLY-VALIDATED
- Decision reason: all gates passed
- Validation evidence path: evidence/C-02-validator.log
- Validation evidence SHA-256: $VALIDATION_HASH
- Human decision / acceptor / date: ACCEPTED / human-auditor / 2026-07-13
EOF

cat >> "$TMP_ROOT/audit-workspace/evm-demo/triage/known-issues.md" <<'EOF'
| missing-check\|asset-conservation\|withdrawal | accepted | C-02 / F-01 | Vault | canonical accepted issue |
EOF

cat >> "$TMP_ROOT/audit-workspace/evm-demo/findings.md" <<EOF
## F-01 — Test Finding
- Candidate ID / dedup key: C-02 / missing-check|asset-conservation|withdrawal
- Target lock SHA-256: $TARGET_LOCK_HASH
- Target artifact IDs: T-01
- Discovery context / classification: optional manual review / access control
- Target locator: contracts/Vault.sol:42
- Reachability chain / evidence: deposit -> W-01 -> S-01
- Mechanism: permissionless deposit bypasses the conservation check
- Invariant violated: INV-1 assets remain conserved
- Original severity: High
- Current remediation status: Open
- Current deployment: confirmed exploitable
- Deployment/state anchor: ethereum Vault deployment at block 22000000 / block hash 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- Evidence verdict: CONFIRMED-DEPLOYED
- Verification evidence: triage/reproducers/C-02.md
- Independent validation: triage/validation/C-02.md
- Cost versus impact: 100 USDC versus 1000 USDC loss
- Human decision: ACCEPTED / human-auditor / 2026-07-13
- Client response: NOT PROVIDED as of 2026-07-13
- Remediation baseline: NOT PROVIDED - finding remains open
- Retest: NOT YET RETESTED - finding remains open
- Residual risk: Full original impact remains
- Disclosure handling: CLIENT-CONFIDENTIAL / human-auditor / 2026-07-13
EOF

sed \
    -e '/^| Candidates dispositioned |/ s/| 0 | 0 | 0 |/| 1 | 1 | 0 |/' \
    -e '/^| Candidates with verification evidence |/ s/| 0 | 0 | 0 |/| 1 | 1 | 0 |/' \
    -e '/^| Independent validations |/ s/| 0 | 0 | 0 |/| 1 | 1 | 0 |/' \
    -e '/^| Material candidate verdicts |/ s/| 0 | 0 | 0 |/| 1 | 1 | 0 |/' \
    -e '/^| Human-accepted findings |/ s/| 0 | 0 | 0 |/| 1 | 1 | 0 |/' \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md" \
    > "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.tmp"
mv "$TMP_ROOT/audit-workspace/evm-demo/coverage.md.tmp" \
    "$TMP_ROOT/audit-workspace/evm-demo/coverage.md"

bash "$SKILL_DIR/scripts/triage-index.sh" "$TMP_ROOT/audit-workspace/evm-demo" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" "$TMP_ROOT/audit-workspace/evm-demo"
run_adversarial_triage_tests

# ---------------------------------------------------------------------------
# Proof is the findings gate; human sign-off is the report gate; integrity
# digests are optional for internal review.
# ---------------------------------------------------------------------------
DEMO_WS="$TMP_ROOT/audit-workspace/evm-demo"

expect_gate_failure() {
    gate_message="$1"
    gate_expected="$2"
    shift 2
    gate_log="$TMP_ROOT/gate-failure.log"
    if bash "$SKILL_DIR/scripts/triage-check.sh" "$@" "$DEMO_WS" >"$gate_log" 2>&1; then
        printf '%s\n' "$gate_message" >&2
        exit 1
    fi
    if ! grep -Fq -e "$gate_expected" "$gate_log"; then
        printf '%s Expected error containing: %s\n' "$gate_message" "$gate_expected" >&2
        sed -n '1,80p' "$gate_log" >&2
        exit 1
    fi
}

# The signed fixture must satisfy the report gate as-is.
bash "$SKILL_DIR/scripts/triage-check.sh" --report "$DEMO_WS" >/dev/null

# An independently validated finding with no signed decision is a legitimate
# findings.md entry: it closes on evidence and blocks only reporting.
for signed_file in triage/candidates/C-02.md triage/validation/C-02.md findings.md; do
    cp "$DEMO_WS/$signed_file" "$DEMO_WS/$signed_file.signed"
done
sed 's/^- Status: HUMAN-ACCEPTED$/- Status: INDEPENDENTLY-VALIDATED/' \
    "$DEMO_WS/triage/candidates/C-02.md.signed" > "$DEMO_WS/triage/candidates/C-02.md"
sed 's#^- Human decision / acceptor / date:.*#- Human decision / acceptor / date: TBD#' \
    "$DEMO_WS/triage/validation/C-02.md.signed" > "$DEMO_WS/triage/validation/C-02.md"
sed '/^- Human decision:/d' "$DEMO_WS/findings.md.signed" > "$DEMO_WS/findings.md"
bash "$SKILL_DIR/scripts/triage-index.sh" "$DEMO_WS" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" "$DEMO_WS" >/dev/null
expect_gate_failure 'Unsigned finding unexpectedly passed the report gate.' \
    'requires linked candidate C-02 to be HUMAN-ACCEPTED' --report
for signed_file in triage/candidates/C-02.md triage/validation/C-02.md findings.md; do
    mv "$DEMO_WS/$signed_file.signed" "$DEMO_WS/$signed_file"
done
bash "$SKILL_DIR/scripts/triage-index.sh" "$DEMO_WS" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" --report "$DEMO_WS" >/dev/null

# A workspace that records no integrity digest at all still closes on proof;
# --strict-hashes is the opt-in for delivery-grade integrity binding.
for hashless_file in scope.md target-lock.md triage/candidates/C-02.md \
    triage/reproducers/C-02.md triage/validation/C-02.md findings.md; do
    cp "$DEMO_WS/$hashless_file" "$DEMO_WS/$hashless_file.hashed"
done
for identity_file in scope.md target-lock.md; do
    sed 's#^| Deployed bytecode / package hash |.*|$#| Deployed bytecode / package hash | N/A |#' \
        "$DEMO_WS/$identity_file.hashed" > "$DEMO_WS/$identity_file"
done
sed 's#^| T-01 | contracts/Vault.sol | [0-9a-f]* |#| T-01 | contracts/Vault.sol | N/A |#' \
    "$DEMO_WS/target-lock.md" > "$DEMO_WS/target-lock.md.tmp"
mv "$DEMO_WS/target-lock.md.tmp" "$DEMO_WS/target-lock.md"
grep -Fq '| T-01 | contracts/Vault.sol | N/A |' "$DEMO_WS/target-lock.md"
for hashless_file in triage/candidates/C-02.md triage/reproducers/C-02.md \
    triage/validation/C-02.md findings.md; do
    sed \
        -e 's#^- Target lock SHA-256:.*#- Target lock SHA-256: N/A#' \
        -e 's#^- Source and verification artifact hashes:.*#- Source and verification artifact hashes: N/A#' \
        -e 's#^- Primary verification artifact SHA-256:.*#- Primary verification artifact SHA-256: N/A#' \
        -e 's#^- Primary evidence SHA-256:.*#- Primary evidence SHA-256: N/A#' \
        -e 's#^- Falsification / control evidence SHA-256:.*#- Falsification / control evidence SHA-256: N/A#' \
        -e 's#^- Validation evidence SHA-256:.*#- Validation evidence SHA-256: N/A#' \
        "$DEMO_WS/$hashless_file.hashed" > "$DEMO_WS/$hashless_file"
done
bash "$SKILL_DIR/scripts/triage-index.sh" "$DEMO_WS" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" "$DEMO_WS" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" --report "$DEMO_WS" >/dev/null
expect_gate_failure 'Digest-free workspace unexpectedly passed --strict-hashes.' \
    '--strict-hashes requires' --strict-hashes

# Dropping the digest never drops the proof: the referenced artifact must still
# resolve to a retained non-empty workspace file.
cp "$DEMO_WS/triage/reproducers/C-02.md" "$DEMO_WS/triage/reproducers/C-02.md.resolvable"
sed 's#^- Primary evidence path:.*#- Primary evidence path: evidence/C-02-absent.log#' \
    "$DEMO_WS/triage/reproducers/C-02.md.resolvable" > "$DEMO_WS/triage/reproducers/C-02.md"
expect_gate_failure 'Unresolvable digest-free evidence path unexpectedly passed.' \
    "does not resolve to a non-empty file"
mv "$DEMO_WS/triage/reproducers/C-02.md.resolvable" "$DEMO_WS/triage/reproducers/C-02.md"

# A recorded digest is still verified even when digests are optional.
cp "$DEMO_WS/triage/reproducers/C-02.md" "$DEMO_WS/triage/reproducers/C-02.md.optional"
sed 's#^- Primary evidence SHA-256:.*#- Primary evidence SHA-256: 0000000000000000000000000000000000000000000000000000000000000000#' \
    "$DEMO_WS/triage/reproducers/C-02.md.optional" > "$DEMO_WS/triage/reproducers/C-02.md"
expect_gate_failure 'Mismatched optional digest unexpectedly passed.' \
    "'Primary evidence SHA-256' does not match"
sed 's#^- Primary evidence SHA-256:.*#- Primary evidence SHA-256: not-a-digest#' \
    "$DEMO_WS/triage/reproducers/C-02.md.optional" > "$DEMO_WS/triage/reproducers/C-02.md"
expect_gate_failure 'Free-text stand-in for a digest unexpectedly passed.' \
    'must be a 64-hex SHA-256 or an explicit N/A'
mv "$DEMO_WS/triage/reproducers/C-02.md.optional" "$DEMO_WS/triage/reproducers/C-02.md"

for hashless_file in scope.md target-lock.md triage/candidates/C-02.md \
    triage/reproducers/C-02.md triage/validation/C-02.md findings.md; do
    mv "$DEMO_WS/$hashless_file.hashed" "$DEMO_WS/$hashless_file"
done
bash "$SKILL_DIR/scripts/triage-index.sh" "$DEMO_WS" >/dev/null
bash "$SKILL_DIR/scripts/triage-check.sh" --report --strict-hashes "$DEMO_WS" >/dev/null

# The canonical closure row is "Findings recorded"; the pre-sign-off-gate name
# stays valid, but exactly one of them must be present.
cp "$DEMO_WS/coverage.md" "$DEMO_WS/coverage.md.legacy-row"
sed 's/^| Human-accepted findings |/| Findings recorded |/' \
    "$DEMO_WS/coverage.md.legacy-row" > "$DEMO_WS/coverage.md"
bash "$SKILL_DIR/scripts/triage-check.sh" "$DEMO_WS" >/dev/null
awk '{ print } /^\| Findings recorded \|/ { print "| Human-accepted findings | 1 | 1 | 0 | duplicate row |" }' \
    "$DEMO_WS/coverage.md" > "$DEMO_WS/coverage.md.tmp"
mv "$DEMO_WS/coverage.md.tmp" "$DEMO_WS/coverage.md"
expect_gate_failure 'Duplicate findings-closure rows unexpectedly passed.' \
    'exactly one findings row'
mv "$DEMO_WS/coverage.md.legacy-row" "$DEMO_WS/coverage.md"
bash "$SKILL_DIR/scripts/triage-check.sh" "$DEMO_WS" >/dev/null

if (cd "$TMP_ROOT" && bash "$SKILL_DIR/scripts/init-workspace.sh" aptos-demo aptos >/dev/null 2>&1); then
    printf 'Aptos fail-closed check unexpectedly succeeded.\n' >&2
    exit 1
fi
test ! -e "$TMP_ROOT/audit-workspace/aptos-demo"

bash "$SKILL_DIR/scripts/atlas-inventory.sh" \
    "$SKILL_DIR/templates/simulation" "$TMP_ROOT/atlas"
printf '\nmanual-atlas-enrichment\n' >> "$TMP_ROOT/atlas/sinks.md"
bash "$SKILL_DIR/scripts/atlas-inventory.sh" \
    "$SKILL_DIR/templates/simulation" "$TMP_ROOT/atlas" >/dev/null
grep -R -Fq 'manual-atlas-enrichment' "$TMP_ROOT/tmp/atlas-inventory"
mkdir -p "$TMP_ROOT/atlas-edge-source"
cat > "$TMP_ROOT/atlas-edge-source/NativeSinks.sol" <<'EOF'
pragma solidity ^0.8.20;
contract NativeSinks {
    function sinks(address payable receiver, address vault, uint256 amount) external {
        Address.sendValue(receiver, amount);
        (bool ok,) = vault.call{value: amount}("");
        require(ok);
        selfdestruct(receiver);
    }
}
EOF
bash "$SKILL_DIR/scripts/atlas-inventory.sh" \
    "$TMP_ROOT/atlas-edge-source" "$TMP_ROOT/atlas-edge" >/dev/null
grep -Fq 'Native value helper' "$TMP_ROOT/atlas-edge/sinks.md"
grep -Fq 'Native value call' "$TMP_ROOT/atlas-edge/sinks.md"
grep -Fq 'SELFDESTRUCT value send' "$TMP_ROOT/atlas-edge/sinks.md"
mkdir -p "$TMP_ROOT/compiler"
bash "$SKILL_DIR/scripts/check-compiler.sh" \
    "$SKILL_DIR/templates/simulation" "$TMP_ROOT/compiler"
printf '\ncompiler-retention-marker\n' >> "$TMP_ROOT/compiler/compiler-check.md"
bash "$SKILL_DIR/scripts/check-compiler.sh" \
    "$SKILL_DIR/templates/simulation" "$TMP_ROOT/compiler" >/dev/null
grep -R -Fq 'compiler-retention-marker' "$TMP_ROOT/compiler/tmp/check-compiler"

test -s "$TMP_ROOT/atlas/sinks.md"
test -s "$TMP_ROOT/atlas/gates.md"
test -s "$TMP_ROOT/atlas/writes.md"
test -s "$TMP_ROOT/compiler/compiler-check.md"

printf 'Skill smoke tests passed.\n'
