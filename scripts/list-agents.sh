#!/bin/bash
# list-agents.sh — List all agent users and their service status
#
# Usage: list-agents.sh

set -euo pipefail

AGENTS_MEMBERS=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' ' ')

if [[ -z "$AGENTS_MEMBERS" ]]; then
    echo "No agent users found."
    exit 0
fi

printf "%-20s %-12s %-10s %s\n" "USER" "SERVICE" "ACTIVE" "HOME"
printf "%-20s %-12s %-10s %s\n" "----" "-------" "------" "----"

for USERNAME in $AGENTS_MEMBERS; do
    SERVICE="agent@${USERNAME}.service"
    ACTIVE=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "inactive")
    HOME_DIR="/home/$USERNAME"
    HOME_EXISTS="yes"
    [[ -d "$HOME_DIR" ]] || HOME_EXISTS="missing"

    printf "%-20s %-12s %-10s %s (%s)\n" "$USERNAME" "$SERVICE" "$ACTIVE" "$HOME_DIR" "$HOME_EXISTS"
done
