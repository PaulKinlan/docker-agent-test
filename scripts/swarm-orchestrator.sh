#!/bin/bash
# swarm-orchestrator.sh — Central DAG-based swarm coordinator
#
# Maps to SwarmKit's Orchestrator: watches the shared task board, detects
# completed tasks, unblocks downstream work, notifies agents of ready tasks,
# and implements fail-fast (stops the swarm on critical failure).
#
# Runs as a systemd service (swarm-orchestrator.service) polling the task
# board at a configurable interval.
#
# Environment:
#   ORCHESTRATOR_POLL_INTERVAL  — Seconds between polls (default: 30)
#   ORCHESTRATOR_FAIL_FAST      — Stop all agents on any task failure (default: true)
#
# The orchestrator does NOT run agent cycles — agents run on their own timers.
# It only manages the task board and coordinates via mail notifications.

set -euo pipefail

readonly SHARED_DIR="/home/shared"
readonly TASKS_FILE="${SHARED_DIR}/tasks.jsonl"
readonly EVENTS_FILE="${SHARED_DIR}/swarm-events.jsonl"
readonly POLL_INTERVAL="${ORCHESTRATOR_POLL_INTERVAL:-30}"
readonly FAIL_FAST="${ORCHESTRATOR_FAIL_FAST:-true}"

log() {
    echo "[$(date -Iseconds)] orchestrator: $*"
}

emit_event() {
    local event_type="$1"
    local payload="${2:-\{\}}"
    local timestamp
    timestamp="$(date -Iseconds)"
    # Build compact single-line JSONL entry
    local compact_payload
    compact_payload=$(echo "$payload" | jq -c . 2>/dev/null || echo "$payload")
    jq -cn --arg ts "$timestamp" --arg src "orchestrator" --arg evt "$event_type" \
        --argjson pay "$compact_payload" \
        '{timestamp: $ts, source: $src, event: $evt, payload: $pay}' >> "$EVENTS_FILE"
}

# Get all current task states (last entry per ID)
get_all_tasks() {
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo "[]"
        return
    fi
    jq -s 'group_by(.id) | map(last)' "$TASKS_FILE"
}

