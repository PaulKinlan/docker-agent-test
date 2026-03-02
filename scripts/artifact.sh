#!/bin/bash
# artifact.sh — Shared artifact registry for inter-agent file sharing
#
# Agents produce files and register them in a shared manifest so other agents
# can discover and consume them. Maps to SwarmKit's ArtifactStore concept.
#
# Usage:
#   artifact.sh register <path> [--description <text>]   Register an artifact
#   artifact.sh list [--producer <agent>]                 List artifacts
#   artifact.sh get <path>                                Get artifact metadata
#   artifact.sh read <path>                               Read artifact contents
#
# The shared workspace lives at /home/shared/ and is writable by the agents group.
# The manifest is stored at /home/shared/.manifest.jsonl (append-only JSONL).
#
# Examples:
#   artifact.sh register output/report.csv --description "Q4 sales report"
#   artifact.sh list --producer alice
#   artifact.sh read output/report.csv

set -euo pipefail

readonly SHARED_DIR="/home/shared"
readonly MANIFEST="${SHARED_DIR}/.manifest.jsonl"
readonly USAGE="Usage: artifact.sh {register|list|get|read} [options]"

# --- Host/container detection ---
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

# Ensure shared directory exists
if [[ ! -d "$SHARED_DIR" ]]; then
    echo "Error: Shared workspace $SHARED_DIR does not exist." >&2
    echo "It should be created during container build." >&2
    exit 1
fi

# --- Commands ---

cmd_register() {
    local path="" description=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description="${2:-}"
                shift 2
                ;;
            -*)
                echo "Error: Unknown option '$1'." >&2
                exit 1
                ;;
            *)
                if [[ -z "$path" ]]; then
                    path="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$path" ]]; then
        echo "Error: Path is required." >&2
        echo "Usage: artifact.sh register <path> [--description <text>]" >&2
        exit 1
    fi

    # Resolve path relative to shared dir
    local full_path="${SHARED_DIR}/${path}"
    if [[ ! -f "$full_path" ]]; then
        echo "Error: File not found: $full_path" >&2
        exit 1
    fi

    local producer
    producer="$(whoami)"
    local size
    size="$(stat -c %s "$full_path" 2>/dev/null || stat -f %z "$full_path")"
    local timestamp
    timestamp="$(date -Iseconds)"

    # Append to manifest (JSONL format)
    jq -cn --arg p "$path" --arg pr "$producer" --arg d "$description" \
        --argjson s "$size" --arg t "$timestamp" \
        '{path:$p,producer:$pr,description:$d,size_bytes:$s,created_at:$t}' >> "$MANIFEST"

    echo "Registered: $path (producer=$producer, size=$size bytes)"
}

cmd_list() {
    local producer=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --producer)
                producer="${2:-}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ ! -f "$MANIFEST" ]]; then
        echo "No artifacts registered."
        exit 0
    fi

    if [[ -n "$producer" ]]; then
        jq -r "select(.producer == \"$producer\") | \"\(.created_at)  \(.producer)  \(.path)  \(.description)\"" "$MANIFEST"
    else
        jq -r '"\(.created_at)  \(.producer)  \(.path)  \(.description)"' "$MANIFEST"
    fi
}

cmd_get() {
    local path="${1:-}"
    if [[ -z "$path" ]]; then
        echo "Error: Path is required." >&2
        echo "Usage: artifact.sh get <path>" >&2
        exit 1
    fi

    if [[ ! -f "$MANIFEST" ]]; then
        echo "No artifacts registered."
        exit 1
    fi

    # Return the most recent entry for this path (compact single-line JSON)
    jq -c "select(.path == \"$path\")" "$MANIFEST" | tail -1
}

cmd_read() {
    local path="${1:-}"
    if [[ -z "$path" ]]; then
        echo "Error: Path is required." >&2
        echo "Usage: artifact.sh read <path>" >&2
        exit 1
    fi

    local full_path="${SHARED_DIR}/${path}"
    if [[ ! -f "$full_path" ]]; then
        echo "Error: File not found: $full_path" >&2
        exit 1
    fi

    cat "$full_path"
}

# --- Dispatch ---

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    register) cmd_register "$@" ;;
    list)     cmd_list "$@" ;;
    get)      cmd_get "$@" ;;
    read)     cmd_read "$@" ;;
    *)
        echo "$USAGE" >&2
        exit 1
        ;;
esac
