#!/bin/bash
# remove-agent.sh — Remove an agent user and its service
#
# Usage: remove-agent.sh <username> [--keep-home]
#
# This script:
#   1. Stops and disables the agent@<username> systemd service
#   2. Removes the Linux user
#   3. Optionally preserves the home directory (--keep-home)

set -euo pipefail

# --- Host/container detection ---
# If not running inside the container, proxy the command through docker exec.
# Override the container name with AGENT_HOST_CONTAINER if needed.
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

KEEP_HOME=false

if [[ $# -lt 1 ]]; then
    echo "Usage: remove-agent.sh <username> [--keep-home]" >&2
    exit 1
fi

USERNAME="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-home) KEEP_HOME=true ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# Check if user exists
if ! id "$USERNAME" &>/dev/null; then
    echo "Error: User '$USERNAME' does not exist." >&2
    exit 1
fi

echo "Removing agent user: $USERNAME"

# 1. Stop the mail watcher and agent process (PID-based, matches nohup+su launch)
echo "  Stopping processes..."

# Stop mail watcher
if [[ -f "/run/mail-watcher-${USERNAME}.pid" ]]; then
    WATCHER_PID_VAL="$(cat "/run/mail-watcher-${USERNAME}.pid")"
    if kill -0 "$WATCHER_PID_VAL" 2>/dev/null; then
        kill "$WATCHER_PID_VAL" 2>/dev/null || true
        echo "  -> Mail watcher stopped (PID $WATCHER_PID_VAL)"
    fi
    rm -f "/run/mail-watcher-${USERNAME}.pid"
fi

# Stop agent process
if [[ -f "/run/agent-${USERNAME}.pid" ]]; then
    AGENT_PID_VAL="$(cat "/run/agent-${USERNAME}.pid")"
    if kill -0 "$AGENT_PID_VAL" 2>/dev/null; then
        kill "$AGENT_PID_VAL" 2>/dev/null || true
        echo "  -> Agent process stopped (PID $AGENT_PID_VAL)"
    fi
    rm -f "/run/agent-${USERNAME}.pid"
fi

# Also stop via systemd if enabled (defensive — agent-manager.sh on older images)
if timeout --kill-after=5 5 systemctl is-enabled "agent@${USERNAME}.service" &>/dev/null; then
    timeout --kill-after=5 10 systemctl stop "agent@${USERNAME}.service" 2>/dev/null || true
    timeout --kill-after=5 10 systemctl disable "agent@${USERNAME}.service" 2>/dev/null || true
    echo "  -> agent@${USERNAME}.service stopped and disabled"
fi

# 2. Find persona groups the user belongs to (excluding agents and their primary group)
#    so we can clean up empty groups after removal.
PERSONA_GROUPS=""
USER_GROUPS=$(id -Gn "$USERNAME" 2>/dev/null || true)
PRIMARY_GROUP=$(id -gn "$USERNAME" 2>/dev/null || true)
for GRP in $USER_GROUPS; do
    [[ "$GRP" == "agents" || "$GRP" == "$PRIMARY_GROUP" ]] && continue
    PERSONA_GROUPS="$PERSONA_GROUPS $GRP"
done

# 3. Remove the user
if [[ "$KEEP_HOME" == true ]]; then
    userdel "$USERNAME"
    echo "  -> User removed (home directory preserved at /home/$USERNAME)"
else
    userdel -r "$USERNAME"
    echo "  -> User and home directory removed"
fi

# 4. Clean up empty persona groups
for GRP in $PERSONA_GROUPS; do
    MEMBERS=$(getent group "$GRP" 2>/dev/null | cut -d: -f4)
    if [[ -z "$MEMBERS" ]]; then
        groupdel "$GRP" 2>/dev/null || true
        echo "  -> Removed empty persona group: $GRP"
    fi
done

# Regenerate mail aliases (removes user from 'all' and persona aliases)
/usr/local/bin/sync-aliases.sh

echo "Agent '$USERNAME' has been removed."
