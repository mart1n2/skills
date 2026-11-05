#!/usr/bin/env bash
# Shared .env loader for all audit scripts.
# Source this file: source "$(dirname "$0")/load-env.sh"
#
# Portable: uses only POSIX parameter expansion so it can be sourced from
# bash 3.2+ and from an interactive zsh (for ad hoc cast/curl calls). No
# BASH_REMATCH, no ${!indirect}, no arrays.
#
# Loading priority (first-found wins per variable):
#   1. Already-exported shell environment variables
#   2. $WORKSPACE/.env                                     (per-audit overrides)
#   3. $SKILL_DIR/.env                                     (active runtime's skill)
#   4. Active agent global (Hermes, Codex, Claude custom/default config, or OpenClaw)
#   5. ~/.env                                              (user fallback)

_load_env_file() {
    envfile="$1"
    [ -f "$envfile" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|\#*) continue ;;
        esac
        # Strip leading whitespace, then skip comments and lines without '='.
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            ''|\#*) continue ;;
            *=*) ;;
            *) continue ;;
        esac
        key="${line%%=*}"
        val="${line#*=}"
        # Only accept a valid identifier; this also keeps the eval below safe.
        case "$key" in
            ''|*[!A-Za-z0-9_]*|[0-9]*) continue ;;
        esac
        val="${val#\"}" ; val="${val%\"}"
        val="${val#\'}" ; val="${val%\'}"
        # Set only when the variable is currently unset (shell env wins).
        if [ -z "$(eval "printf '%s' \"\${$key+x}\"")" ]; then
            export "$key=$val"
        fi
    done < "$envfile"
}

# Resolve the path of this file under bash or zsh.
_load_env_self=""
if [ -n "${BASH_SOURCE:-}" ]; then
    _load_env_self="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
    _load_env_self="$(eval 'printf "%s" "${(%):-%x}"')"
fi
[ -n "$_load_env_self" ] || _load_env_self="$0"

# Auto-detect SKILL_DIR if not already set
if [ -z "${SKILL_DIR:-}" ]; then
    _load_env_candidate="$(cd "$(dirname "$_load_env_self")/.." 2>/dev/null && pwd)"
    if [ -n "$_load_env_candidate" ] && [ -f "$_load_env_candidate/config/chains.json" ]; then
        SKILL_DIR="$_load_env_candidate"
    fi
fi

# Load in priority order (first-found wins per variable). Never scan another
# runtime's skill directory: Claude, Codex, and Hermes may keep different keys.
[ -n "${WORKSPACE:-}" ] && _load_env_file "$WORKSPACE/.env"
[ -n "${SKILL_DIR:-}" ] && _load_env_file "$SKILL_DIR/.env"
[ -n "${HERMES_SESSION_ID:-}" ] && _load_env_file "${HERMES_HOME:-$HOME/.hermes}/.env"
[ -z "${HERMES_SESSION_ID:-}" ] && [ -n "${CODEX_SHELL:-}" ] && \
    _load_env_file "${CODEX_HOME:-$HOME/.codex}/.env"
[ -z "${HERMES_SESSION_ID:-}" ] && [ -z "${CODEX_SHELL:-}" ] && \
    _load_env_file "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.env"
[ -n "${OPENCLAW_HOME:-}" ] && _load_env_file "$OPENCLAW_HOME/.env"
_load_env_file "$HOME/.env"
unset _load_env_self _load_env_candidate
