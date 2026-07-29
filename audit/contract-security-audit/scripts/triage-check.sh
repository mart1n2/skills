#!/usr/bin/env bash
# Validate the contract-security-audit triage contract.
# Portable across Apple Bash 3.2 and Linux Bash; invoke explicitly with bash.

set -euo pipefail

MODE="final"
if [ "${1:-}" = "--bootstrap" ]; then
    MODE="bootstrap"
    shift
fi
WORKSPACE="${1:?Usage: triage-check.sh [--bootstrap] <audit-workspace/protocol>}"

failures=0
TMP_CHECK="$(mktemp -d "${TMPDIR:-/tmp}/contract-audit-triage.XXXXXX")"
trap 'rm -rf "$TMP_CHECK"' EXIT HUP INT TERM
ACCEPTED_KEYS="$TMP_CHECK/accepted-keys.tsv"
: > "$ACCEPTED_KEYS"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    failures=$((failures + 1))
}

field_value() {
    file="$1"
    field="$2"
    awk -v prefix="- $field:" '
        index($0, prefix) == 1 {
            value = substr($0, length(prefix) + 1)
            sub(/^[ \t]*/, "", value)
            print value
            exit
        }
    ' "$file"
}

table_field_value() {
    file="$1"
    field="$2"
    awk -F '|' -v wanted="$field" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        trim($2) == wanted { print trim($3); exit }
    ' "$file"
}

is_unset() {
    value="$1"
    case "$value" in
        ""|'?'|none|NONE|TBD|tbd|TBD\ *|tbd\ *|unknown|UNKNOWN|unknown\ *|UNKNOWN\ *|C-NN|*'<'*'>'*) return 0 ;;
        *) return 1 ;;
    esac
}

is_non_substantive() {
    value="$1"
    case "$value" in
        N/A|n/a|NA|na|none|NONE|'?') return 0 ;;
        *) return 1 ;;
    esac
}

require_field() {
    file="$1"
    field="$2"
    field_count="$(awk -v prefix="- $field:" 'index($0, prefix) == 1 { count++ } END { print count + 0 }' "$file")"
    if [ "$field_count" -ne 1 ]; then
        fail "$file: field '$field' must appear exactly once (found $field_count)"
        return
    fi
    value="$(field_value "$file" "$field")"
    if is_unset "$value"; then
        fail "$file: missing or placeholder field '$field'"
    fi
}

require_substantive_field() {
    file="$1"
    field="$2"
    field_count="$(awk -v prefix="- $field:" 'index($0, prefix) == 1 { count++ } END { print count + 0 }' "$file")"
    if [ "$field_count" -ne 1 ]; then
        fail "$file: substantive field '$field' must appear exactly once (found $field_count)"
        return
    fi
    value="$(field_value "$file" "$field")"
    if is_unset "$value" || is_non_substantive "$value"; then
        fail "$file: missing, placeholder, or non-substantive field '$field'"
    fi
}

require_table_field() {
    file="$1"
    field="$2"
    field_count="$(awk -F '|' -v wanted="$field" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        trim($2) == wanted { count++ }
        END { print count + 0 }
    ' "$file")"
    if [ "$field_count" -ne 1 ]; then
        fail "$file: scope field '$field' must appear exactly once (found $field_count)"
        return
    fi
    value="$(table_field_value "$file" "$field")"
    if is_unset "$value"; then
        fail "$file: missing or placeholder scope field '$field'"
    fi
}

require_table_row() {
    file="$1"
    field="$2"
    field_count="$(awk -F '|' -v wanted="$field" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        trim($2) == wanted { count++ }
        END { print count + 0 }
    ' "$file")"
    if [ "$field_count" -ne 1 ]; then
        fail "$file: scope field '$field' must appear exactly once (found $field_count)"
    fi
}

require_table_substantive_field() {
    file="$1"
    field="$2"
    require_table_field "$file" "$field"
    value="$(table_field_value "$file" "$field")"
    if is_non_substantive "$value"; then
        fail "$file: scope field '$field' cannot be N/A/none/? in final mode"
    fi
}

sha256_file() {
    path="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    else
        return 1
    fi
}

validate_target_id_value() {
    target_list_context="$1"
    target_list_value="$2"
    if ! printf '%s\n' "$target_list_value" | grep -Eq '^T-[0-9]+(,T-[0-9]+)*$'; then
        fail "$target_list_context: target artifact IDs must be a canonical comma-separated T-NN list with no spaces"
        return
    fi
    duplicate_target_id="$(printf '%s\n' "$target_list_value" | awk -F ',' '
        { for (i = 1; i <= NF; i++) if (++seen[$i] == 2) { print $i; exit } }
    ')"
    if [ -n "$duplicate_target_id" ]; then
        fail "$target_list_context: target artifact IDs repeat $duplicate_target_id"
    fi
    while IFS= read -r listed_target_id; do
        [ -n "$listed_target_id" ] || continue
        if ! grep -Fqx "$listed_target_id" "$TARGET_IDS"; then
            fail "$target_list_context: target artifact IDs reference unknown $listed_target_id"
        fi
    done < <(printf '%s\n' "$target_list_value" | tr ',' '\n')
}

validate_target_id_list() {
    target_list_file="$1"
    target_list_field="$2"
    validate_target_id_value "$target_list_file: '$target_list_field'" \
        "$(field_value "$target_list_file" "$target_list_field")"
}

validate_deployed_identity_format() {
    deployed_chain="$1"
    deployed_ids="$2"
    deployed_hash="$3"

    case "$deployed_chain" in
        solana)
            if ! printf '%s\n' "$deployed_ids" | grep -Eq '(^|[^1-9A-HJ-NP-Za-km-z])[1-9A-HJ-NP-Za-km-z]{32,44}([^1-9A-HJ-NP-Za-km-z]|$)'; then
                fail "$WORKSPACE/target-lock.md: CONFIRMED-DEPLOYED Solana identity requires a base58 program ID"
            fi
            if ! printf '%s\n' "$deployed_hash" | grep -Eq '(^|[^[:alnum:]])((0x)?[0-9a-fA-F]{64}|[1-9A-HJ-NP-Za-km-z]{32,64})([^[:alnum:]]|$)'; then
                fail "$WORKSPACE/target-lock.md: CONFIRMED-DEPLOYED Solana identity requires a structured deployed binary/package digest"
            fi
            ;;
        sui)
            if ! printf '%s\n' "$deployed_ids" | grep -Eq '(^|[^[:xdigit:]])0x[0-9a-fA-F]{1,64}([^[:xdigit:]]|$)'; then
                fail "$WORKSPACE/target-lock.md: CONFIRMED-DEPLOYED Sui identity requires a hexadecimal package ID"
            fi
            if ! printf '%s\n' "$deployed_hash" | grep -Eq '(^|[^[:alnum:]])((0x)?[0-9a-fA-F]{64}|[1-9A-HJ-NP-Za-km-z]{32,64})([^[:alnum:]]|$)'; then
                fail "$WORKSPACE/target-lock.md: CONFIRMED-DEPLOYED Sui identity requires a structured package/object digest"
            fi
            ;;
        *)
            if ! printf '%s\n' "$deployed_ids" | grep -Eq '(^|[^[:xdigit:]])0x[0-9a-fA-F]{40}([^[:xdigit:]]|$)'; then
                fail "$WORKSPACE/target-lock.md: CONFIRMED-DEPLOYED EVM identity requires a 20-byte deployment address"
            fi
            if ! printf '%s\n' "$deployed_hash" | grep -Eq '(^|[^[:xdigit:]])0x[0-9a-fA-F]{64}([^[:xdigit:]]|$)'; then
                fail "$WORKSPACE/target-lock.md: CONFIRMED-DEPLOYED EVM identity requires a 32-byte deployed code hash"
            fi
            ;;
    esac
}

normalize_actor() {
    printf '%s\n' "$1" | awk '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print tolower($0) }'
}

ledger_contains_key() {
    key="$1"
    escaped_key="$(printf '%s\n' "$key" | sed 's/|/\\|/g')"
    grep -Fq "| $escaped_key |" "$WORKSPACE/triage/known-issues.md"
}

ledger_contains_key_and_canonical() {
    ledger_key="$1"
    ledger_canonical="$2"
    escaped_ledger_key="$(printf '%s\n' "$ledger_key" | sed 's/|/\\|/g')"
    grep -F "| $escaped_ledger_key |" "$WORKSPACE/triage/known-issues.md" | \
        grep -Eq "(^|[^[:alnum:]-])$ledger_canonical([^[:alnum:]-]|$)"
}

workspace_path_has_symlink() {
    relative_path="$1"
    path_cursor="$WORKSPACE"
    if [ -L "$path_cursor" ]; then
        return 0
    fi
    while IFS= read -r path_component; do
        [ -n "$path_component" ] || continue
        [ "$path_component" = "." ] && continue
        path_cursor="$path_cursor/$path_component"
        if [ -L "$path_cursor" ]; then
            return 0
        fi
    done < <(printf '%s\n' "$relative_path" | awk -F '/' '{ for (i = 1; i <= NF; i++) print $i }')
    return 1
}

verify_workspace_artifact() {
    manifest="$1"
    path_field="$2"
    hash_field="$3"
    relative_path="$(field_value "$manifest" "$path_field")"
    expected_hash="$(field_value "$manifest" "$hash_field" | tr '[:upper:]' '[:lower:]')"

    if is_unset "$relative_path" || is_unset "$expected_hash"; then
        return
    fi
    verify_workspace_artifact_values \
        "$manifest" "$path_field" "$hash_field" "$relative_path" "$expected_hash"
}

