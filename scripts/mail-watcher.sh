#!/bin/bash
# mail-watcher.sh — inotify-based Maildir watcher for event-driven mail processing
#
# Usage: mail-watcher.sh (launched by create-agent.sh / agent-manager.sh)
#
# Watches ~/Maildir/new/ for incoming mail using inotifywait and logs each
# delivery. Messages are left in new/ for the MUA (s-nail) to handle —
# s-nail moves them to cur/ when the agent reads mail, preserving standard
# Maildir semantics (new/ = unseen, cur/ = seen).
#
# This script provides the foundation for Phase 2 work-queue integration,
# where it will parse incoming mail and create work items.
#
# The Delivered-To header (first line of each message, injected by OpenSMTPD)
# contains the envelope recipient address.

set -euo pipefail

readonly AGENT_USER="$(whoami)"
readonly MAILDIR="$HOME/Maildir"
readonly MAILDIR_NEW="$MAILDIR/new"
readonly PIDFILE="$HOME/.mail-watcher.pid"

# Write our actual PID so cleanup scripts can kill the right process
# (the launcher records the su wrapper PID which is a different process)
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

log() {
    echo "[$(date -Iseconds)] mail-watcher(${AGENT_USER}): $*"
}

# Ensure Maildir structure exists
for dir in "$MAILDIR" "$MAILDIR_NEW" "$MAILDIR/cur" "$MAILDIR/tmp"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log "Created $dir"
    fi
done

log "Watching $MAILDIR_NEW for incoming mail (PID $$)"

# Watch for new messages using inotifywait
# CREATE: OpenSMTPD writes directly to new/
# MOVED_TO: OpenSMTPD writes to tmp/ first then renames to new/ (standard Maildir delivery)
inotifywait -m -e create -e moved_to --format '%f' "$MAILDIR_NEW" 2>/dev/null |
while IFS= read -r filename; do
    log "New mail: $filename"
done
