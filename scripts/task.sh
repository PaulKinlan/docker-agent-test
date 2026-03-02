#!/bin/bash
# task.sh — Structured task management with DAG dependencies
#
# Manages a shared task board at /home/shared/tasks.jsonl that supports
# SwarmKit-style blocked_by dependencies between tasks.
#
# Usage:
#   task.sh add <subject> --owner <agent> [--description <text>] [--blocked-by <task-id>,...]
#   task.sh list [--owner <agent>] [--status <status>]
#   task.sh ready [--owner <agent>]         List tasks whose blockers are all completed
#   task.sh update <task-id> --status <pending|in_progress|completed|failed> [--result <text>]
#   task.sh get <task-id>                   Show task details
#   task.sh graph                           Print task dependency graph
#
# Task states: pending, in_progress, completed, failed
# A task is "ready" when status=pending AND all blocked_by tasks are completed.
#
# Examples:
#   task.sh add "Build engine" --owner alice --description "Core game engine"
#   task.sh add "Build snake" --owner bob --blocked-by task-a1b2
#   task.sh update task-a1b2 --status completed --result "Engine built at /home/shared/engine/"
#   task.sh ready --owner bob

set -euo pipefail

readonly SHARED_DIR="/home/shared"
readonly TASKS_FILE="${SHARED_DIR}/tasks.jsonl"
readonly USAGE="Usage: task.sh {add|list|ready|update|get|graph} [options]"

# --- Host/container detection ---
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

# Ensure shared directory exists
if [[ ! -d "$SHARED_DIR" ]]; then
    echo "Error: Shared workspace $SHARED_DIR does not exist." >&2
    exit 1
fi

# Generate a short task ID (8 hex chars)
gen_id() {
    printf "task-%s" "$(head -c 4 /dev/urandom | xxd -p)"
}

# Read the current state of a task by ID (returns the last entry for that ID)
# Tasks are append-only JSONL — the last entry for a given ID is the current state
get_task_current() {
    local task_id="$1"
    if [[ ! -f "$TASKS_FILE" ]]; then
        return 1
    fi
    local result
    result=$(jq -c "select(.id == \"$task_id\")" "$TASKS_FILE" | tail -1)
    if [[ -z "$result" ]]; then
        return 1
    fi
    echo "$result"
}

# Get current status of a task
get_task_status() {
    local task_id="$1"
    local current
    current="$(get_task_current "$task_id")" || return 1
    echo "$current" | jq -r '.status'
}

# Build a consolidated view: last entry per task ID
get_all_current() {
    if [[ ! -f "$TASKS_FILE" ]]; then
        return 0
    fi
    # Group by ID, take the last entry for each
    jq -s 'group_by(.id) | map(last)[]' "$TASKS_FILE"
}

# --- Commands ---

cmd_add() {
    local subject="" owner="" description="" blocked_by=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --owner)
                owner="${2:-}"
                shift 2
                ;;
            --description)
                description="${2:-}"
                shift 2
                ;;
            --blocked-by)
                blocked_by="${2:-}"
                shift 2
                ;;
            -*)
                echo "Error: Unknown option '$1'." >&2
                exit 1
                ;;
            *)
                if [[ -z "$subject" ]]; then
                    subject="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$subject" ]]; then
        echo "Error: Subject is required." >&2
        echo "Usage: task.sh add <subject> --owner <agent> [--description <text>] [--blocked-by <id>,...]" >&2
        exit 1
    fi

    if [[ -z "$owner" ]]; then
        echo "Error: --owner is required." >&2
        exit 1
    fi

    local task_id
    task_id="$(gen_id)"
    local timestamp
    timestamp="$(date -Iseconds)"

    # Convert blocked_by from comma-separated to JSON array
    local blocked_by_json="[]"
    if [[ -n "$blocked_by" ]]; then
        blocked_by_json=$(echo "$blocked_by" | tr ',' '\n' | jq -R . | jq -s .)
        # Validate that all blocker IDs exist
        for bid in $(echo "$blocked_by" | tr ',' ' '); do
            if ! get_task_current "$bid" &>/dev/null; then
                echo "Warning: Blocker task '$bid' not found in task board." >&2
            fi
        done
    fi

    # Write task entry (compact single-line JSON for JSONL format)
    jq -cn \
        --arg id "$task_id" \
        --arg subject "$subject" \
        --arg description "$description" \
        --arg owner "$owner" \
        --arg status "pending" \
        --argjson blocked_by "$blocked_by_json" \
        --arg created_at "$timestamp" \
        --arg updated_at "$timestamp" \
        --arg result "" \
        '{id: $id, subject: $subject, description: $description, owner: $owner, status: $status, blocked_by: $blocked_by, created_at: $created_at, updated_at: $updated_at, result: $result}' \
        >> "$TASKS_FILE"

    echo "$task_id"
}