verify_workspace_artifact_values() {
    artifact_context="$1"
    path_label="$2"
    hash_label="$3"
    relative_path="$4"
    expected_hash="$(printf '%s' "$5" | tr '[:upper:]' '[:lower:]')"

    case "$relative_path" in
        /*|../*|*/../*)
            fail "$artifact_context: '$path_label' must stay inside the audit workspace"
            return
            ;;
    esac
    artifact="$WORKSPACE/$relative_path"

    # Ban symlinks in evidence paths. Lexical ../ checks are insufficient when
    # a workspace-local link resolves to an external mutable artifact.
    if workspace_path_has_symlink "$relative_path"; then
        fail "$artifact_context: '$path_label' traverses a symlink"
        return
    fi

    if [ ! -s "$artifact" ]; then
        fail "$artifact_context: '$path_label' does not resolve to a non-empty file: $artifact"
        return
    fi
    actual_hash="$(sha256_file "$artifact" || true)"
    if [ -z "$actual_hash" ]; then
        fail "$artifact_context: no SHA-256 implementation available"
    elif [ "$actual_hash" != "$expected_hash" ]; then
        fail "$artifact_context: '$hash_label' does not match $relative_path"
    fi
}

structured_field_value() {
    structured_record="$1"
    structured_key="$2"
    printf '%s\n' "$structured_record" | awk -F ';' -v wanted="$structured_key" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        {
            for (i = 1; i <= NF; i++) {
                part = trim($i)
                prefix = wanted "="
                if (index(part, prefix) == 1) {
                    print trim(substr(part, length(prefix) + 1))
                    exit
                }
            }
        }
    '
}

is_valid_iso_date() {
    iso_date="$1"
    if ! printf '%s\n' "$iso_date" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        return 1
    fi
    iso_year="${iso_date%%-*}"
    iso_rest="${iso_date#*-}"
    iso_month="${iso_rest%%-*}"
    iso_day="${iso_rest##*-}"
    awk -v year="$iso_year" -v month="$iso_month" -v day="$iso_day" '
        BEGIN {
            year += 0; month += 0; day += 0
            days[1]=31; days[2]=28; days[3]=31; days[4]=30; days[5]=31; days[6]=30
            days[7]=31; days[8]=31; days[9]=30; days[10]=31; days[11]=30; days[12]=31
            if ((year % 400 == 0) || (year % 4 == 0 && year % 100 != 0)) days[2]=29
            exit !(month >= 1 && month <= 12 && day >= 1 && day <= days[month])
        }
    '
}

is_valid_revision_descriptor() {
    revision_descriptor="$1"
    revision_kind="${revision_descriptor%%:*}"
    revision_id="${revision_descriptor#*:}"
    [ "$revision_kind" != "$revision_descriptor" ] || return 1
    case "$revision_kind" in
        git|artifact-sha256|evm-bytecode|solana-programdata|sui-package|package|program|bytecode|deployment) ;;
        *) return 1 ;;
    esac
    case "$revision_id" in
        ""|*[!A-Za-z0-9._:@+-]*) return 1 ;;
    esac
    [ "${#revision_id}" -ge 16 ] || return 1
    if [ "$revision_kind" = "git" ]; then
        printf '%s\n' "$revision_id" | grep -Eq '^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$'
    fi
}

for required in \
    "$WORKSPACE/README.md" \
    "$WORKSPACE/scope.md" \
    "$WORKSPACE/target-lock.md" \
    "$WORKSPACE/findings.md" \
    "$WORKSPACE/coverage.md" \
    "$WORKSPACE/contracts" \
    "$WORKSPACE/evidence" \
    "$WORKSPACE/tmp" \
    "$WORKSPACE/reports" \
    "$WORKSPACE/triage" \
    "$WORKSPACE/triage/candidates.md" \
    "$WORKSPACE/triage/known-issues.md" \
    "$WORKSPACE/triage/candidates" \
    "$WORKSPACE/triage/reproducers" \
    "$WORKSPACE/triage/validation"; do
    if [ ! -e "$required" ]; then
        fail "required triage artifact missing: $required"
    fi
done

# Canonical audit and triage artifacts must not traverse mutable external
# symlinks. Abort before any parser follows an unsafe parent directory.
unsafe_structure=0
for relative in \
    README.md \
    scope.md \
    target-lock.md \
    findings.md \
    coverage.md \
    contracts \
    evidence \
    tmp \
    reports \
    triage \
    triage/candidates.md \
    triage/known-issues.md \
    triage/candidates \
    triage/reproducers \
    triage/validation; do
    if workspace_path_has_symlink "$relative"; then
        fail "$WORKSPACE/$relative: canonical workspace path must not traverse a symlink"
        unsafe_structure=1
    fi
done
for relative in orientation.md model.md poc atlas; do
    if [ -e "$WORKSPACE/$relative" ] && workspace_path_has_symlink "$relative"; then
        fail "$WORKSPACE/$relative: optional workspace path must not traverse a symlink"
        unsafe_structure=1
    fi
done
if [ "$unsafe_structure" -ne 0 ]; then
    printf 'Triage check aborted because canonical workspace structure is unsafe.\n' >&2
    exit 1
fi

if [ ! -f "$WORKSPACE/findings.md" ]; then
    exit 1
fi

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_LOCK_SHA256="$(sha256_file "$WORKSPACE/target-lock.md" || true)"
if [ -z "$TARGET_LOCK_SHA256" ]; then
    fail "$WORKSPACE/target-lock.md: cannot compute canonical target-lock SHA-256"
fi
if ! bash "$SKILL_DIR/scripts/triage-index.sh" --check "$WORKSPACE" >/dev/null; then
    fail "$WORKSPACE/triage/candidates.md: generated candidate index is stale"
fi

if [ "$MODE" = "final" ]; then
    for field in \
        "Protocol" \
        "Chain" \
        "Source repository / package" \
        "Source revision" \
        "Production build/profile or target-identity procedure" \
        "Compiler / toolchain" \
        "Configuration / state anchor"; do
        require_table_substantive_field "$WORKSPACE/scope.md" "$field"
        require_table_substantive_field "$WORKSPACE/target-lock.md" "$field"
    done
    for field in \
        "Deployment / program / package IDs" \
        "Deployed bytecode / package hash"; do
        # Logic/reconstruction audits may have no deployment. The rows must be
        # present and explicitly say N/A; deployed claims are tightened below.
        require_table_row "$WORKSPACE/scope.md" "$field"
        require_table_row "$WORKSPACE/target-lock.md" "$field"
    done

    for field in \
        "Protocol" \
        "Chain" \
        "Source repository / package" \
        "Source revision" \
        "Deployment / program / package IDs" \
        "Deployed bytecode / package hash" \
        "Production build/profile or target-identity procedure" \
        "Compiler / toolchain" \
        "Configuration / state anchor"; do
        scope_identity_value="$(table_field_value "$WORKSPACE/scope.md" "$field")"
        lock_identity_value="$(table_field_value "$WORKSPACE/target-lock.md" "$field")"
        if [ "$scope_identity_value" != "$lock_identity_value" ]; then
            fail "$WORKSPACE/target-lock.md: target identity field '$field' must exactly match scope.md"
        fi
    done

    TARGET_PROTOCOL="$(table_field_value "$WORKSPACE/target-lock.md" "Protocol")"
    TARGET_CHAIN="$(table_field_value "$WORKSPACE/target-lock.md" "Chain")"
    TARGET_SOURCE_REPOSITORY="$(table_field_value "$WORKSPACE/target-lock.md" "Source repository / package")"
    TARGET_SOURCE_REVISION="$(table_field_value "$WORKSPACE/target-lock.md" "Source revision")"
    TARGET_DEPLOYMENT="$(table_field_value "$WORKSPACE/target-lock.md" "Deployment / program / package IDs")"
    TARGET_DEPLOYED_HASH="$(table_field_value "$WORKSPACE/target-lock.md" "Deployed bytecode / package hash")"
    TARGET_BUILD="$(table_field_value "$WORKSPACE/target-lock.md" "Production build/profile or target-identity procedure")"
    TARGET_COMPILER="$(table_field_value "$WORKSPACE/target-lock.md" "Compiler / toolchain")"
    TARGET_CONFIGURATION="$(table_field_value "$WORKSPACE/target-lock.md" "Configuration / state anchor")"

    TARGET_ROWS="$TMP_CHECK/target-artifacts.tsv"
    if ! awk -F '|' '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        /^##[[:space:]]+Target Artifact Manifest[[:space:]]*$/ { in_targets = 1; next }
        in_targets && /^##[[:space:]]/ { in_targets = 0 }
        in_targets && /^\|/ {
            if (NF != 6) {
                printf "target artifact manifest row has %d columns instead of 4: %s\n", NF - 2, $0 > "/dev/stderr"
                errors++
                next
            }
            id = trim($2)
            path = trim($3)
            digest = trim($4)
            role = trim($5)
            if (id == "" || id == "Target ID" || id ~ /^-+$/) next
            print id "\t" path "\t" digest "\t" role
            rows++
        }
        END {
            if (rows == 0) {
                print "target artifact manifest is missing or empty" > "/dev/stderr"
                errors++
            }
            if (errors) exit 1
        }
    ' "$WORKSPACE/target-lock.md" > "$TARGET_ROWS"; then
        fail "$WORKSPACE/target-lock.md: target artifact manifest validation failed"
    fi

    TARGET_IDS="$TMP_CHECK/target-ids.txt"
    TARGET_PATHS="$TMP_CHECK/target-paths.txt"
    : > "$TARGET_IDS"
    : > "$TARGET_PATHS"
    actual_scope_files=0
    while IFS="$(printf '\t')" read -r target_id target_path target_hash target_role; do
        [ -n "$target_id" ] || continue
        actual_scope_files=$((actual_scope_files + 1))
        if ! printf '%s\n' "$target_id" | grep -Eq '^T-[0-9]+$'; then
            fail "$WORKSPACE/target-lock.md: target artifact ID must use exact T-NN grammar: $target_id"
        elif grep -Fqx "$target_id" "$TARGET_IDS"; then
            fail "$WORKSPACE/target-lock.md: duplicate target artifact ID: $target_id"
        fi
        printf '%s\n' "$target_id" >> "$TARGET_IDS"

        if is_unset "$target_path" || is_non_substantive "$target_path"; then
            fail "$WORKSPACE/target-lock.md: $target_id has a missing or non-substantive workspace path"
            continue
        fi
        case "$target_path" in
            contracts/*) ;;
            *)
                fail "$WORKSPACE/target-lock.md: $target_id path must be workspace-relative under contracts/: $target_path"
                continue
                ;;
        esac
        case "$target_path" in
            /*|../*|*/../*)
                fail "$WORKSPACE/target-lock.md: $target_id path must stay inside contracts/: $target_path"
                continue
                ;;
        esac
        if grep -Fqx "$target_path" "$TARGET_PATHS"; then
            fail "$WORKSPACE/target-lock.md: duplicate target artifact path: $target_path"
        fi
        printf '%s\n' "$target_path" >> "$TARGET_PATHS"
        if workspace_path_has_symlink "$target_path"; then
            fail "$WORKSPACE/$target_path: target artifact path must not traverse a symlink"
            continue
        fi
        if [ ! -f "$WORKSPACE/$target_path" ] || [ -L "$WORKSPACE/$target_path" ]; then
            fail "$WORKSPACE/target-lock.md: $target_id does not resolve to a regular target artifact: $target_path"
            continue
        fi
        normalized_target_hash="$(printf '%s\n' "$target_hash" | tr '[:upper:]' '[:lower:]')"
        if ! printf '%s\n' "$normalized_target_hash" | grep -Eq '^[0-9a-f]{64}$'; then
            fail "$WORKSPACE/target-lock.md: $target_id requires an exact SHA-256 digest"
        else
            actual_target_hash="$(sha256_file "$WORKSPACE/$target_path" || true)"
            if [ "$actual_target_hash" != "$normalized_target_hash" ]; then
                fail "$WORKSPACE/target-lock.md: $target_id SHA-256 does not match $target_path"
            fi
        fi
        if is_unset "$target_role" || is_non_substantive "$target_role"; then
            fail "$WORKSPACE/target-lock.md: $target_id requires a substantive role / scope significance"
        fi
    done < "$TARGET_ROWS"

    actual_candidates="$(find "$WORKSPACE/triage/candidates" \( -type f -o -type l \) -name 'C-*.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
    actual_verification="$(find "$WORKSPACE/triage/reproducers" \( -type f -o -type l \) -name 'C-*.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
    actual_validations="$(find "$WORKSPACE/triage/validation" \( -type f -o -type l \) -name 'C-*.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
    actual_material_candidates="$(find "$WORKSPACE/triage/candidates" -type f -name 'C-*.md' -exec grep -El '^- Potential severity / materiality:[[:space:]].*[[:space:]]/[[:space:]]*MATERIAL[[:space:]]*$' {} + 2>/dev/null | wc -l | tr -d '[:space:]' || true)"
    actual_findings="$(grep -Ec '^##[[:space:]]+F-[0-9]+([[:space:]]+.*)?$' "$WORKSPACE/findings.md" || true)"

    if [ "$actual_scope_files" -eq 0 ]; then
        fail "$WORKSPACE/contracts: final audit requires at least one pinned source or target artifact"
    fi
    while IFS= read -r linked_target; do
        [ -n "$linked_target" ] || continue
        fail "$linked_target: in-scope target artifacts must be regular workspace files, not symlinks"
    done < <(find "$WORKSPACE/contracts" -type l -print 2>/dev/null | LC_ALL=C sort)

    if ! awk -F '|' \
        -v actual_scope_files="$actual_scope_files" \
        -v actual_candidates="$actual_candidates" \
        -v actual_verification="$actual_verification" \
        -v actual_validations="$actual_validations" \
        -v actual_material_candidates="$actual_material_candidates" \
        -v actual_findings="$actual_findings" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        function invalid_evidence(value, lower) {
            lower = tolower(trim(value))
            return lower == "" || lower == "?" ||
                   lower ~ /^(tbd|unknown)([[:space:]:-]|$)/ ||
                   lower ~ /^(n\/a|none)([[:space:]:-]|$)/ ||
                   lower ~ /<[^>]*>/
        }
        function require_surface(name) { required[name] = 1 }
        function reconcile(surface, actual) {
            if (expected != actual || reviewed != actual || open != 0) {
                printf "coverage row %s must reconcile to actual artifact count %d as Expected=%d Reviewed=%d Open=0\n", surface, actual, actual, actual > "/dev/stderr"
                errors++
            }
        }
        BEGIN {
            require_surface("In-scope target artifacts")
            require_surface("Candidates dispositioned")
            require_surface("Candidates with verification evidence")
            require_surface("Independent validations")
            require_surface("Material candidate verdicts")
            require_surface("Human-accepted findings")
        }
        /^##[[:space:]]+Objective Artifact Reconciliation[[:space:]]*$/ { in_coverage = 1; next }
        in_coverage && /^##[[:space:]]/ { in_coverage = 0 }
        in_coverage && /^\|/ {
            surface = trim($2)
            expected = trim($3)
            reviewed = trim($4)
            open = trim($5)
            evidence = trim($6)
            if (surface == "" || surface == "Artifact class" || surface ~ /^-+$/) next
            rows++
            seen[surface]++
            if (seen[surface] > 1) {
                printf "coverage surface %s appears more than once\n", surface > "/dev/stderr"
                errors++
            }
            if (expected !~ /^[0-9]+$/ || reviewed !~ /^[0-9]+$/ || open !~ /^[0-9]+$/) {
                printf "coverage row %s requires numeric Expected/Reviewed/Open counts\n", surface > "/dev/stderr"
                errors++
                next
            }
            if ((reviewed + open) != expected) {
                printf "coverage row %s must satisfy Reviewed + Open = Expected\n", surface > "/dev/stderr"
                errors++
            }
            if (invalid_evidence(evidence)) {
                printf "coverage row %s requires substantive evidence\n", surface > "/dev/stderr"
                errors++
            }
            if (surface == "In-scope target artifacts") reconcile(surface, actual_scope_files)
            if (surface == "Candidates dispositioned") reconcile(surface, actual_candidates)
            if (surface == "Candidates with verification evidence") reconcile(surface, actual_verification)
            if (surface == "Independent validations") reconcile(surface, actual_validations)
            if (surface == "Material candidate verdicts") reconcile(surface, actual_material_candidates)
            if (surface == "Human-accepted findings") reconcile(surface, actual_findings)
        }
        END {
            if (rows == 0) {
                print "objective artifact reconciliation table is missing or empty" > "/dev/stderr"
                errors++
            }
            for (surface in required) {
                if (seen[surface] != 1) {
                    printf "required coverage surface missing: %s\n", surface > "/dev/stderr"
                    errors++
                }
            }
            if (errors) exit 1
        }
    ' "$WORKSPACE/coverage.md"; then
        fail "$WORKSPACE/coverage.md: objective artifact reconciliation failed"
    fi
    if ! awk -F '|' '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        function invalid(value, lower) {
            lower = tolower(trim(value))
            return lower == "" || lower == "?" ||
                   lower ~ /^(tbd|unknown)([[:space:]:-]|$)/ ||
                   lower ~ /^(n\/a|none)([[:space:]:-]|$)/ ||
                   lower ~ /<[^>]*>/
        }
        /^##[[:space:]]+Method-Defined Security Coverage[[:space:]]*$/ { in_methods = 1; next }
        in_methods && /^##[[:space:]]/ { in_methods = 0 }
        in_methods && /^\|/ {
            surface = trim($2)
            status = trim($3)
            evidence = trim($4)
            residual = trim($5)
            if (surface == "" || surface == "Coverage obligation / surface" || surface ~ /^-+$/) next
            rows++
            seen[surface]++
            if (seen[surface] > 1) {
                printf "method-defined coverage surface %s appears more than once\n", surface > "/dev/stderr"
                errors++
            }
            if (status !~ /^(COVERED|PARTIAL|OPEN|EXCLUDED|NOT-APPLICABLE)$/) {
                printf "method-defined coverage surface %s has invalid status %s\n", surface, status > "/dev/stderr"
                errors++
            }
            if (invalid(surface) || invalid(evidence) || invalid(residual)) {
                printf "method-defined coverage surface %s requires substantive evidence and residual-blind-spot text\n", surface > "/dev/stderr"
                errors++
            }
        }
        END {
            if (rows == 0) {
                print "method-defined coverage table requires at least one substantive row" > "/dev/stderr"
                errors++
            }
            if (errors) exit 1
        }
    ' "$WORKSPACE/coverage.md"; then
        fail "$WORKSPACE/coverage.md: method-defined coverage validation failed"
    fi
    # The bundled atlas is one discovery/coverage method, not a mandatory way to
    # find vulnerabilities. If delta.md is used, validate its closure; otherwise
    # coverage.md must identify the alternative method and residual blind spots.
    if [ -f "$WORKSPACE/atlas/delta.md" ] && grep -Fq '?' "$WORKSPACE/atlas/delta.md"; then
        fail "$WORKSPACE/atlas/delta.md: final triage cannot contain unresolved placeholder rows"
    elif [ -f "$WORKSPACE/atlas/delta.md" ]; then
        while IFS= read -r delta_candidate; do
            [ -n "$delta_candidate" ] || continue
            if [ ! -f "$WORKSPACE/triage/candidates/$delta_candidate.md" ]; then
                fail "$WORKSPACE/atlas/delta.md: $delta_candidate has no per-candidate source file"
            fi
        done < <(awk '
            {
                line = $0
                while (match(line, /C-[0-9]+/)) {
                    print substr(line, RSTART, RLENGTH)
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        ' "$WORKSPACE/atlas/delta.md" | LC_ALL=C sort -u)
    fi
fi

if grep -Eq 'Analysis status:[[:space:]]*(hypothesis|proposed|hunting)|Status:[[:space:]]*(PROPOSED|HUNTING|REPRODUCED|INDEPENDENTLY-VALIDATED|HUMAN-ACCEPTED|REJECTED|DUPLICATE|OUT-OF-SCOPE|INCONCLUSIVE)' "$WORKSPACE/findings.md"; then
    fail "$WORKSPACE/findings.md contains candidate lifecycle state; candidates must remain under triage/"
fi

finding_count="$(grep -Ec '^##[[:space:]]+F-[0-9]+([[:space:]]+.*)?$' "$WORKSPACE/findings.md" || true)"
finding_candidate_count="$(grep -Ec '^- Candidate ID / dedup key:[[:space:]]*C-[0-9]+[[:space:]]+/[[:space:]]+[^[:space:]].*$' "$WORKSPACE/findings.md" || true)"
if [ "$finding_count" -ne "$finding_candidate_count" ]; then
    fail "$WORKSPACE/findings.md: every accepted F-NN section must link exactly one concrete C-NN candidate/dedup key"
fi

if grep -Eq '^- Severity:[[:space:]]*' "$WORKSPACE/findings.md"; then
    fail "$WORKSPACE/findings.md uses the legacy '- Severity:' field; migrate each accepted finding to '- Original severity:' and add the retained reporting fields documented in SKILL.md"
fi

if ! awk '
    function trim(value) {
        sub(/^[ \t]+/, "", value)
        sub(/[ \t]+$/, "", value)
        return value
    }
    function invalid(value, lower) {
        lower = tolower(trim(value))
        return lower == "" || lower == "?" ||
               lower ~ /^(tbd|unknown)([[:space:]:-]|$)/ ||
               lower ~ /^(n\/a|none)([[:space:]:-]|$)/ ||
               lower ~ /<[^>]*>/
    }
    function has_hex_identifier(value, required_length,   parts, count, i) {
        count = split(value, parts, /[^0-9A-Fa-f]+/)
        for (i = 1; i <= count; i++) {
            if (length(parts[i]) == required_length) return 1
        }
        return 0
    }
    function has_immutable_revision(value) {
        return has_hex_identifier(value, 40) || has_hex_identifier(value, 64)
    }
    function has_iso_date(value) {
        return value ~ /(^|[^0-9])[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([^0-9]|$)/
    }
    function states_positive_closure(value, lower) {
        lower = tolower(value)
        return lower ~ /(original mechanism closed|violated property holds|security property holds|proof obligation satisfied|exploit preconditions closed|vulnerable state transition unreachable)/
    }
    function reset_fields(   key) {
        for (key in seen) delete seen[key]
    }
    function finish_section(   required, count, i, field) {
        if (!in_finding) return
        required = "Candidate ID / dedup key;Target lock SHA-256;Target artifact IDs;Target locator;Reachability chain / evidence;Mechanism;Invariant violated;Original severity;Current remediation status;Current deployment;Deployment/state anchor;Evidence verdict;Verification evidence;Independent validation;Cost versus impact;Human decision;Client response;Remediation baseline;Retest;Residual risk;Disclosure handling"
        count = split(required, required_fields, ";")
        for (i = 1; i <= count; i++) {
            field = required_fields[i]
            if (seen[field] != 1) {
                printf "finding section %s requires exactly one non-placeholder field: %s\n", heading, field > "/dev/stderr"
                errors++
            }
        }
        if (verdict !~ /^CONFIRMED-(DEPLOYED|RECONSTRUCTION|LOGIC)$/) {
            printf "finding section %s has non-accepted Evidence verdict: %s\n", heading, verdict > "/dev/stderr"
            errors++
        }
        deployment_lower = tolower(trim(current_deployment))
        if (deployment_lower !~ /^(confirmed exploitable|conditionally exposed|plausibly exposed|not exposed at pinned state|not deployed|unknown)$/) {
            printf "finding section %s has invalid Current deployment enum: %s\n", heading, current_deployment > "/dev/stderr"
            errors++
        }
        if (deployment_lower ~ /^(confirmed exploitable|conditionally exposed|plausibly exposed|not exposed at pinned state)$/ && verdict != "CONFIRMED-DEPLOYED") {
            printf "finding section %s makes a deployment-state claim without CONFIRMED-DEPLOYED evidence\n", heading > "/dev/stderr"
            errors++
        }
        state_anchor_lower = tolower(trim(state_anchor))
        if (deployment_lower ~ /^(confirmed exploitable|conditionally exposed|plausibly exposed|not exposed at pinned state)$/ &&
            state_anchor_lower ~ /^(not assessed|unknown|not applicable|not provided)([[:space:]:-]|$)/) {
            printf "finding section %s makes a deployment-state claim without an immutable Deployment/state anchor\n", heading > "/dev/stderr"
            errors++
        }
        remediation_lower = tolower(trim(remediation_status))
        if (remediation_lower !~ /^(open|fixed - verified|partially fixed|acknowledged|risk accepted|not yet retested)$/) {
            printf "finding section %s has invalid Current remediation status: %s\n", heading, remediation_status > "/dev/stderr"
            errors++
        }
        if (remediation_lower == "fixed - verified") {
            remediation_baseline_lower = tolower(trim(remediation_baseline))
            retest_lower = tolower(trim(retest))
            if (remediation_baseline_lower ~ /^(not provided|not assessed|unknown|not applicable)([[:space:]:-]|$)/) {
                printf "finding section %s is Fixed - Verified without an exact Remediation baseline\n", heading > "/dev/stderr"
                errors++
            } else if (!has_immutable_revision(remediation_baseline)) {
                printf "finding section %s is Fixed - Verified without a full 40/64-hex remediation revision or retained baseline-manifest SHA-256\n", heading > "/dev/stderr"
                errors++
            }
            if (retest_lower ~ /^(not yet retested|not assessed|unknown|not applicable)([[:space:]:-]|$)/) {
                printf "finding section %s is Fixed - Verified without substantive Retest evidence/result\n", heading > "/dev/stderr"
                errors++
            } else {
                if (!has_iso_date(retest)) {
                    printf "finding section %s is Fixed - Verified without a YYYY-MM-DD retest date\n", heading > "/dev/stderr"
                    errors++
                }
                if (!has_hex_identifier(retest, 64)) {
                    printf "finding section %s is Fixed - Verified without a retained retest-evidence SHA-256\n", heading > "/dev/stderr"
                    errors++
                }
                if (!states_positive_closure(retest)) {
                    printf "finding section %s is Fixed - Verified without a positive original-mechanism/property closure result\n", heading > "/dev/stderr"
                    errors++
                }
            }
        }
        # CONFIRMED-DEPLOYED describes the fidelity of the evidence, not a promise
        # that the target remains exploitable now. Historical deployed evidence
        # may support a finding whose pinned current state is remediated, paused,
        # or otherwise not exposed. The converse gate above remains strict.
        if (candidate_link !~ /^C-[0-9]+[[:space:]]+\/[[:space:]]+[^[:space:]].*$/) {
            printf "finding section %s has invalid Candidate ID / dedup key grammar: %s\n", heading, candidate_link > "/dev/stderr"
            errors++
        }
    }
    function capture(field, prefix,   value) {
        if (index($0, prefix) != 1) return
        value = substr($0, length(prefix) + 1)
        sub(/^[ \t]*/, "", value)
        if (field != "Current deployment" && invalid(value)) return
        if (field == "Current deployment" && trim(value) == "") return
        seen[field]++
        if (field == "Candidate ID / dedup key") candidate_link = value
        if (field == "Original severity") severity = value
        if (field == "Current remediation status") remediation_status = value
        if (field == "Evidence verdict") verdict = value
        if (field == "Current deployment") current_deployment = value
        if (field == "Deployment/state anchor") state_anchor = value
        if (field == "Remediation baseline") remediation_baseline = value
        if (field == "Retest") retest = value
    }
    /^##[[:space:]]+F-/ {
        if ($0 !~ /^##[[:space:]]+F-[0-9]+([[:space:]]+.*)?$/) {
            printf "malformed finding heading: %s\n", $0 > "/dev/stderr"
            errors++
            finish_section()
            reset_fields()
            in_finding = 0
            next
        }
        finish_section()
        reset_fields()
        in_finding = 1
        heading = $0
        severity = ""
        remediation_status = ""
        verdict = ""
        current_deployment = ""
        state_anchor = ""
        remediation_baseline = ""
        retest = ""
        candidate_link = ""
        next
    }
    /^##[[:space:]]/ {
        finish_section()
        reset_fields()
        in_finding = 0
        next
    }
    in_finding {
        capture("Candidate ID / dedup key", "- Candidate ID / dedup key:")
        capture("Target lock SHA-256", "- Target lock SHA-256:")
        capture("Target artifact IDs", "- Target artifact IDs:")
        capture("Target locator", "- Target locator:")
        capture("Reachability chain / evidence", "- Reachability chain / evidence:")
        capture("Mechanism", "- Mechanism:")
        capture("Invariant violated", "- Invariant violated:")
        capture("Original severity", "- Original severity:")
        capture("Current remediation status", "- Current remediation status:")
        capture("Current deployment", "- Current deployment:")
        capture("Deployment/state anchor", "- Deployment/state anchor:")
        capture("Evidence verdict", "- Evidence verdict:")
        capture("Verification evidence", "- Verification evidence:")
        capture("Independent validation", "- Independent validation:")
        capture("Cost versus impact", "- Cost versus impact:")
        capture("Human decision", "- Human decision:")
        capture("Client response", "- Client response:")
        capture("Remediation baseline", "- Remediation baseline:")
        capture("Retest", "- Retest:")
        capture("Residual risk", "- Residual risk:")
        capture("Disclosure handling", "- Disclosure handling:")
    }
    END {
        finish_section()
        if (errors) exit 1
    }
