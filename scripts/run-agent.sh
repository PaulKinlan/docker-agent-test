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
# Runs autonomous work cycles using the Claude Agent SDK via agent-loop.mjs.
# Each cycle checks mail, processes TODOs, and reports results.
#
# Exit code handling (from agent-loop.mjs):
#   0 — Success (reset backoff)
#   1 — Transient error (backoff, retry)
#   2 — Fatal error (stop retrying, halt service)
#   3 — Timeout (mild backoff, retry)
#
# Backoff: doubles sleep on consecutive transient failures, caps at max.
# Circuit breaker: after N consecutive failures, stops and mails root.

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
# Agent SDK loop — runs autonomous work cycles
# ──────────────────────────────────────────────

# Cycle interval: time to sleep between work cycles (seconds)
readonly BASE_INTERVAL="${AGENT_CYCLE_INTERVAL:-300}"

# Backoff configuration
readonly BACKOFF_MAX="${AGENT_BACKOFF_MAX:-1800}"          # Max sleep: 30 minutes
readonly CIRCUIT_BREAKER="${AGENT_CIRCUIT_BREAKER:-5}"      # Stop after N consecutive failures

# Export variables needed by the Node.js agent-loop script
export AGENT_USER
export NODE_PATH="/usr/lib/node_modules"

log "Agent running (cycle every ${BASE_INTERVAL}s, backoff_max=${BACKOFF_MAX}s, circuit_breaker=${CIRCUIT_BREAKER})"

consecutive_failures=0
current_interval="$BASE_INTERVAL"

while true; do
    log "Starting work cycle (failures=$consecutive_failures, interval=${current_interval}s)"

    exit_code=0
    node /usr/local/bin/agent-loop.mjs 2>&1 | tee -a "$AGENT_LOG" || exit_code=$?

    case "$exit_code" in
        0)
            # Success — reset backoff
            log "Work cycle completed successfully"
            consecutive_failures=0
            current_interval="$BASE_INTERVAL"
            ;;
        1)
            # Transient error — backoff and retry
            ((consecutive_failures++)) || true
            log "Work cycle failed (transient, exit=1, consecutive=$consecutive_failures)"

            # Exponential backoff: double the interval, cap at max
            current_interval=$(( current_interval * 2 ))
            if (( current_interval > BACKOFF_MAX )); then
                current_interval="$BACKOFF_MAX"
            fi
            log "Backoff: next interval=${current_interval}s"
            ;;
        2)
            # Fatal error — stop the agent
            log "FATAL: Work cycle returned exit=2 (unrecoverable). Stopping agent."
            printf 'Agent %s has stopped due to a fatal error (exit code 2).\n\nThis usually means an invalid API key or misconfigured model.\nCheck logs: journalctl -u agent@%s.service\n\nThe agent service will not restart until the issue is fixed.\n' \
                "$AGENT_USER" "$AGENT_USER" \
                | mail -s "FATAL: Agent $AGENT_USER stopped" root 2>/dev/null || true
            exit 2
            ;;
        3)
            # Timeout — mild backoff
            ((consecutive_failures++)) || true
            log "Work cycle timed out (exit=3, consecutive=$consecutive_failures)"
            # Add 50% to interval on timeout
            current_interval=$(( current_interval + current_interval / 2 ))
            if (( current_interval > BACKOFF_MAX )); then
                current_interval="$BACKOFF_MAX"
            fi
            ;;
        *)
            # Unknown exit code — treat as transient
            ((consecutive_failures++)) || true
            log "Work cycle failed (unknown exit=$exit_code, consecutive=$consecutive_failures)"
            current_interval=$(( current_interval * 2 ))
            if (( current_interval > BACKOFF_MAX )); then
                current_interval="$BACKOFF_MAX"
            fi
            ;;
    esac

    # Circuit breaker: stop after too many consecutive failures
    if (( consecutive_failures >= CIRCUIT_BREAKER )); then
        log "CIRCUIT BREAKER: $consecutive_failures consecutive failures. Stopping agent."
        printf 'Agent %s has been stopped by the circuit breaker after %d consecutive failures.\n\nLast exit code: %d\nCheck logs: journalctl -u agent@%s.service\n\nTo restart: systemctl start agent@%s.service\n' \
            "$AGENT_USER" "$consecutive_failures" "$exit_code" "$AGENT_USER" "$AGENT_USER" \
            | mail -s "CIRCUIT BREAKER: Agent $AGENT_USER stopped" root 2>/dev/null || true
        exit 1
    fi

    # Wait for next cycle — use inotifywait to wake immediately on new mail
    # instead of sleeping the full interval. Falls back to plain sleep if
    # inotifywait is unavailable or Maildir doesn't exist.
    MAILDIR_NEW="$HOME/Maildir/new"
    if command -v inotifywait &>/dev/null && [[ -d "$MAILDIR_NEW" ]]; then
        log "Waiting up to ${current_interval}s (or until new mail arrives)"
        if inotifywait -t "$current_interval" -e create -e moved_to "$MAILDIR_NEW" 2>/dev/null; then
            log "Woke up: new mail detected"
        fi
    else
        sleep "$current_interval"
    fi
done