cmd_list() {
    local owner="" status=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --owner)  owner="${2:-}";  shift 2 ;;
            --status) status="${2:-}"; shift 2 ;;
            *)        shift ;;
        esac
    done

    if [[ ! -f "$TASKS_FILE" ]]; then
        echo "No tasks."
        exit 0
    fi

    local filter="true"
    [[ -n "$owner" ]]  && filter="$filter and .owner == \"$owner\""
    [[ -n "$status" ]] && filter="$filter and .status == \"$status\""

    jq -s "group_by(.id) | map(last) | map(select($filter))[] | \"\(.id)  \(.status | (if length < 12 then . + (\" \" * (12 - length)) else . end))  \(.owner | (if length < 12 then . + (\" \" * (12 - length)) else . end))  \(.subject)\"" "$TASKS_FILE" | sed 's/^"//;s/"$//'
}

cmd_ready() {
    local owner=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --owner) owner="${2:-}"; shift 2 ;;
            *)       shift ;;
        esac
    done

    if [[ ! -f "$TASKS_FILE" ]]; then
        echo "No tasks."
        exit 0
    fi

    # Get all current task states as a JSON array
    local all_tasks
    all_tasks=$(jq -s 'group_by(.id) | map(last)' "$TASKS_FILE")

    # Find tasks where status=pending and all blocked_by tasks are completed
    echo "$all_tasks" | jq -r --arg owner "$owner" '
        # Build a map of task_id -> status
        (map({(.id): .status}) | add // {}) as $status_map |
        .[] |
        select(.status == "pending") |
        select(if $owner != "" then .owner == $owner else true end) |
        select(
            (.blocked_by // []) | all(. as $bid | $status_map[$bid] == "completed")
        ) |
        "\(.id)  \(.owner)  \(.subject)"
    '
}

cmd_update() {
    local task_id="" status="" result=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) status="${2:-}"; shift 2 ;;
            --result) result="${2:-}"; shift 2 ;;
            -*)
                echo "Error: Unknown option '$1'." >&2
                exit 1
                ;;
            *)
                if [[ -z "$task_id" ]]; then
                    task_id="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$task_id" ]]; then
        echo "Error: Task ID is required." >&2
        exit 1
    fi

    # Validate status
    if [[ -n "$status" ]]; then
        case "$status" in
            pending|in_progress|completed|failed) ;;
            *)
                echo "Error: Invalid status '$status'. Must be: pending, in_progress, completed, failed." >&2
                exit 1
                ;;
        esac
    fi

    # Get current task state
    local current
    current="$(get_task_current "$task_id")" || {
        echo "Error: Task '$task_id' not found." >&2
        exit 1
    }

    local timestamp
    timestamp="$(date -Iseconds)"

    # Build updated entry by merging current with overrides (compact for JSONL)
    echo "$current" | jq -c \
        --arg status "${status:-}" \
        --arg result "${result:-}" \
        --arg updated_at "$timestamp" \
        '. + {updated_at: $updated_at} + (if $status != "" then {status: $status} else {} end) + (if $result != "" then {result: $result} else {} end)' \
        >> "$TASKS_FILE"

    echo "Updated $task_id: status=${status:-unchanged}"
}

cmd_get() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Error: Task ID is required." >&2
        exit 1
    fi

    local current
    current="$(get_task_current "$task_id")" || {
        echo "Error: Task '$task_id' not found." >&2
        exit 1
    }

    echo "$current" | jq .
}

cmd_graph() {
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo "No tasks."
        exit 0
    fi

    # Build a text-based dependency graph
    jq -s 'group_by(.id) | map(last)' "$TASKS_FILE" | jq -r '
        .[] |
        . as $task |
        if (.blocked_by | length) > 0 then
            .blocked_by[] | "\(.) -> \($task.id)  (\($task.subject))"
        else
            "\($task.id)  \($task.subject) [no dependencies]"
        end
    '
}

# --- Dispatch ---

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    add)    cmd_add "$@" ;;
    list)   cmd_list "$@" ;;
    ready)  cmd_ready "$@" ;;
    update) cmd_update "$@" ;;
    get)    cmd_get "$@" ;;
    graph)  cmd_graph "$@" ;;
    *)
        echo "$USAGE" >&2
        exit 1
        ;;
esac