' "$WORKSPACE/findings.md"; then
    fail "$WORKSPACE/findings.md: accepted finding schema validation failed"
fi

FIXED_FINDING_METADATA="$TMP_CHECK/fixed-finding-metadata.tsv"
awk '
    function trim(value) {
        sub(/^[ \t]+/, "", value)
        sub(/[ \t]+$/, "", value)
        return value
    }
    function after(prefix, value) {
        value = substr($0, length(prefix) + 1)
        sub(/^[ \t]*/, "", value)
        return value
    }
    function finish() {
        if (in_finding && status == "Fixed - Verified") {
            print finding_id "\t" baseline "\t" retest
        }
    }
    /^##[[:space:]]+F-[0-9]+([[:space:]]+.*)?$/ {
        finish()
        in_finding = 1
        finding_id = baseline = retest = status = ""
        if (match($0, /F-[0-9]+/)) finding_id = substr($0, RSTART, RLENGTH)
        next
    }
    /^##[[:space:]]/ {
        finish()
        in_finding = 0
        next
    }
    in_finding && index($0, "- Current remediation status:") == 1 {
        status = trim(after("- Current remediation status:"))
    }
    in_finding && index($0, "- Remediation baseline:") == 1 {
        baseline = trim(after("- Remediation baseline:"))
    }
    in_finding && index($0, "- Retest:") == 1 {
        retest = trim(after("- Retest:"))
    }
    END { finish() }
