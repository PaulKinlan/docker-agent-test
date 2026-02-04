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

# 1. Stop and disable the agent service
if systemctl is-enabled "agent@${USERNAME}.service" &>/dev/null; then
    systemctl stop "agent@${USERNAME}.service" 2>/dev/null || true
    systemctl disable "agent@${USERNAME}.service"
    echo "  -> agent@${USERNAME}.service stopped and disabled"
else
    echo "  -> No active service found (skipping)"
fi

# 2. Remove the user
if [[ "$KEEP_HOME" == true ]]; then
    userdel "$USERNAME"
    echo "  -> User removed (home directory preserved at /home/$USERNAME)"
else
    userdel -r "$USERNAME"
    echo "  -> User and home directory removed"
fi

echo "Agent '$USERNAME' has been removed."
