#!/bin/bash
# stop-swarm.sh — Stop all agent services and the orchestrator
#
# Usage: stop-swarm.sh [--reason <text>]
#
# Implements SwarmKit's cascading cancellation: stops all agents and the
# orchestrator, optionally recording a reason in the swarm event log.
#
# Examples:
#   stop-swarm.sh
#   stop-swarm.sh --reason "Critical bug found in task output"

set -euo pipefail

readonly SHARED_DIR="/home/shared"
readonly EVENTS_FILE="${SHARED_DIR}/swarm-events.jsonl"

# --- Host/container detection ---
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

# Parse args
REASON="Manual stop requested"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reason)
            REASON="${2:-Manual stop}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "Stopping swarm: $REASON"

# Emit event
timestamp="$(date -Iseconds)"
if [[ -d "$SHARED_DIR" ]]; then
    jq -cn --arg ts "$timestamp" --arg reason "$REASON" \
        '{timestamp: $ts, source: "stop-swarm", event: "swarm_halted", payload: {reason: $reason}}' \
        >> "$EVENTS_FILE" 2>/dev/null || true
fi

# Stop orchestrator
echo "Stopping swarm-orchestrator.service..."
systemctl stop swarm-orchestrator.service 2>/dev/null || true

# Stop all agent services
AGENTS=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' ' ')
if [[ -z "$AGENTS" ]]; then
    echo "No agents found."
    exit 0
fi

STOPPED=0
for agent in $AGENTS; do
    echo "Stopping agent@${agent}.service..."
    if systemctl stop "agent@${agent}.service" 2>/dev/null; then
        ((STOPPED++)) || true
    fi
done

# Notify all agents via mail
printf 'The swarm has been stopped.\n\nReason: %s\nTime: %s\nAgents stopped: %d\n' \
    "$REASON" "$timestamp" "$STOPPED" \
    | mail -s "Swarm stopped" all 2>/dev/null || true

echo "Swarm stopped. $STOPPED agent(s) halted."