' "$WORKSPACE/findings.md" > "$FIXED_FINDING_METADATA"

while IFS="$(printf '\t')" read -r fixed_id fixed_baseline fixed_retest; do
    [ -n "$fixed_id" ] || continue

    baseline_revision="$(structured_field_value "$fixed_baseline" "revision")"
    baseline_manifest="$(structured_field_value "$fixed_baseline" "manifest")"
    baseline_manifest_hash="$(structured_field_value "$fixed_baseline" "sha256")"
    if is_unset "$baseline_revision" || is_unset "$baseline_manifest" || \
       is_unset "$baseline_manifest_hash"; then
        fail "$WORKSPACE/findings.md: $fixed_id Fixed - Verified remediation baseline must use revision=...; manifest=...; sha256=..."
    else
        if ! is_valid_revision_descriptor "$baseline_revision"; then
            fail "$WORKSPACE/findings.md: $fixed_id remediation revision must use a supported type:immutable-id descriptor"
        fi
        if ! printf '%s\n' "$baseline_manifest_hash" | grep -Eq '^[0-9a-fA-F]{64}$'; then
            fail "$WORKSPACE/findings.md: $fixed_id remediation manifest SHA-256 must be exactly 64 hex characters"
        else
            verify_workspace_artifact_values "$WORKSPACE/findings.md: $fixed_id" \
                "remediation manifest" "remediation manifest SHA-256" \
                "$baseline_manifest" "$baseline_manifest_hash"
        fi
        case "$baseline_manifest" in
            /*|../*|*/../*) ;;
            *)
                if ! workspace_path_has_symlink "$baseline_manifest" && \
                   [ -f "$WORKSPACE/$baseline_manifest" ] && \
                   ! grep -Fq "$baseline_revision" "$WORKSPACE/$baseline_manifest"; then
                    fail "$WORKSPACE/findings.md: $fixed_id remediation manifest does not name revision $baseline_revision"
                fi
                ;;
        esac
    fi

    retest_reviewer="$(structured_field_value "$fixed_retest" "reviewer")"
    retest_date="$(structured_field_value "$fixed_retest" "date")"
    retest_method="$(structured_field_value "$fixed_retest" "method")"
    retest_evidence="$(structured_field_value "$fixed_retest" "evidence")"
    retest_hash="$(structured_field_value "$fixed_retest" "sha256")"
    retest_result="$(structured_field_value "$fixed_retest" "result")"
    if is_unset "$retest_reviewer" || is_unset "$retest_date" || \
       is_unset "$retest_method" || is_unset "$retest_evidence" || \
       is_unset "$retest_hash" || is_unset "$retest_result"; then
        fail "$WORKSPACE/findings.md: $fixed_id Fixed - Verified retest must use reviewer=...; date=...; method=...; evidence=...; sha256=...; result=..."
    else
        if ! is_valid_iso_date "$retest_date"; then
            fail "$WORKSPACE/findings.md: $fixed_id retest date is not a real YYYY-MM-DD calendar date"
        fi
        if ! printf '%s\n' "$retest_hash" | grep -Eq '^[0-9a-fA-F]{64}$'; then
            fail "$WORKSPACE/findings.md: $fixed_id retest evidence SHA-256 must be exactly 64 hex characters"
        else
            verify_workspace_artifact_values "$WORKSPACE/findings.md: $fixed_id" \
                "retest evidence" "retest evidence SHA-256" \
                "$retest_evidence" "$retest_hash"
        fi
        if ! printf '%s\n' "$retest_result" | grep -Eqi \
            '(original mechanism closed|violated property holds|security property holds|proof obligation satisfied|exploit preconditions closed|vulnerable state transition unreachable)'; then
            fail "$WORKSPACE/findings.md: $fixed_id retest result does not state positive mechanism/property closure"
        fi
    fi
done < "$FIXED_FINDING_METADATA"

FINDING_LINKS="$TMP_CHECK/finding-links.tsv"
awk '
    function trim(value) {
        sub(/^[ \t]+/, "", value)
        sub(/[ \t]+$/, "", value)
        return value
    }
    function value_after(prefix, value) {
        value = substr($0, length(prefix) + 1)
        sub(/^[ \t]*/, "", value)
        return value
    }
    function finish_section() {
        if (!in_finding) return
        print finding_id "\t" candidate "\t" dedup "\t" reproducer "\t" validation "\t" human "\t" current "\t" verdict "\t" target_lock "\t" target_ids
    }
    /^##[[:space:]]+F-[0-9]+([[:space:]]+.*)?$/ {
        finish_section()
        in_finding = 1
        if (match($0, /F-[0-9]+/)) finding_id = substr($0, RSTART, RLENGTH)
        candidate = dedup = reproducer = validation = human = current = verdict = target_lock = target_ids = ""
        next
    }
    in_finding && index($0, "- Target lock SHA-256:") == 1 { target_lock = value_after("- Target lock SHA-256:") }
    in_finding && index($0, "- Target artifact IDs:") == 1 { target_ids = value_after("- Target artifact IDs:") }
    in_finding && index($0, "- Candidate ID / dedup key:") == 1 {
        raw = value_after("- Candidate ID / dedup key:")
        slash = index(raw, " / ")
        if (slash > 0) {
            candidate = trim(substr(raw, 1, slash - 1))
            dedup = trim(substr(raw, slash + 3))
        }
    }
    in_finding && index($0, "- Verification evidence:") == 1 { reproducer = value_after("- Verification evidence:") }
    in_finding && index($0, "- Independent validation:") == 1 { validation = value_after("- Independent validation:") }
    in_finding && index($0, "- Human decision:") == 1 { human = value_after("- Human decision:") }
    in_finding && index($0, "- Current deployment:") == 1 { current = value_after("- Current deployment:") }
    in_finding && index($0, "- Evidence verdict:") == 1 { verdict = value_after("- Evidence verdict:") }
    /^##[[:space:]]/ && $0 !~ /^##[[:space:]]+F-[0-9]+([[:space:]]+.*)?$/ {
        finish_section()
        in_finding = 0
    }
    END { finish_section() }
