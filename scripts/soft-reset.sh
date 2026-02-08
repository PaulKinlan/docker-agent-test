#!/bin/bash
# soft-reset.sh — Remove all agents, clear logs and mail inside the container
#
# Usage: soft-reset.sh [--yes]
#
# This script:
#   1. Removes all agent users (stops services, deletes users and home dirs)
#   2. Clears the systemd journal
#   3. Empties the mail spool

set -euo pipefail

# --- Host/container detection ---
# If not running inside the container, proxy the command through docker exec.
# Override the container name with AGENT_HOST_CONTAINER if needed.
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y) SKIP_CONFIRM=true ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# --- Confirmation ---
if [[ "$SKIP_CONFIRM" != true ]]; then
    echo "This will:"
    echo "  - Remove all agent users (services, accounts, and home directories)"
    echo "  - Clear all systemd journal logs"
    echo "  - Empty the mail spool"
    echo ""
    read -r -p "Continue? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# --- Remove all agents ---
AGENTS_MEMBERS=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' ' ')

if [[ -n "$AGENTS_MEMBERS" ]]; then
    for USERNAME in $AGENTS_MEMBERS; do
        echo "Removing agent: $USERNAME"
        /usr/local/bin/remove-agent.sh "$USERNAME"
    done
else
    echo "No agent users found."
fi

# --- Regenerate aliases (clears the 'all' group alias) ---
/usr/local/bin/sync-aliases.sh

# --- Clear journal logs ---
echo "Clearing systemd journal..."
journalctl --rotate --vacuum-time=1s 2>/dev/null || true
echo "  -> Journal cleared"

# --- Empty mail spool ---
echo "Clearing mail spool..."
rm -f /var/spool/mail/*
echo "  -> Mail spool cleared"

echo ""
echo "Soft reset complete."
