#!/usr/bin/env bash
# Shared non-destructive retention helpers for audit-producing scripts.
# Source this file from Bash 3.2+; do not execute it directly.

audit_path_has_content() {
    audit_retention_path="$1"
    if [ -e "$audit_retention_path" ] || [ -L "$audit_retention_path" ]; then
        return 0
    fi
    return 1
}

audit_validate_managed_path() {
    audit_retention_workspace_input="$1"
    audit_retention_source_input="$2"

    if ! audit_retention_workspace_physical="$(cd "$audit_retention_workspace_input" 2>/dev/null && pwd -P)"; then
        printf 'ERROR: retention workspace is unavailable: %s\n' "$audit_retention_workspace_input" >&2
        return 1
    fi
    if [ -L "$audit_retention_source_input" ]; then
        printf 'ERROR: refusing to archive or replace symlink output: %s\n' "$audit_retention_source_input" >&2
        return 1
    fi
    audit_retention_parent="$(dirname "$audit_retention_source_input")"
    if ! audit_retention_parent_physical="$(cd "$audit_retention_parent" 2>/dev/null && pwd -P)"; then
        printf 'ERROR: managed output parent is unavailable: %s\n' "$audit_retention_parent" >&2
        return 1
    fi
    case "$audit_retention_parent_physical" in
        "$audit_retention_workspace_physical"|"$audit_retention_workspace_physical"/*) ;;
        *)
            printf 'ERROR: managed output escapes retention workspace: %s\n' "$audit_retention_source_input" >&2
            return 1
            ;;
    esac
    if [ -d "$audit_retention_source_input" ] && \
       [ -n "$(find "$audit_retention_source_input" -type l -print -quit 2>/dev/null)" ]; then
        printf 'ERROR: managed output directory contains a symlink: %s\n' "$audit_retention_source_input" >&2
        return 1
    fi
}

audit_archive_existing() {
    audit_retention_workspace="$1"
    audit_retention_helper="$2"
    shift 2

    case "$audit_retention_helper" in
        ""|*[!A-Za-z0-9._-]*)
            printf 'ERROR: invalid retention helper name: %s\n' "$audit_retention_helper" >&2
            return 1
            ;;
    esac

    if ! audit_retention_workspace_physical="$(cd "$audit_retention_workspace" 2>/dev/null && pwd -P)"; then
        printf 'ERROR: retention workspace is unavailable: %s\n' "$audit_retention_workspace" >&2
        return 1
    fi

    if [ -L "$audit_retention_workspace/tmp" ]; then
        printf 'ERROR: retention tmp path must not be a symlink: %s\n' "$audit_retention_workspace/tmp" >&2
        return 1
    fi
    if [ -e "$audit_retention_workspace/tmp" ] && [ ! -d "$audit_retention_workspace/tmp" ]; then
        printf 'ERROR: retention tmp path is not a directory: %s\n' "$audit_retention_workspace/tmp" >&2
        return 1
    fi
    mkdir -p "$audit_retention_workspace/tmp" || return 1

    audit_retention_helper_root="$audit_retention_workspace/tmp/$audit_retention_helper"
    if [ -L "$audit_retention_helper_root" ]; then
        printf 'ERROR: retention helper path must not be a symlink: %s\n' "$audit_retention_helper_root" >&2
        return 1
    fi
    if [ -e "$audit_retention_helper_root" ] && [ ! -d "$audit_retention_helper_root" ]; then
        printf 'ERROR: retention helper path is not a directory: %s\n' "$audit_retention_helper_root" >&2
        return 1
    fi
    mkdir -p "$audit_retention_helper_root" || return 1
    if ! audit_retention_helper_physical="$(cd "$audit_retention_helper_root" 2>/dev/null && pwd -P)"; then
        printf 'ERROR: retention helper path is unavailable: %s\n' "$audit_retention_helper_root" >&2
        return 1
    fi
    case "$audit_retention_helper_physical" in
        "$audit_retention_workspace_physical"/*) ;;
        *)
            printf 'ERROR: retention helper path escapes workspace: %s\n' "$audit_retention_helper_root" >&2
            return 1
            ;;
    esac

    for audit_retention_source in "$@"; do
        audit_validate_managed_path "$audit_retention_workspace" "$audit_retention_source" || return 1
    done

    audit_retention_base="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    audit_retention_root="$audit_retention_helper_root/$audit_retention_base"
    audit_retention_partial="$audit_retention_helper_root/.partial-$audit_retention_base"
    audit_retention_suffix=0
    while [ -e "$audit_retention_root" ] || [ -L "$audit_retention_root" ] || \
          [ -e "$audit_retention_partial" ] || [ -L "$audit_retention_partial" ]; do
        audit_retention_suffix=$((audit_retention_suffix + 1))
        audit_retention_root="$audit_retention_helper_root/$audit_retention_base-$audit_retention_suffix"
        audit_retention_partial="$audit_retention_helper_root/.partial-$audit_retention_base-$audit_retention_suffix"
    done

    audit_retention_created=0
    for audit_retention_source in "$@"; do
        if ! audit_path_has_content "$audit_retention_source"; then
            continue
        fi
        if [ "$audit_retention_created" -eq 0 ]; then
            mkdir "$audit_retention_partial" || {
                printf 'ERROR: cannot create partial retention snapshot: %s\n' "$audit_retention_partial" >&2
                return 1
            }
            {
                printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
                printf 'helper=%s\n' "$audit_retention_helper"
            } > "$audit_retention_partial/retention-manifest.txt" || return 1
            : > "$audit_retention_partial/INCOMPLETE" || return 1
            audit_retention_created=1
        fi

        audit_retention_name="$(basename "$audit_retention_source")"
        audit_retention_destination="$audit_retention_partial/$audit_retention_name"
        audit_retention_final_destination="$audit_retention_root/$audit_retention_name"
        if [ -e "$audit_retention_destination" ] || [ -L "$audit_retention_destination" ]; then
            audit_retention_n=1
            while [ -e "$audit_retention_destination.$audit_retention_n" ] || [ -L "$audit_retention_destination.$audit_retention_n" ]; do
                audit_retention_n=$((audit_retention_n + 1))
            done
            audit_retention_destination="$audit_retention_destination.$audit_retention_n"
            audit_retention_final_destination="$audit_retention_final_destination.$audit_retention_n"
        fi

        if [ -d "$audit_retention_source" ] && [ ! -L "$audit_retention_source" ]; then
            if ! cp -pR "$audit_retention_source" "$audit_retention_destination"; then
                printf 'failure=copy source %s\n' "$audit_retention_source" \
                    >> "$audit_retention_partial/retention-manifest.txt" 2>/dev/null || true
                return 1
            fi
        else
            if ! cp -p "$audit_retention_source" "$audit_retention_destination"; then
                printf 'failure=copy source %s\n' "$audit_retention_source" \
                    >> "$audit_retention_partial/retention-manifest.txt" 2>/dev/null || true
                return 1
            fi
        fi
        printf 'source=%s archived=%s\n' \
            "$audit_retention_source" "$audit_retention_final_destination" \
            >> "$audit_retention_partial/retention-manifest.txt" || return 1
    done

    if [ "$audit_retention_created" -eq 1 ]; then
        rm -f "$audit_retention_partial/INCOMPLETE"
        printf 'complete=true\n' >> "$audit_retention_partial/retention-manifest.txt" || return 1
        if ! mv "$audit_retention_partial" "$audit_retention_root"; then
            printf 'failure=finalize snapshot\n' \
                >> "$audit_retention_partial/retention-manifest.txt" 2>/dev/null || true
            return 1
        fi
        printf '[retained] %s prior output -> %s\n' \
            "$audit_retention_helper" "$audit_retention_root" >&2
    fi
}

audit_create_retained_run_dir() {
    audit_run_workspace="$1"
    audit_run_helper="$2"
    audit_run_label="${3:-run}"

    case "$audit_run_label" in
        ""|*[!A-Za-z0-9._-]*)
            printf 'ERROR: invalid retained-run label: %s\n' "$audit_run_label" >&2
            return 1
            ;;
    esac

    # A no-source archive call performs the same workspace/tmp/helper validation
    # and creates only the safe helper root.
    audit_archive_existing "$audit_run_workspace" "$audit_run_helper" || return 1

    audit_run_workspace_physical="$(cd "$audit_run_workspace" 2>/dev/null && pwd -P)" || return 1
    audit_run_helper_root="$audit_run_workspace/tmp/$audit_run_helper"
    audit_run_base="$(date -u +%Y%m%dT%H%M%SZ)-$$-$audit_run_label"
    audit_run_dir="$audit_run_helper_root/$audit_run_base"
    audit_run_suffix=0
    while [ -e "$audit_run_dir" ] || [ -L "$audit_run_dir" ]; do
        audit_run_suffix=$((audit_run_suffix + 1))
        audit_run_dir="$audit_run_helper_root/$audit_run_base-$audit_run_suffix"
    done
    if ! mkdir "$audit_run_dir"; then
        printf 'ERROR: cannot create retained run directory: %s\n' "$audit_run_dir" >&2
        return 1
    fi
    audit_run_physical="$(cd "$audit_run_dir" 2>/dev/null && pwd -P)" || return 1
    case "$audit_run_physical" in
        "$audit_run_workspace_physical"/*) ;;
        *)
            printf 'ERROR: retained run directory escapes workspace: %s\n' "$audit_run_dir" >&2
            return 1
            ;;
    esac
    printf '%s\n' "$audit_run_physical"
}