' "$WORKSPACE/findings.md" > "$FINDING_LINKS"

duplicate_finding_candidate="$(awk -F '\t' '++seen[$2] == 2 { print $2; exit }' "$FINDING_LINKS")"
if [ -n "$duplicate_finding_candidate" ]; then
    fail "$WORKSPACE/findings.md: candidate $duplicate_finding_candidate is linked by more than one accepted finding"
fi

duplicate_finding_id="$(awk -F '\t' '++seen[$1] == 2 { print $1; exit }' "$FINDING_LINKS")"
if [ -n "$duplicate_finding_id" ]; then
    fail "$WORKSPACE/findings.md: finding ID $duplicate_finding_id appears more than once"
fi

HAS_CONFIRMED_DEPLOYED=0
while IFS="$(printf '\t')" read -r finding_id finding_candidate finding_dedup finding_reproducer finding_validation_link finding_human finding_current finding_verdict finding_target_lock_hash finding_target_ids; do
    [ -n "$finding_candidate" ] || continue
    finding_candidate_file="$WORKSPACE/triage/candidates/$finding_candidate.md"
    if [ ! -f "$finding_candidate_file" ]; then
        fail "$WORKSPACE/findings.md: linked candidate $finding_candidate does not exist"
        continue
    fi
    finding_candidate_status="$(field_value "$finding_candidate_file" "Status")"
    if [ "$finding_candidate_status" != "HUMAN-ACCEPTED" ]; then
        fail "$WORKSPACE/findings.md: linked candidate $finding_candidate has status '$finding_candidate_status', not HUMAN-ACCEPTED"
    fi
    candidate_dedup="$(field_value "$finding_candidate_file" "Dedup key")"
    if [ "$finding_dedup" != "$candidate_dedup" ]; then
        fail "$WORKSPACE/findings.md: $finding_candidate dedup key '$finding_dedup' does not match candidate key '$candidate_dedup'"
    fi
    if [ "$MODE" = "final" ]; then
        normalized_finding_target_lock_hash="$(printf '%s\n' "$finding_target_lock_hash" | tr '[:upper:]' '[:lower:]')"
        if [ "$normalized_finding_target_lock_hash" != "$TARGET_LOCK_SHA256" ]; then
            fail "$WORKSPACE/findings.md: $finding_id target lock SHA-256 does not match current target-lock.md"
        fi
        validate_target_id_value "$WORKSPACE/findings.md: $finding_id" "$finding_target_ids"
        candidate_target_ids="$(field_value "$finding_candidate_file" "Target artifact IDs")"
        if [ "$finding_target_ids" != "$candidate_target_ids" ]; then
            fail "$WORKSPACE/findings.md: $finding_id/$finding_candidate target artifact IDs do not match its candidate"
        fi
    fi
    if [ "$finding_reproducer" != "triage/reproducers/$finding_candidate.md" ]; then
        fail "$WORKSPACE/findings.md: $finding_id/$finding_candidate must link its canonical reproducer manifest in the same finding section"
    fi
    if [ "$finding_validation_link" != "triage/validation/$finding_candidate.md" ]; then
        fail "$WORKSPACE/findings.md: $finding_id/$finding_candidate must link its independent validation record in the same finding section"
    fi
    finding_manifest="$WORKSPACE/triage/reproducers/$finding_candidate.md"
    if [ -L "$finding_manifest" ]; then
        fail "$finding_manifest: verification manifest must be a regular workspace file, not a symlink"
    elif [ -f "$finding_manifest" ]; then
        manifest_verdict="$(field_value "$finding_manifest" "Evidence verdict")"
        if [ "$finding_verdict" != "$manifest_verdict" ]; then
            fail "$WORKSPACE/findings.md: $finding_id/$finding_candidate verdict '$finding_verdict' does not match manifest verdict '$manifest_verdict'"
        fi
    fi
    finding_validation="$WORKSPACE/triage/validation/$finding_candidate.md"
    if [ -L "$finding_validation" ]; then
        fail "$finding_validation: validation record must be a regular workspace file, not a symlink"
    elif [ -f "$finding_validation" ]; then
        accepted_decision="$(field_value "$finding_validation" "Human decision / acceptor / date")"
        if [ "$finding_human" != "$accepted_decision" ]; then
            fail "$WORKSPACE/findings.md: $finding_id/$finding_candidate human decision does not match its validation record"
        fi
        validation_verdict="$(field_value "$finding_validation" "Evidence verdict")"
        if [ "$finding_verdict" != "$validation_verdict" ]; then
            fail "$WORKSPACE/findings.md: $finding_id/$finding_candidate verdict '$finding_verdict' does not match validation verdict '$validation_verdict'"
        fi
    fi
    if [ "$finding_verdict" = "CONFIRMED-DEPLOYED" ]; then
        HAS_CONFIRMED_DEPLOYED=1
    fi
