#!/bin/bash
# mail-watcher.sh — inotify-based Maildir watcher for event-driven mail processing
#
# Usage: mail-watcher.sh (run by mail-watcher@<user>.service)
#
# Watches ~/Maildir/new/ for incoming mail using inotifywait. When OpenSMTPD
# delivers a message, this script:
#   1. Logs the delivery
#   2. Moves the message from new/ to cur/ (standard Maildir "seen" transition)
#
# This prevents file buildup in new/ and provides the foundation for
# Phase 2 work-queue integration. The agent loop (run-agent.sh) separately
# watches ~/Maildir/new/ with inotifywait to wake up immediately on new mail.
#
# The Delivered-To header (first line of each message, injected by OpenSMTPD)
# contains the envelope recipient address.

set -euo pipefail

readonly AGENT_USER="$(whoami)"
readonly MAILDIR="$HOME/Maildir"
readonly MAILDIR_NEW="$MAILDIR/new"
readonly MAILDIR_CUR="$MAILDIR/cur"

log() {
    echo "[$(date -Iseconds)] mail-watcher(${AGENT_USER}): $*"
}

# Ensure Maildir structure exists
for dir in "$MAILDIR" "$MAILDIR_NEW" "$MAILDIR_CUR" "$MAILDIR/tmp"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log "Created $dir"
    fi
done

log "Watching $MAILDIR_NEW for incoming mail"

# Process any messages already sitting in new/ (e.g., from before watcher started)
for existing in "$MAILDIR_NEW"/*; do
    [[ -f "$existing" ]] || continue
    filename="$(basename "$existing")"
    mv "$existing" "$MAILDIR_CUR/${filename}:2,"
    log "Processed pre-existing: $filename"
done

# Watch for new messages using inotifywait
# CREATE: OpenSMTPD writes directly to new/
# MOVED_TO: OpenSMTPD writes to tmp/ first then renames to new/ (standard Maildir delivery)
inotifywait -m -e create -e moved_to --format '%f' "$MAILDIR_NEW" 2>/dev/null |
while IFS= read -r filename; do
    filepath="$MAILDIR_NEW/$filename"

    # Small delay to ensure the file is fully written
    sleep 0.1

    # Skip if file was already moved (race with another process)
    if [[ ! -f "$filepath" ]]; then
        continue
    fi

    # Move from new/ to cur/ with standard Maildir info suffix
    # :2, means "no flags set" — s-nail will see it as unread in cur/
    mv "$filepath" "$MAILDIR_CUR/${filename}:2,"
    log "New mail: $filename"
done
