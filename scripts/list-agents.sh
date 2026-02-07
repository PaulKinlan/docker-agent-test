#!/bin/bash
# list-agents.sh — List all agent users and their service status
#
# Usage: list-agents.sh

set -euo pipefail

# --- Host/container detection ---
# If not running inside the container, proxy the command through docker exec.
# Override the container name with AGENT_HOST_CONTAINER if needed.
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

AGENTS_MEMBERS=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' ' ')

if [[ -z "$AGENTS_MEMBERS" ]]; then
    echo "No agent users found."
    exit 0
fi

printf "%-20s %-12s %-10s %s\n" "USER" "SERVICE" "ACTIVE" "HOME"
printf "%-20s %-12s %-10s %s\n" "----" "-------" "------" "----"

for USERNAME in $AGENTS_MEMBERS; do
    SERVICE="agent@${USERNAME}.service"
    ACTIVE=$(timeout --kill-after=5 5 systemctl is-active "$SERVICE" 2>/dev/null || echo "inactive")
    HOME_DIR="/home/$USERNAME"
    HOME_EXISTS="yes"
    [[ -d "$HOME_DIR" ]] || HOME_EXISTS="missing"

    printf "%-20s %-12s %-10s %s (%s)\n" "$USERNAME" "$SERVICE" "$ACTIVE" "$HOME_DIR" "$HOME_EXISTS"
done
