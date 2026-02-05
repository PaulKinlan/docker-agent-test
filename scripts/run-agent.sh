#!/bin/bash
# run-agent.sh — Agent runner (executed per-user by agent@<user>.service)
#
# This script is the entrypoint for each agent. It runs as the agent user
# with the user's home directory as the working directory.
#
# API Key Loading:
#   1. Global defaults from /etc/agent-api-keys/global.env (if exists)
#   2. Per-agent overrides from ~/.claude/api-keys.env (if exists)
#   Per-agent keys take precedence over global keys.
#
# Currently a placeholder that logs heartbeats. Replace the main loop
# with your actual agent binary (e.g., claude-code, or another system).

set -euo pipefail

AGENT_USER="$(whoami)"
AGENT_HOME="$(pwd)"
AGENT_LOG="/home/${AGENT_USER}/.agent.log"

log() {
    echo "[$(date -Iseconds)] agent(${AGENT_USER}): $*" | tee -a "$AGENT_LOG"
}

log "Starting agent"
log "  User:    $AGENT_USER"
log "  Home:    $AGENT_HOME"
log "  PID:     $$"

# Read agent config if it exists
AGENTS_MD="/home/${AGENT_USER}/agents.md"
if [[ -f "$AGENTS_MD" ]]; then
    log "  Config:  $AGENTS_MD (found)"
else
    log "  Config:  $AGENTS_MD (not found)"
fi

CLAUDE_CONFIG="/home/${AGENT_USER}/.claude/config.json"
if [[ -f "$CLAUDE_CONFIG" ]]; then
    log "  Claude:  $CLAUDE_CONFIG (found)"
    # Read persona from config
    PERSONA="$(grep -o '"persona"[[:space:]]*:[[:space:]]*"[^"]*"' "$CLAUDE_CONFIG" | head -1 | sed 's/.*"persona"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')" || true
    if [[ -n "${PERSONA:-}" ]]; then
        log "  Persona: $PERSONA"
    fi
else
    log "  Claude:  $CLAUDE_CONFIG (not found)"
fi

# Load API keys
# Function to load env file and export variables
load_env_file() {
    local env_file="$1"
    local source_name="$2"
    local count=0
    if [[ -f "$env_file" ]] && [[ -r "$env_file" ]]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            # Remove leading/trailing whitespace from key
            key="$(echo "$key" | xargs)"
            # Export the variable
            export "$key=$value"
            ((count++)) || true
        done < "$env_file"
        if [[ $count -gt 0 ]]; then
            log "  API keys: loaded $count from $source_name"
        fi
        return 0
    fi
    return 1
}

# 1. Load global API keys (defaults for all agents)
GLOBAL_API_KEYS="/etc/agent-api-keys/global.env"
if [[ -f "$GLOBAL_API_KEYS" ]]; then
    load_env_file "$GLOBAL_API_KEYS" "global" || true
else
    log "  API keys: no global config"
fi

# 2. Load per-agent API keys (overrides global)
AGENT_API_KEYS="/home/${AGENT_USER}/.claude/api-keys.env"
if [[ -f "$AGENT_API_KEYS" ]] && [[ -r "$AGENT_API_KEYS" ]]; then
    load_env_file "$AGENT_API_KEYS" "agent" || true
else
    log "  API keys: no agent-specific config"
fi

# ──────────────────────────────────────────────
# TODO: Replace this loop with your agent binary
# e.g.:  exec claude-code --config "$CLAUDE_CONFIG"
# ──────────────────────────────────────────────

HEARTBEAT_INTERVAL=60  # seconds

log "Agent running (heartbeat every ${HEARTBEAT_INTERVAL}s)"

while true; do
    sleep "$HEARTBEAT_INTERVAL"
    log "Heartbeat — alive"
done
