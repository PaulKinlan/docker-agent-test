#!/bin/bash
# run-agent.sh — Agent runner (executed per-user by agent@<user>.service)
#
# This script is the entrypoint for each agent. It runs as the agent user
# with the user's home directory as the working directory.
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
else
    log "  Claude:  $CLAUDE_CONFIG (not found)"
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
