#!/usr/bin/env bash
# Shared .env loader for all audit scripts.
# Source this file: source "$(dirname "$0")/load-env.sh"
#
# Loading priority (first-found wins per variable):
#   1. Already-exported shell environment variables
#   2. $WORKSPACE/.env                                     (per-audit overrides)
#   3. $SKILL_DIR/.env                                     (active runtime's skill)
#   4. Active agent global (Hermes, Codex, Claude custom/default config, or OpenClaw)
#   5. ~/.env                                              (user fallback)

_load_env_file() {
    local envfile="$1"
    [ -f "$envfile" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            val="${val#\"}" ; val="${val%\"}"
            val="${val#\'}" ; val="${val%\'}"
            if [ -z "${!key+x}" ]; then
                export "$key=$val"
            fi
        fi
    done < "$envfile"
}

# Auto-detect SKILL_DIR if not already set
if [ -z "${SKILL_DIR:-}" ]; then
    if [ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/chains.json" ]; then
        SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    elif [ -f "$(cd "$(dirname "$0")/.." && pwd)/config/chains.json" ]; then
        SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
