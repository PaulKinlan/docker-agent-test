#!/bin/bash
# check-health.sh — Agent health monitoring via heartbeat files
#
# Each agent writes ~/.agent-heartbeat with a timestamp during every cycle.
# This script checks all agents and flags those whose heartbeat is stale.
#
# Usage:
#   check-health.sh                    Show health status for all agents
#   check-health.sh --stale-after 600  Flag agents idle longer than 600s (default: 900)
#   check-health.sh --json             Output as JSON
#
# Exit codes:
#   0 — All agents healthy
#   1 — One or more agents unhealthy

set -euo pipefail

# --- Host/container detection ---
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

# Defaults
STALE_THRESHOLD=900  # 15 minutes
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stale-after)
            STALE_THRESHOLD="${2:-900}"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

AGENTS_MEMBERS=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' ' ')

if [[ -z "$AGENTS_MEMBERS" ]]; then
    echo "No agents found."
    exit 0
fi

NOW=$(date +%s)
UNHEALTHY=0
JSON_ENTRIES=""

if [[ "$JSON_OUTPUT" == "false" ]]; then
    printf "%-16s %-10s %-12s %-8s %-20s %s\n" "AGENT" "SERVICE" "HEARTBEAT" "STALE?" "LAST PHASE" "LAST SEEN"
    printf "%-16s %-10s %-12s %-8s %-20s %s\n" "-----" "-------" "---------" "------" "----------" "---------"
fi

for agent in $AGENTS_MEMBERS; do
    HEARTBEAT_FILE="/home/${agent}/.agent-heartbeat"
    SERVICE="agent@${agent}.service"
    SERVICE_ACTIVE=$(systemctl is-active "$SERVICE" 2>/dev/null | head -1) || true
    [[ -z "$SERVICE_ACTIVE" ]] && SERVICE_ACTIVE="inactive"

    if [[ ! -f "$HEARTBEAT_FILE" ]]; then
        status="no-heartbeat"
        phase="unknown"
        last_seen="never"
        is_stale="YES"
        ((UNHEALTHY++)) || true
    else
        # Parse heartbeat JSON
        hb_json=$(cat "$HEARTBEAT_FILE" 2>/dev/null || echo '{}')
        hb_timestamp=$(echo "$hb_json" | jq -r '.timestamp // ""' 2>/dev/null || echo "")
        phase=$(echo "$hb_json" | jq -r '.phase // "unknown"' 2>/dev/null || echo "unknown")

        if [[ -z "$hb_timestamp" ]]; then
            status="invalid"
            last_seen="invalid"
            is_stale="YES"
            ((UNHEALTHY++)) || true
        else
            # Convert ISO timestamp to epoch
            hb_epoch=$(date -d "$hb_timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${hb_timestamp%%+*}" +%s 2>/dev/null || echo "0")
            age=$(( NOW - hb_epoch ))
            last_seen="${age}s ago"

            if (( age > STALE_THRESHOLD )); then
                status="stale"
                is_stale="YES"
                ((UNHEALTHY++)) || true
            else
                status="healthy"
                is_stale="no"
            fi
        fi
    fi

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        entry=$(jq -n \
            --arg agent "$agent" \
            --arg service "$SERVICE_ACTIVE" \
            --arg status "$status" \
            --arg phase "$phase" \
            --arg last_seen "$last_seen" \
            --argjson stale "$([ "$is_stale" = "YES" ] && echo true || echo false)" \
            '{agent: $agent, service: $service, status: $status, phase: $phase, last_seen: $last_seen, stale: $stale}')
        if [[ -n "$JSON_ENTRIES" ]]; then
            JSON_ENTRIES="${JSON_ENTRIES},${entry}"
        else
            JSON_ENTRIES="$entry"
        fi
    else
        printf "%-16s %-10s %-12s %-8s %-20s %s\n" "$agent" "$SERVICE_ACTIVE" "$status" "$is_stale" "$phase" "$last_seen"
    fi
done

if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "[${JSON_ENTRIES}]" | jq .
fi

if (( UNHEALTHY > 0 )); then
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo ""
        echo "$UNHEALTHY agent(s) unhealthy (stale threshold: ${STALE_THRESHOLD}s)"
    fi
    exit 1
fi

exit 0
