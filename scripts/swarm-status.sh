#!/bin/bash
# swarm-status.sh — Aggregate swarm status across all agents
#
# Maps to SwarmKit's SwarmResult: shows task board status, agent health,
# cost totals, and recent events in a single view.
#
# Usage:
#   swarm-status.sh                  Full status overview
#   swarm-status.sh --tasks          Task board summary only
#   swarm-status.sh --costs          Cost aggregation only
#   swarm-status.sh --events [N]     Last N swarm events (default: 20)
#   swarm-status.sh --json           Output everything as JSON

set -euo pipefail

readonly SHARED_DIR="/home/shared"
readonly TASKS_FILE="${SHARED_DIR}/tasks.jsonl"
readonly EVENTS_FILE="${SHARED_DIR}/swarm-events.jsonl"

# --- Host/container detection ---
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

# Parse args
MODE="full"
EVENT_COUNT=20
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tasks)  MODE="tasks";  shift ;;
        --costs)  MODE="costs";  shift ;;
        --events) MODE="events"; EVENT_COUNT="${2:-20}"; shift; shift 2>/dev/null || true ;;
        --json)   JSON_OUTPUT=true; shift ;;
        *)        shift ;;
    esac
done

# --- Task board summary ---
show_tasks() {
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo "Task Board: No tasks"
        return
    fi

    local all_tasks
    all_tasks=$(jq -s 'group_by(.id) | map(last)' "$TASKS_FILE")
    local total pending in_progress completed failed
    total=$(echo "$all_tasks" | jq 'length')
    pending=$(echo "$all_tasks" | jq 'map(select(.status == "pending")) | length')
    in_progress=$(echo "$all_tasks" | jq 'map(select(.status == "in_progress")) | length')
    completed=$(echo "$all_tasks" | jq 'map(select(.status == "completed")) | length')
    failed=$(echo "$all_tasks" | jq 'map(select(.status == "failed")) | length')

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --argjson total "$total" --argjson pending "$pending" \
            --argjson in_progress "$in_progress" --argjson completed "$completed" \
            --argjson failed "$failed" \
            '{total: $total, pending: $pending, in_progress: $in_progress, completed: $completed, failed: $failed}'
        return
    fi

    echo "=== Task Board ==="
    echo "  Total:       $total"
    echo "  Pending:     $pending"
    echo "  In Progress: $in_progress"
    echo "  Completed:   $completed"
    echo "  Failed:      $failed"

    # Show overall result
    if (( total > 0 )) && (( pending == 0 )) && (( in_progress == 0 )); then
        if (( failed == 0 )); then
            echo "  Result:      SUCCESS (all tasks completed)"
        else
            echo "  Result:      PARTIAL ($failed task(s) failed)"
        fi
    elif (( total > 0 )); then
        echo "  Result:      IN PROGRESS"
    fi
    echo ""

    # List active tasks
    if (( in_progress > 0 )); then
        echo "  Active tasks:"
        echo "$all_tasks" | jq -r 'map(select(.status == "in_progress")) | .[] | "    \(.id)  \(.owner)  \(.subject)"'
        echo ""
    fi
}

