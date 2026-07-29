#!/usr/bin/env bash
# Deterministically generate the candidate registry from one-file-per-candidate
# source artifacts. Portable across Apple Bash 3.2 and Linux Bash.

set -euo pipefail

MODE="write"
if [ "${1:-}" = "--check" ]; then
    MODE="check"
    shift
fi
WORKSPACE="${1:?Usage: triage-index.sh [--check] <audit-workspace/protocol>}"
CANDIDATE_DIR="$WORKSPACE/triage/candidates"
INDEX="$WORKSPACE/triage/candidates.md"

if [ -L "$WORKSPACE" ] || [ -L "$WORKSPACE/triage" ] || [ -L "$CANDIDATE_DIR" ]; then
    printf 'ERROR: workspace/triage/candidate directories must not be symlinks\n' >&2
    exit 1
fi
if [ -L "$INDEX" ]; then
    printf 'ERROR: candidate index must not be a symlink: %s\n' "$INDEX" >&2
    exit 1
fi
if [ ! -d "$CANDIDATE_DIR" ]; then
    printf 'ERROR: candidate directory missing: %s\n' "$CANDIDATE_DIR" >&2
    exit 1
fi

TMP_INDEX="$(mktemp "${TMPDIR:-/tmp}/contract-audit-index.XXXXXX")"
trap 'rm -f "$TMP_INDEX"' EXIT HUP INT TERM

field_value() {
    file="$1"
    field="$2"
    awk -v prefix="- $field:" '
        index($0, prefix) == 1 {
            count++
            value = substr($0, length(prefix) + 1)
            sub(/^[ \t]*/, "", value)
            if (count == 1) first = value
        }
        END {
            if (count != 1) {
                printf "ERROR: %s field %s must appear exactly once (found %d)\n", FILENAME, prefix, count + 0 > "/dev/stderr"
                exit 2
            }
            print first
        }
    ' "$file"
}

escape_cell() {
    printf '%s' "$1" | sed 's/|/\\|/g'
}

require_exact_field() {
    file="$1"
    field="$2"
    count="$(awk -v prefix="- $field:" 'index($0, prefix) == 1 { count++ } END { print count + 0 }' "$file")"
    if [ "$count" -ne 1 ]; then
        printf "ERROR: %s field '- %s:' must appear exactly once (found %s)\n" \
            "$file" "$field" "$count" >&2
        return 1
    fi
}

{
    printf '# Candidate Registry — Generated Index\n\n'
    printf '> Generated from `triage/candidates/C-NN.md` by `triage-index.sh`. '
    printf 'Do not edit this table manually; claim work by creating/updating the per-candidate file, then regenerate.\n\n'
    printf '| ID | Target / threat actor and entry | Invariant / mechanism | Impact criterion / falsification | Verification manifest | Dedup key | Owner | Status |\n'
    printf '|----|-------------------------|-----------------------|----------------------------------|-----------------------|-----------|-------|--------|\n'

    while IFS= read -r candidate_file; do
        [ -n "$candidate_file" ] || continue
        if [ -L "$candidate_file" ] || [ ! -f "$candidate_file" ]; then
            printf 'ERROR: candidate manifest must be a regular file, not a symlink: %s\n' "$candidate_file" >&2
            exit 1
        fi
        for field in \
            "Candidate ID" \
            "Target component" \
            "Threat actor / entry" \
            "Invariant" \
            "Mechanism and reachability evidence" \
            "Claimed impact / success criterion" \
            "Falsification / control" \
            "Verification manifest" \
            "Dedup key" \
            "Producer" \
            "Status"; do
            require_exact_field "$candidate_file" "$field" || exit 1
        done
        raw_id="$(field_value "$candidate_file" "Candidate ID")"
        base_id="$(basename "$candidate_file" .md)"
        if ! printf '%s\n' "$raw_id" | grep -Eq '^C-[0-9]+$' || \
           [ "$raw_id" != "$base_id" ]; then
            printf 'ERROR: candidate ID and filename must use matching exact C-NN grammar: %s\n' "$candidate_file" >&2
            exit 1
        fi
        id="$(escape_cell "$raw_id")"
        target="$(escape_cell "$(field_value "$candidate_file" "Target component") / $(field_value "$candidate_file" "Threat actor / entry")")"
        invariant="$(escape_cell "$(field_value "$candidate_file" "Invariant") / $(field_value "$candidate_file" "Mechanism and reachability evidence")")"
        oracle="$(escape_cell "$(field_value "$candidate_file" "Claimed impact / success criterion") / $(field_value "$candidate_file" "Falsification / control")")"
        reproducer="$(escape_cell "$(field_value "$candidate_file" "Verification manifest")")"
        dedup="$(escape_cell "$(field_value "$candidate_file" "Dedup key")")"
        owner="$(escape_cell "$(field_value "$candidate_file" "Producer")")"
        status="$(escape_cell "$(field_value "$candidate_file" "Status")")"
        printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
            "$id" "$target" "$invariant" "$oracle" "$reproducer" "$dedup" "$owner" "$status"
    done < <(find "$CANDIDATE_DIR" \( -type f -o -type l \) -name 'C-*.md' -print | LC_ALL=C sort)
} > "$TMP_INDEX"

if [ "$MODE" = "check" ]; then
    if [ ! -f "$INDEX" ] || ! cmp -s "$TMP_INDEX" "$INDEX"; then
        printf 'ERROR: candidate index is stale; run: bash %s/scripts/triage-index.sh %s\n' \
            "$(cd "$(dirname "$0")/.." && pwd)" "$WORKSPACE" >&2
        exit 1
    fi
    printf 'Candidate index is current.\n'
else
    mv "$TMP_INDEX" "$INDEX"
    trap - EXIT HUP INT TERM
    printf 'Candidate index updated: %s\n' "$INDEX"
fi
