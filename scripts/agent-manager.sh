#!/bin/bash
# agent-manager.sh — Boot-time reconciliation of agent services
#
# Enumerates all users in the 'agents' group and ensures their
# agent@<username>.service is enabled and running.
# Runs once at boot via agent-manager.service (Type=oneshot).

set -euo pipefail

echo "agent-manager: Starting at $(date -Iseconds)"

# Ensure /home/shared exists. The Docker volume mount (./home:/home) overwrites
# the build-time directory, so we must re-create it at every boot.
if [[ ! -d /home/shared ]]; then
    mkdir -p /home/shared
    chgrp agents /home/shared
    chmod 2775 /home/shared
    echo "agent-manager: Created /home/shared (mode 2775, group=agents)"
fi

echo "agent-manager: Reconciling agent services..."

# Get all members of the 'agents' group
echo "agent-manager: Querying 'agents' group membership..."
AGENTS_MEMBERS=$(getent group agents | cut -d: -f4 | tr ',' ' ')

if [[ -z "$AGENTS_MEMBERS" ]]; then
    echo "agent-manager: No agent users found in 'agents' group."
    echo "agent-manager: Finished at $(date -Iseconds)"
    exit 0
fi

echo "agent-manager: Found agents: ${AGENTS_MEMBERS}"

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

    # Ensure Maildir structure exists (may be missing if home was preserved from before migration)
    MAILDIR="/home/$USERNAME/Maildir"
    if [[ ! -d "$MAILDIR/new" ]]; then
        mkdir -p "$MAILDIR/new" "$MAILDIR/cur" "$MAILDIR/tmp"
        chown -R "$USERNAME:$USERNAME" "$MAILDIR"
        chmod 700 "$MAILDIR"
        echo "  [INIT] $USERNAME — created Maildir"
    fi

    # Enable and start (idempotent, with timeout to avoid D-Bus hangs)
    # --kill-after sends SIGKILL if SIGTERM doesn't work (e.g., stuck D-Bus call)
    echo "  Enabling agent@${USERNAME}.service..."
    timeout --kill-after=5 10 systemctl enable "agent@${USERNAME}.service" 2>/dev/null || true

    echo "  Starting agent@${USERNAME}.service..."
    if timeout --kill-after=5 10 systemctl start --no-block "agent@${USERNAME}.service" 2>/dev/null; then
        echo "  [OK]   $USERNAME — agent starting"
        ((STARTED++))
    else
        echo "  [FAIL] $USERNAME — agent failed to queue start"
        ((FAILED++))
    fi

    # Start mail watcher for event-driven mail processing
    echo "  Enabling mail-watcher@${USERNAME}.service..."
    timeout --kill-after=5 10 systemctl enable "mail-watcher@${USERNAME}.service" 2>/dev/null || true
    timeout --kill-after=5 10 systemctl start --no-block "mail-watcher@${USERNAME}.service" 2>/dev/null || true
done

# Regenerate mail aliases to ensure they match current agent membership
/usr/local/bin/sync-aliases.sh

echo "agent-manager: Done. Started=$STARTED Failed=$FAILED"
echo "agent-manager: Finished at $(date -Iseconds)"
