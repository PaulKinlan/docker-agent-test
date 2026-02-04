#!/bin/bash
# agent-manager.sh — Boot-time reconciliation of agent services
#
# Enumerates all users in the 'agents' group and ensures their
# agent@<username>.service is enabled and running.
# Runs once at boot via agent-manager.service (Type=oneshot).

set -euo pipefail

echo "agent-manager: Reconciling agent services..."

# Get all members of the 'agents' group
AGENTS_MEMBERS=$(getent group agents | cut -d: -f4 | tr ',' ' ')

if [[ -z "$AGENTS_MEMBERS" ]]; then
    echo "agent-manager: No agent users found in 'agents' group."
    exit 0
fi

STARTED=0
FAILED=0

for USERNAME in $AGENTS_MEMBERS; do
    # Sanity check: user still exists and has a home dir
    if ! id "$USERNAME" &>/dev/null; then
        echo "  [SKIP] $USERNAME — user does not exist"
        continue
    fi

    if [[ ! -d "/home/$USERNAME" ]]; then
        echo "  [SKIP] $USERNAME — no home directory"
        continue
    fi

    # Enable and start (idempotent)
    systemctl enable "agent@${USERNAME}.service" 2>/dev/null || true

    if systemctl start "agent@${USERNAME}.service" 2>/dev/null; then
        echo "  [OK]   $USERNAME — agent started"
        ((STARTED++))
    else
        echo "  [FAIL] $USERNAME — agent failed to start"
        ((FAILED++))
    fi
done

echo "agent-manager: Done. Started=$STARTED Failed=$FAILED"