done < "$FINDING_LINKS"

if [ "$HAS_CONFIRMED_DEPLOYED" -eq 1 ]; then
    require_table_substantive_field "$WORKSPACE/scope.md" "Deployment / program / package IDs"
    require_table_substantive_field "$WORKSPACE/scope.md" "Deployed bytecode / package hash"
    require_table_substantive_field "$WORKSPACE/target-lock.md" "Deployment / program / package IDs"
    require_table_substantive_field "$WORKSPACE/target-lock.md" "Deployed bytecode / package hash"
    if [ "$MODE" = "final" ]; then
        validate_deployed_identity_format "$TARGET_CHAIN" "$TARGET_DEPLOYMENT" "$TARGET_DEPLOYED_HASH"
    fi
fi

if [ -d "$WORKSPACE/triage/candidates" ]; then
    while IFS= read -r candidate_file; do
        [ -n "$candidate_file" ] || continue
        if [ -L "$candidate_file" ]; then
            fail "$candidate_file: candidate manifests must be regular workspace files, not symlinks"
            continue
        fi
        if [ ! -f "$candidate_file" ]; then
            fail "$candidate_file: candidate manifest is not a regular file"
            continue
        fi

        for field in \
            "Candidate ID" \
            "Target lock SHA-256" \
            "Target artifact IDs" \
            "Target component" \
            "Target revision" \
            "Deployment / package / program" \
            "Production build / configuration" \
            "Threat actor / entry" \
            "Required actor capabilities" \
            "Invariant" \
            "Mechanism and reachability evidence" \
            "Claimed impact / success criterion" \
            "Falsification / control" \
            "Verification manifest" \
            "Dedup key" \
            "Known-issue search" \
            "Producer" \
            "Producer context / timestamp" \
            "Source and verification artifact hashes" \
            "Cost versus impact" \
            "Potential severity / materiality" \
            "Coverage limitation" \
            "Canonical candidate / finding" \
            "Status" \
            "Disposition reason / evidence"; do
            require_field "$candidate_file" "$field"
        done

        for field in \
            "Target lock SHA-256" \
            "Target artifact IDs" \
            "Target component" \
            "Target revision" \
            "Production build / configuration" \
            "Threat actor / entry" \
            "Required actor capabilities" \
            "Invariant" \
            "Mechanism and reachability evidence" \
            "Claimed impact / success criterion" \
            "Falsification / control" \
            "Dedup key" \
            "Known-issue search" \
            "Producer" \
            "Producer context / timestamp" \
            "Source and verification artifact hashes" \
            "Cost versus impact" \
            "Potential severity / materiality" \
            "Disposition reason / evidence"; do
            require_substantive_field "$candidate_file" "$field"
        done

        candidate_id="$(field_value "$candidate_file" "Candidate ID")"
        status="$(field_value "$candidate_file" "Status")"
        base="$(basename "$candidate_file" .md)"
        candidate_materiality_value="$(field_value "$candidate_file" "Potential severity / materiality")"
        if ! printf '%s\n' "$candidate_materiality_value" | grep -Eq '^.*[^[:space:]][[:space:]]+/[[:space:]]+(MATERIAL|NON-MATERIAL)$'; then
            fail "$candidate_file: Potential severity / materiality must use <engagement severity label> / MATERIAL or NON-MATERIAL"
        fi

        candidate_target_lock_hash="$(field_value "$candidate_file" "Target lock SHA-256" | tr '[:upper:]' '[:lower:]')"
        if [ "$candidate_target_lock_hash" != "$TARGET_LOCK_SHA256" ]; then
            fail "$candidate_file: Target lock SHA-256 does not match the current target-lock.md"
        fi
        if [ "$MODE" = "final" ]; then
            validate_target_id_list "$candidate_file" "Target artifact IDs"
            candidate_target_ids="$(field_value "$candidate_file" "Target artifact IDs")"
            candidate_revision="$(field_value "$candidate_file" "Target revision")"
            candidate_deployment="$(field_value "$candidate_file" "Deployment / package / program")"
            candidate_build="$(field_value "$candidate_file" "Production build / configuration")"
            if [ "$candidate_revision" != "$TARGET_SOURCE_REVISION" ]; then
                fail "$candidate_file: Target revision must exactly match target-lock.md"
            fi
            if [ "$candidate_deployment" != "$TARGET_DEPLOYMENT" ]; then
                fail "$candidate_file: Deployment / package / program must exactly match target-lock.md"
            fi
            if [ "$candidate_build" != "$TARGET_BUILD" ]; then
                fail "$candidate_file: Production build / configuration must exactly match target-lock.md"
            fi
        fi

        if ! printf '%s\n' "$candidate_id" | grep -Eq '^C-[0-9]+$' || \
           ! printf '%s\n' "$base" | grep -Eq '^C-[0-9]+$'; then
            fail "$candidate_file: candidate ID and filename must use exact C-NN grammar"
        fi
        if [ "$candidate_id" != "$base" ]; then
            fail "$candidate_file: Candidate ID '$candidate_id' must match filename '$base'"
        fi

        case "$status" in
            PROPOSED|HUNTING|REPRODUCED|INDEPENDENTLY-VALIDATED|HUMAN-ACCEPTED|REJECTED|DUPLICATE|OUT-OF-SCOPE|INCONCLUSIVE) ;;
            *) fail "$candidate_file: invalid lifecycle status '$status'" ;;
        esac

        if [ "$MODE" = "final" ]; then
            case "$status" in
                HUMAN-ACCEPTED|REJECTED|DUPLICATE|OUT-OF-SCOPE|INCONCLUSIVE) ;;
                *) fail "$candidate_file: final triage requires a terminal disposition, not '$status'" ;;
            esac
        fi

        dedup_key="$(field_value "$candidate_file" "Dedup key")"
        if ! printf '%s\n' "$dedup_key" | awk -F '|' '
            function trim(value) {
                sub(/^[ \t]+/, "", value)
                sub(/[ \t]+$/, "", value)
                return value
            }
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    value = tolower(trim($i))
                    if (value == "" || value == "n/a" || value == "none" ||
                        value == "?" || value == "tbd" || value == "unknown") exit 1
                }
            }
        '; then
            fail "$candidate_file: Dedup key must use non-empty root-cause|invariant|sink segments"
        fi
        manifest_ref="$(field_value "$candidate_file" "Verification manifest")"
        if [ "$manifest_ref" != "triage/reproducers/$candidate_id.md" ]; then
            fail "$candidate_file: Verification manifest must be triage/reproducers/$candidate_id.md"
        fi

        if [ "$status" = "INCONCLUSIVE" ]; then
            coverage_limitation="$(field_value "$candidate_file" "Coverage limitation")"
            if [ "$coverage_limitation" = "N/A" ] || ! grep -Fq "$candidate_id" "$WORKSPACE/coverage.md"; then
                fail "$candidate_file: INCONCLUSIVE requires a C-ID-linked coverage.md limitation"
            fi
            candidate_materiality="$(field_value "$candidate_file" "Potential severity / materiality")"
            if ! awk -F '|' -v candidate="$candidate_id" -v candidate_materiality="$candidate_materiality" '
                function trim(value) {
                    sub(/^[ \t]+/, "", value)
                    sub(/[ \t]+$/, "", value)
                    return value
                }
                function invalid(value, lower) {
                    lower = tolower(trim(value))
                    return lower == "" || lower == "?" ||
                           lower ~ /^(tbd|unknown|n\/a|none)([[:space:]:-]|$)/ ||
                           lower ~ /<[^>]*>/
                }
                /^##[[:space:]]+Candidate Limitations[[:space:]]*$/ { in_limitations = 1; next }
                in_limitations && /^##[[:space:]]/ { in_limitations = 0 }
                in_limitations && trim($2) == candidate {
                    rows++
                    if (NF != 8) {
                        printf "candidate limitation %s row must have exactly six columns\n", candidate > "/dev/stderr"
                        errors++
                    }
                    materiality = trim($3)
                    status = trim($4)
                    blocker = trim($5)
                    next_step = trim($6)
                    report_verdict = trim($7)
                }
                END {
                    if (rows != 1) {
                        printf "candidate limitation table requires exactly one row for %s (found %d)\n", candidate, rows > "/dev/stderr"
                        errors++
                    }
                    if (materiality != candidate_materiality) {
                        printf "candidate limitation %s severity/materiality must match its candidate\n", candidate > "/dev/stderr"
                        errors++
                    }
                    if (status !~ /^(PARTIAL|OPEN)$/) {
                        printf "candidate limitation %s status must be PARTIAL or OPEN\n", candidate > "/dev/stderr"
                        errors++
                    }
                    if (invalid(blocker) || invalid(next_step) || invalid(report_verdict)) {
                        printf "candidate limitation %s requires a substantive blocker, next step, and report verdict\n", candidate > "/dev/stderr"
                        errors++
                    }
                    if (candidate_materiality ~ /\/[[:space:]]*MATERIAL$/ && report_verdict != "INCOMPLETE") {
                        printf "MATERIAL INCONCLUSIVE candidate %s requires report verdict INCOMPLETE\n", candidate > "/dev/stderr"
                        errors++
                    }
                    if (errors) exit 1
                }
            ' "$WORKSPACE/coverage.md"; then
                fail "$candidate_file: structured INCONCLUSIVE closure validation failed"
            fi
        fi

        if [ "$status" = "DUPLICATE" ]; then
            canonical="$(field_value "$candidate_file" "Canonical candidate / finding")"
            if ! printf '%s\n' "$canonical" | grep -Eq '^(C|F)-[0-9]+$'; then
                fail "$candidate_file: DUPLICATE requires a canonical C-NN or F-NN reference"
            elif [ "$canonical" = "$candidate_id" ]; then
                fail "$candidate_file: DUPLICATE canonical reference cannot point to itself"
            else
                case "$canonical" in
                    C-*)
                        if [ ! -f "$WORKSPACE/triage/candidates/$canonical.md" ] || [ -L "$WORKSPACE/triage/candidates/$canonical.md" ]; then
                            fail "$candidate_file: canonical candidate $canonical does not exist as a regular candidate record"
                        fi
                        ;;
                    F-*)
                        if ! grep -Eq "^##[[:space:]]+$canonical([[:space:]]+.*)?$" "$WORKSPACE/findings.md"; then
                            fail "$candidate_file: canonical finding $canonical does not exist in findings.md"
                        fi
                        ;;
                esac
            fi
            if ! ledger_contains_key "$dedup_key"; then
                fail "$candidate_file: duplicate dedup key is missing from known-issues.md"
            elif printf '%s\n' "$canonical" | grep -Eq '^(C|F)-[0-9]+$' && \
                 ! ledger_contains_key_and_canonical "$dedup_key" "$canonical"; then
                fail "$candidate_file: known-issues.md does not bind dedup key '$dedup_key' to canonical $canonical"
            fi
        fi

        if [ "$status" = "REJECTED" ] && ! ledger_contains_key "$dedup_key"; then
            fail "$candidate_file: rejected dedup key and rationale must be recorded in known-issues.md"
        fi

        case "$status" in
            REPRODUCED|INDEPENDENTLY-VALIDATED|HUMAN-ACCEPTED)
                reproducer="$WORKSPACE/triage/reproducers/$candidate_id.md"
                if [ -L "$reproducer" ]; then
                    fail "$reproducer: verification manifest must be a regular workspace file, not a symlink"
                elif [ ! -f "$reproducer" ]; then
                    fail "$candidate_file: status $status requires $reproducer"
                else
                    for field in \
                        "Candidate" \
                        "Target lock SHA-256" \
                        "Target artifact IDs" \
                        "Target/source revision and artifact hash" \
                        "Production build/profile or target-identity procedure" \
                        "Chain, deployment/configuration, dependencies" \
                        "Evidence verdict" \
                        "Target fidelity" \
                        "Target fidelity basis" \
                        "State anchor kind" \
                        "State anchor value" \
                        "Producer context and evidence revision" \
                        "Toolchain/OS versions" \
                        "Actor initial conditions and capital/capability acquisition" \
                        "Preconditions checked" \
                        "Action sequence or proof derivation" \
                        "Evidence method" \
                        "Primary verification artifact path" \
                        "Primary verification artifact SHA-256" \
                        "Exact command or review procedure" \
                        "Claimed impact / success criterion" \
                        "Primary evidence path" \
                        "Primary evidence SHA-256" \
                        "Falsification / control procedure and expected discriminator" \
                        "Falsification / control evidence path" \
                        "Falsification / control evidence SHA-256" \
                        "Production-state deviations" \
                        "Repeatability / proof-review result"; do
                        require_substantive_field "$reproducer" "$field"
                    done
                    reproducer_candidate="$(field_value "$reproducer" "Candidate")"
                    if [ "$reproducer_candidate" != "$candidate_id" ]; then
                        fail "$reproducer: Candidate '$reproducer_candidate' must match '$candidate_id'"
                    fi
                    reproducer_target_lock_hash="$(field_value "$reproducer" "Target lock SHA-256" | tr '[:upper:]' '[:lower:]')"
                    if [ "$reproducer_target_lock_hash" != "$TARGET_LOCK_SHA256" ]; then
                        fail "$reproducer: Target lock SHA-256 does not match the current target-lock.md"
                    fi
                    if [ "$MODE" = "final" ]; then
                        validate_target_id_list "$reproducer" "Target artifact IDs"
                        reproducer_target_ids="$(field_value "$reproducer" "Target artifact IDs")"
                        if [ "$reproducer_target_ids" != "$candidate_target_ids" ]; then
                            fail "$reproducer: Target artifact IDs do not match $candidate_id"
                        fi

                        manifest_target_source="$(field_value "$reproducer" "Target/source revision and artifact hash")"
                        manifest_build="$(field_value "$reproducer" "Production build/profile or target-identity procedure")"
                        manifest_chain_config="$(field_value "$reproducer" "Chain, deployment/configuration, dependencies")"
                        case "$manifest_target_source" in
                            *"$TARGET_SOURCE_REVISION"*) ;;
                            *) fail "$reproducer: target/source identity does not contain the locked source revision" ;;
                        esac
                        case "$manifest_build" in
                            *"$TARGET_BUILD"*) ;;
                            *) fail "$reproducer: production build identity does not contain the locked build/profile" ;;
                        esac
                        for locked_value in "$TARGET_CHAIN" "$TARGET_DEPLOYMENT" "$TARGET_CONFIGURATION"; do
                            case "$manifest_chain_config" in
                                *"$locked_value"*) ;;
                                *) fail "$reproducer: chain/deployment/configuration does not contain locked value '$locked_value'" ;;
                            esac
                        done
                    fi
                    manifest_verdict="$(field_value "$reproducer" "Evidence verdict")"
                    target_fidelity="$(field_value "$reproducer" "Target fidelity")"
                    state_anchor_kind="$(field_value "$reproducer" "State anchor kind")"
                    state_anchor_value="$(field_value "$reproducer" "State anchor value")"
                    case "$manifest_verdict/$target_fidelity" in
                        CONFIRMED-DEPLOYED/DEPLOYED|CONFIRMED-RECONSTRUCTION/RECONSTRUCTION|CONFIRMED-LOGIC/LOGIC) ;;
                        *) fail "$reproducer: Evidence verdict '$manifest_verdict' contradicts Target fidelity '$target_fidelity'" ;;
                    esac
                    if [ "$MODE" = "final" ] && [ "$manifest_verdict" = "CONFIRMED-DEPLOYED" ]; then
                        case "$manifest_target_source" in
                            *"$TARGET_DEPLOYED_HASH"*) ;;
                            *) fail "$reproducer: deployed target/source identity does not contain the locked deployed hash" ;;
                        esac
                    fi
                    case "$state_anchor_kind" in
                        BLOCK|SLOT|TRANSACTION|OBJECT-VERSIONS|STATE-ROOT|SNAPSHOT|DEPLOYMENT-VERSION|SOURCE-REVISION|PRE-DEPLOYMENT|OTHER-PINNED) ;;
                        *) fail "$reproducer: invalid State anchor kind '$state_anchor_kind'" ;;
                    esac
                    if printf '%s\n' "$state_anchor_value" | grep -Eiq '(^|[^[:alnum:]_])(latest|head)([^[:alnum:]_]|$)'; then
                        fail "$reproducer: State anchor value must be pinned, not latest/head"
                    fi
                    case "$state_anchor_kind" in
                        BLOCK|SLOT)
                            if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^[1-9][0-9]*$'; then
                                fail "$reproducer: $state_anchor_kind State anchor value must be a positive integer"
                            fi
                            ;;
                        TRANSACTION)
                            case "${TARGET_CHAIN:-}" in
                                solana)
                                    if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^[1-9A-HJ-NP-Za-km-z]{64,100}$'; then
                                        fail "$reproducer: Solana TRANSACTION anchor must be a base58 transaction signature"
                                    fi
                                    ;;
                                sui)
                                    if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^[1-9A-HJ-NP-Za-km-z]{32,64}$'; then
                                        fail "$reproducer: Sui TRANSACTION anchor must be a base58 transaction digest"
                                    fi
                                    ;;
                                *)
                                    if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^0x[0-9a-fA-F]{64}$'; then
                                        fail "$reproducer: EVM TRANSACTION anchor must be a 32-byte transaction hash"
                                    fi
                                    ;;
                            esac
                            ;;
                        OBJECT-VERSIONS)
                            if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^0x[0-9a-fA-F]{1,64}@[1-9][0-9]*(,0x[0-9a-fA-F]{1,64}@[1-9][0-9]*)*$'; then
                                fail "$reproducer: OBJECT-VERSIONS anchor must use object-id@positive-version entries"
                            fi
                            ;;
                        STATE-ROOT)
                            if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^(0x[0-9a-fA-F]{64}|[1-9A-HJ-NP-Za-km-z]{32,64})$'; then
                                fail "$reproducer: STATE-ROOT anchor must be a structured 32-byte hex/base58 digest"
                            fi
                            ;;
                        SNAPSHOT)
                            if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^(sha256[:=])?[0-9a-fA-F]{64}$'; then
                                fail "$reproducer: SNAPSHOT anchor must be content-addressed by SHA-256"
                            fi
                            ;;
                        DEPLOYMENT-VERSION|SOURCE-REVISION|PRE-DEPLOYMENT)
                            if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^([0-9a-fA-F]{7,64}|[[:alnum:]_.:-]*[0-9][[:alnum:]_.:-]*)$'; then
                                fail "$reproducer: $state_anchor_kind anchor must be an immutable revision/version identifier"
                            fi
                            ;;
                        OTHER-PINNED)
                            if ! printf '%s\n' "$state_anchor_value" | grep -Eq '^[[:alnum:]_.-]+[=:][^[:space:]]*[0-9][^[:space:]]*$'; then
                                fail "$reproducer: OTHER-PINNED State anchor value must use a named immutable/versioned anchor such as epoch=123"
                            fi
                            ;;
                    esac
                    if [ "$target_fidelity" = "DEPLOYED" ]; then
                        case "$state_anchor_kind" in
                            SOURCE-REVISION|PRE-DEPLOYMENT)
                                fail "$reproducer: DEPLOYED fidelity requires a deployed-state anchor kind"
                                ;;
                        esac
                    fi
                    verify_workspace_artifact "$reproducer" "Primary verification artifact path" "Primary verification artifact SHA-256"
                    verify_workspace_artifact "$reproducer" "Primary evidence path" "Primary evidence SHA-256"
                    verify_workspace_artifact "$reproducer" "Falsification / control evidence path" "Falsification / control evidence SHA-256"
                fi
                ;;
        esac

        case "$status" in
            INDEPENDENTLY-VALIDATED|HUMAN-ACCEPTED)
                validation="$WORKSPACE/triage/validation/$candidate_id.md"
                if [ -L "$validation" ]; then
                    fail "$validation: validation record must be a regular workspace file, not a symlink"
                elif [ ! -f "$validation" ]; then
                    fail "$candidate_file: status $status requires $validation"
                else
                    for field in \
                        "Candidate" \
                        "Target lock SHA-256" \
                        "Target artifact IDs" \
                        "Validator" \
                        "Validator context / timestamp" \
                        "Independent from producer" \
                        "Independent verification procedure" \
                        "Target identity / production configuration" \
                        "Independent verification result" \
                        "Evidence verdict" \
                        "Target fidelity verdict" \
                        "Actor/reachability verdict" \
                        "Impossible-state review" \
                        "Impact criterion and falsification result" \
                        "Dedup disposition" \
                        "Actor cost versus impact" \
                        "Recommendation" \
                        "Decision reason" \
                        "Validation evidence path" \
                        "Validation evidence SHA-256"; do
                        require_substantive_field "$validation" "$field"
                    done

                    validation_candidate="$(field_value "$validation" "Candidate")"
                    if [ "$validation_candidate" != "$candidate_id" ]; then
                        fail "$validation: Candidate '$validation_candidate' must match '$candidate_id'"
                    fi
                    validation_target_lock_hash="$(field_value "$validation" "Target lock SHA-256" | tr '[:upper:]' '[:lower:]')"
                    if [ "$validation_target_lock_hash" != "$TARGET_LOCK_SHA256" ]; then
                        fail "$validation: Target lock SHA-256 does not match the current target-lock.md"
                    fi
                    if [ "$MODE" = "final" ]; then
                        validate_target_id_list "$validation" "Target artifact IDs"
                        validation_target_ids="$(field_value "$validation" "Target artifact IDs")"
                        if [ "$validation_target_ids" != "$candidate_target_ids" ]; then
                            fail "$validation: Target artifact IDs do not match $candidate_id"
                        fi
                        validation_target_identity="$(field_value "$validation" "Target identity / production configuration")"
                        for locked_value in "$TARGET_SOURCE_REVISION" "$TARGET_BUILD" "$TARGET_CHAIN" "$TARGET_DEPLOYMENT" "$TARGET_CONFIGURATION"; do
                            case "$validation_target_identity" in
                                *"$locked_value"*) ;;
                                *) fail "$validation: target identity/configuration does not contain locked value '$locked_value'" ;;
                            esac
                        done
                    fi
                    verify_workspace_artifact "$validation" "Validation evidence path" "Validation evidence SHA-256"

                    validation_evidence_verdict="$(field_value "$validation" "Evidence verdict")"
                    if [ "$MODE" = "final" ] && [ "$validation_evidence_verdict" = "CONFIRMED-DEPLOYED" ]; then
                        case "$validation_target_identity" in
                            *"$TARGET_DEPLOYED_HASH"*) ;;
                            *) fail "$validation: deployed target identity/configuration does not contain the locked deployed hash" ;;
                        esac
                    fi
                    manifest_path="$WORKSPACE/triage/reproducers/$candidate_id.md"
                    if [ -f "$manifest_path" ] && [ ! -L "$manifest_path" ]; then
                        manifest_evidence_verdict="$(field_value "$manifest_path" "Evidence verdict")"
                        if [ "$validation_evidence_verdict" != "$manifest_evidence_verdict" ]; then
                            fail "$validation: Evidence verdict '$validation_evidence_verdict' does not match manifest verdict '$manifest_evidence_verdict'"
                        fi
                    else
                        fail "$validation: cannot compare Evidence verdict because canonical manifest is missing or unsafe"
                    fi

                    producer="$(normalize_actor "$(field_value "$candidate_file" "Producer")")"
                    validator="$(normalize_actor "$(field_value "$validation" "Validator")")"
                    independent="$(field_value "$validation" "Independent from producer" | tr '[:upper:]' '[:lower:]')"
                    if [ "$producer" = "$validator" ]; then
                        fail "$validation: validator must differ from producer '$producer'"
                    fi
                    case "$independent" in
                        yes|true|confirmed) ;;
                        *) fail "$validation: 'Independent from producer' must be yes/true/confirmed" ;;
                    esac

                    reachability="$(field_value "$validation" "Actor/reachability verdict" | tr '[:lower:]' '[:upper:]')"
                    impossible_state="$(field_value "$validation" "Impossible-state review" | tr '[:lower:]' '[:upper:]')"
                    oracle_result="$(field_value "$validation" "Impact criterion and falsification result" | tr '[:lower:]' '[:upper:]')"
                    fidelity_result="$(field_value "$validation" "Target fidelity verdict" | tr '[:lower:]' '[:upper:]')"
                    dedup_result="$(field_value "$validation" "Dedup disposition" | tr '[:lower:]' '[:upper:]')"
                    recommendation="$(field_value "$validation" "Recommendation" | tr '[:lower:]' '[:upper:]')"

                    case "$reachability" in
                        PASS\ *|PASS|CONFIRMED\ *|CONFIRMED) ;;
                        *) fail "$validation: reachability verdict must explicitly start PASS or CONFIRMED" ;;
                    esac
                    case "$impossible_state" in
                        PASS\ *|PASS|CONFIRMED\ *|CONFIRMED) ;;
                        *) fail "$validation: impossible-state review must explicitly start PASS or CONFIRMED" ;;
                    esac
                    case "$oracle_result" in
                        PASS\ *|PASS|CONFIRMED\ *|CONFIRMED) ;;
                        *) fail "$validation: oracle/negative-control result must explicitly start PASS or CONFIRMED" ;;
                    esac
                    case "$fidelity_result" in
                        PASS\ *|PASS|CONFIRMED\ *|CONFIRMED) ;;
                        *) fail "$validation: target fidelity verdict must explicitly start PASS or CONFIRMED" ;;
                    esac
                    case "$dedup_result" in
                        NOVEL\ *|NOVEL|UNIQUE\ *|UNIQUE|VARIANT-OF\ *|VARIANT-OF) ;;
                        *) fail "$validation: validated candidate dedup disposition must start NOVEL, UNIQUE, or VARIANT-OF" ;;
                    esac
                    case "$recommendation" in
                        INDEPENDENTLY-VALIDATED\ *|INDEPENDENTLY-VALIDATED|ACCEPT\ *|ACCEPT) ;;
                        *) fail "$validation: status $status requires an acceptance recommendation" ;;
                    esac
                fi
                ;;
        esac

    if [ "$status" = "HUMAN-ACCEPTED" ]; then
            validation="$WORKSPACE/triage/validation/$candidate_id.md"
            if [ -f "$validation" ] && [ ! -L "$validation" ]; then
                require_field "$validation" "Human decision / acceptor / date"
                human_decision="$(field_value "$validation" "Human decision / acceptor / date")"
                if ! printf '%s\n' "$human_decision" | grep -Eq '^ACCEPTED[[:space:]]*/[[:space:]]*[^/[:space:]][^/]*/[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$'; then
                    fail "$validation: HUMAN-ACCEPTED requires 'ACCEPTED / <human acceptor> / YYYY-MM-DD'"
                fi
            fi
            if ! awk -F '\t' -v candidate="$candidate_id" '$2 == candidate { found = 1 } END { exit(found ? 0 : 1) }' "$FINDING_LINKS"; then
                fail "$candidate_file: HUMAN-ACCEPTED candidate is not linked from findings.md"
            fi
            if ! ledger_contains_key "$dedup_key"; then
                fail "$candidate_file: accepted dedup key is missing from known-issues.md"
            fi
            printf '%s\t%s\n' "$dedup_key" "$candidate_id" >> "$ACCEPTED_KEYS"
        fi
    done < <(find "$WORKSPACE/triage/candidates" \( -type f -o -type l \) -name 'C-*.md' -print | LC_ALL=C sort)
fi

duplicate_accepted_key="$(awk -F '\t' '++seen[$1] == 2 { print $1; exit }' "$ACCEPTED_KEYS")"
if [ -n "$duplicate_accepted_key" ]; then
    fail "more than one HUMAN-ACCEPTED candidate uses dedup key '$duplicate_accepted_key'"
fi

if [ "$failures" -ne 0 ]; then
    printf 'Triage check failed with %s error(s).\n' "$failures" >&2
    exit 1
fi

printf 'Triage contract checks passed.\n'