# Find tasks that are ready (pending + all blockers completed)
get_ready_tasks() {
    local all_tasks="$1"
    echo "$all_tasks" | jq '
        (map({(.id): .status}) | add // {}) as $status_map |
        map(select(
            .status == "pending" and
            ((.blocked_by // []) | all(. as $bid | $status_map[$bid] == "completed"))
        ))
    '
}

# Find tasks that just completed (completed since last poll)
# We track this via a state file
get_newly_completed() {
    local all_tasks="$1"
    local state_file="${SHARED_DIR}/.orchestrator-seen-completed"

    local completed_ids
    completed_ids=$(echo "$all_tasks" | jq -r 'map(select(.status == "completed")) | .[].id')

    local new_ids=""
    for tid in $completed_ids; do
        if ! grep -qxF "$tid" "$state_file" 2>/dev/null; then
            new_ids="$new_ids $tid"
            echo "$tid" >> "$state_file"
        fi
    done
    echo "$new_ids"
}

# Find tasks that just failed
get_newly_failed() {
    local all_tasks="$1"
    local state_file="${SHARED_DIR}/.orchestrator-seen-failed"

    local failed_ids
    failed_ids=$(echo "$all_tasks" | jq -r 'map(select(.status == "failed")) | .[].id')

    local new_ids=""
    for tid in $failed_ids; do
        if ! grep -qxF "$tid" "$state_file" 2>/dev/null; then
            new_ids="$new_ids $tid"
            echo "$tid" >> "$state_file"
        fi
    done
    echo "$new_ids"
}

# Notify an agent that they have a ready task
notify_agent_ready() {
    local agent="$1"
    local task_id="$2"
    local subject="$3"

    printf 'Task ready for you: %s\n\nTask ID: %s\nSubject: %s\n\nRun: task.sh update %s --status in_progress\nThen complete the work and run: task.sh update %s --status completed --result "summary"\n' \
        "$subject" "$task_id" "$subject" "$task_id" "$task_id" \
        | mail -s "Task ready: $subject" "$agent" 2>/dev/null || true

    log "Notified $agent: task $task_id ($subject) is ready"
}

# Stop all agent services (fail-fast)
stop_all_agents() {
    local reason="$1"
    log "FAIL-FAST: Stopping all agents — $reason"
    emit_event "swarm_halted" "$(jq -n --arg reason "$reason" '{reason: $reason}')"

    local agents
    agents=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' ' ')
    for agent in $agents; do
        log "Stopping agent@${agent}.service"
        systemctl stop "agent@${agent}.service" 2>/dev/null || true
    done

    # Notify all agents via mail
    printf 'The swarm has been halted.\n\nReason: %s\n\nAll agent services have been stopped. Manual intervention required.\n' \
        "$reason" | mail -s "SWARM HALTED: $reason" all 2>/dev/null || true
}

# Check if all tasks are terminal (completed or failed)
all_tasks_terminal() {
    local all_tasks="$1"
    local non_terminal
    non_terminal=$(echo "$all_tasks" | jq 'map(select(.status == "pending" or .status == "in_progress")) | length')
    [[ "$non_terminal" == "0" ]]
}

# --- Main loop ---

log "Starting swarm orchestrator (poll=${POLL_INTERVAL}s, fail_fast=${FAIL_FAST})"
emit_event "orchestrator_started" "{}"

# Initialize state tracking files
touch "${SHARED_DIR}/.orchestrator-seen-completed"
touch "${SHARED_DIR}/.orchestrator-seen-failed"

while true; do
    # Get current task board state
    all_tasks=$(get_all_tasks)
    task_count=$(echo "$all_tasks" | jq 'length')

    if [[ "$task_count" == "0" ]]; then
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Check for newly failed tasks
    newly_failed=$(get_newly_failed "$all_tasks")
    for tid in $newly_failed; do
        task_info=$(echo "$all_tasks" | jq -r ".[] | select(.id == \"$tid\")")
        task_subject=$(echo "$task_info" | jq -r '.subject')
        task_owner=$(echo "$task_info" | jq -r '.owner')
        task_result=$(echo "$task_info" | jq -r '.result // "no details"')

        log "Task FAILED: $tid ($task_subject) owner=$task_owner"
        emit_event "task_failed" "$(jq -n --arg id "$tid" --arg subject "$task_subject" --arg owner "$task_owner" '{id: $id, subject: $subject, owner: $owner}')"

        if [[ "$FAIL_FAST" == "true" ]]; then
            stop_all_agents "Task $tid ($task_subject) failed: $task_result"
            log "Orchestrator exiting due to fail-fast"
            exit 1
        fi
    done

    # Check for newly completed tasks
    newly_completed=$(get_newly_completed "$all_tasks")
    for tid in $newly_completed; do
        task_info=$(echo "$all_tasks" | jq -r ".[] | select(.id == \"$tid\")")
        task_subject=$(echo "$task_info" | jq -r '.subject')
        task_owner=$(echo "$task_info" | jq -r '.owner')

        log "Task COMPLETED: $tid ($task_subject) by $task_owner"
        emit_event "task_completed" "$(jq -n --arg id "$tid" --arg subject "$task_subject" --arg owner "$task_owner" '{id: $id, subject: $subject, owner: $owner}')"
    done

    # Find ready tasks and notify their owners
    ready_tasks=$(get_ready_tasks "$all_tasks")
    ready_count=$(echo "$ready_tasks" | jq 'length')

    if [[ "$ready_count" != "0" ]]; then
        echo "$ready_tasks" | jq -c '.[]' | while read -r task; do
            task_id=$(echo "$task" | jq -r '.id')
            task_owner=$(echo "$task" | jq -r '.owner')
            task_subject=$(echo "$task" | jq -r '.subject')

            # Only notify once — track notified tasks
            state_file="${SHARED_DIR}/.orchestrator-notified"
            if ! grep -qxF "$task_id" "$state_file" 2>/dev/null; then
                notify_agent_ready "$task_owner" "$task_id" "$task_subject"
                echo "$task_id" >> "$state_file"
            fi
        done
    fi

    # Check if the swarm is done (all tasks terminal)
    if all_tasks_terminal "$all_tasks"; then
        completed=$(echo "$all_tasks" | jq 'map(select(.status == "completed")) | length')
        failed=$(echo "$all_tasks" | jq 'map(select(.status == "failed")) | length')
        log "All tasks terminal: completed=$completed failed=$failed total=$task_count"
        emit_event "swarm_finished" "$(jq -n --arg completed "$completed" --arg failed "$failed" --arg total "$task_count" '{completed: $completed, failed: $failed, total: $total}')"

        if [[ "$failed" == "0" ]]; then
            log "Swarm completed successfully"
        else
            log "Swarm completed with failures"
        fi
        # Don't exit — keep running in case new tasks are added
    fi

    sleep "$POLL_INTERVAL"
done