# --- Cost aggregation ---
show_costs() {
    local total_cost=0
    local total_cycles=0
    local total_turns=0

    AGENTS_MEMBERS=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' ' ')

    if [[ -z "$AGENTS_MEMBERS" ]]; then
        echo "No agents found."
        return
    fi

    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo "=== Cost Summary ==="
        printf "  %-16s %8s %8s %10s\n" "AGENT" "CYCLES" "TURNS" "COST (USD)"
        printf "  %-16s %8s %8s %10s\n" "-----" "------" "-----" "----------"
    fi

    local json_entries=""

    for agent in $AGENTS_MEMBERS; do
        local results_dir="/home/${agent}/.agent-results"
        local agent_cost=0 agent_cycles=0 agent_turns=0

        if [[ -d "$results_dir" ]]; then
            for result_file in "$results_dir"/cycle-*.json; do
                [[ -f "$result_file" ]] || continue
                ((agent_cycles++)) || true

                local cost turns
                cost=$(jq -r '.cost_usd // 0' "$result_file" 2>/dev/null || echo 0)
                turns=$(jq -r '.turns // 0' "$result_file" 2>/dev/null || echo 0)

                agent_cost=$(awk "BEGIN {printf \"%.4f\", $agent_cost + $cost}")
                agent_turns=$(( agent_turns + turns ))
            done
        fi

        total_cost=$(awk "BEGIN {printf \"%.4f\", $total_cost + $agent_cost}")
        total_cycles=$(( total_cycles + agent_cycles ))
        total_turns=$(( total_turns + agent_turns ))

        if [[ "$JSON_OUTPUT" == "true" ]]; then
            entry=$(jq -n --arg agent "$agent" --argjson cycles "$agent_cycles" \
                --argjson turns "$agent_turns" --arg cost "$agent_cost" \
                '{agent: $agent, cycles: $cycles, turns: $turns, cost_usd: ($cost | tonumber)}')
            if [[ -n "$json_entries" ]]; then
                json_entries="${json_entries},${entry}"
            else
                json_entries="$entry"
            fi
        else
            printf "  %-16s %8d %8d %10s\n" "$agent" "$agent_cycles" "$agent_turns" "\$$agent_cost"
        fi
    done

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --arg total_cost "$total_cost" --argjson total_cycles "$total_cycles" \
            --argjson total_turns "$total_turns" --argjson agents "[$json_entries]" \
            '{total_cost_usd: ($total_cost | tonumber), total_cycles: $total_cycles, total_turns: $total_turns, agents: $agents}'
    else
        printf "  %-16s %8s %8s %10s\n" "-----" "------" "-----" "----------"
        printf "  %-16s %8d %8d %10s\n" "TOTAL" "$total_cycles" "$total_turns" "\$$total_cost"
        echo ""
    fi
}

# --- Recent events ---
show_events() {
    local count="$1"

    # Collect events from both swarm-level and per-agent event logs
    {
        if [[ -f "$EVENTS_FILE" ]]; then
            cat "$EVENTS_FILE"
        fi

        # Per-agent events
        AGENTS_MEMBERS=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' ' ')
        for agent in $AGENTS_MEMBERS; do
            local events_file="/home/${agent}/.agent-events.jsonl"
            if [[ -f "$events_file" ]]; then
                cat "$events_file"
            fi
        done
    } | jq -s 'sort_by(.timestamp) | .[-'"$count"':]' 2>/dev/null | {
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            cat
        else
            echo "=== Recent Events (last $count) ==="
            jq -r '.[] | "  \(.timestamp)  \(.agent // .source)  \(.event)  \(del(.timestamp, .agent, .source, .event) | to_entries | map("\(.key)=\(.value)") | join(" "))"' 2>/dev/null || echo "  No events."
            echo ""
        fi
    }
}

# --- Agent health (abbreviated) ---
show_health() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        /usr/local/bin/check-health.sh --json 2>/dev/null || true
    else
        echo "=== Agent Health ==="
        /usr/local/bin/check-health.sh 2>/dev/null | sed 's/^/  /' || true
        echo ""
    fi
}

# --- Dispatch ---

case "$MODE" in
    tasks)
        show_tasks
        ;;
    costs)
        show_costs
        ;;
    events)
        show_events "$EVENT_COUNT"
        ;;
    full)
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            # Combine all sections into one JSON object
            tasks_json=$(show_tasks)
            costs_json=$(show_costs)
            events_json=$(show_events "$EVENT_COUNT")
            health_json=$(show_health)
            jq -n \
                --argjson tasks "$tasks_json" \
                --argjson costs "$costs_json" \
                --argjson events "$events_json" \
                --argjson health "$health_json" \
                '{tasks: $tasks, costs: $costs, events: $events, health: $health}'
        else
            show_tasks
            show_health
            show_costs
            show_events "$EVENT_COUNT"
        fi
        ;;
esac
