#!/bin/bash
# snapshot-agents.sh — Snapshot agent state (home directories, logs) using a separate git repo
#
# This script runs on the HOST only. It uses a dedicated GIT_DIR (.agent-snapshots)
# that is separate from the main source repository, so snapshots don't conflict
# with the project's own git history. The .agent-snapshots directory is not mounted
# into the container, so agents never see it.
#
# Usage: snapshot-agents.sh <command> [args]
#
# Commands:
#   init              Initialize the snapshot repository
#   create [message]  Take a snapshot (default message: timestamp)
#   log [git-args]    Show snapshot history
#   diff [git-args]   Show changes since last snapshot
#   show [git-args]   Show a specific snapshot
#   status            Show what changed since last snapshot
#   help              Show usage information

set -euo pipefail

# --- Refuse to run inside the container ---
if [[ -f /.dockerenv ]]; then
    echo "Error: snapshot-agents.sh must be run on the host, not inside the container." >&2
    exit 1
fi

# --- Resolve project root ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Handle both ./scripts/snapshot-agents.sh and direct invocation
if [[ "$(basename "$SCRIPT_DIR")" == "scripts" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    PROJECT_ROOT="$SCRIPT_DIR"
fi

readonly SNAPSHOT_DIR="$PROJECT_ROOT/.agent-snapshots"
readonly WORK_TREE="$PROJECT_ROOT"

# --- Helper: run git against the snapshot repo ---
snapshot_git() {
    git --git-dir="$SNAPSHOT_DIR" --work-tree="$WORK_TREE" "$@"
}

# --- Helper: check snapshot repo is initialized ---
require_init() {
    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        echo "Error: Snapshot repository not initialized." >&2
        echo "Run '$0 init' or 'make snapshot-init' first." >&2
        exit 1
    fi
}

# --- Commands ---

cmd_init() {
    if [[ -d "$SNAPSHOT_DIR" ]]; then
        echo "Snapshot repository already initialized at $SNAPSHOT_DIR"
        return 0
    fi

    git init --bare "$SNAPSHOT_DIR"

    # Configure the snapshot repo to only track the container mount-point directories.
    # Everything else (source code, Dockerfile, etc.) belongs to the main repo.
    cat > "$SNAPSHOT_DIR/info/exclude" <<'EOF'
# Snapshot repo: only track agent runtime directories (home/, log/).
# Everything else is managed by the main source repo.
# Note: mail is stored in ~/Maildir/ (inside home/) since the switch to Maildir format.

# Ignore everything by default
/*

# Track the container mount points
!/home
!/log

# Skip .gitkeep files (those belong to the main repo)
.gitkeep

# Skip binary journal files (large, not useful in git)
log/journal/
EOF

    echo "Snapshot repository initialized at $SNAPSHOT_DIR"
    echo "Run 'make snapshot' or '$0 create' to take a snapshot."
}

cmd_create() {
    require_init

    local message="${1:-snapshot $(date -Is)}"

    snapshot_git add -A

    # Check if there are staged changes
    if snapshot_git diff --cached --quiet 2>/dev/null; then
        # Also check for untracked files on first commit
        if snapshot_git rev-parse HEAD &>/dev/null; then
            echo "No changes to snapshot."
            return 0
        fi
        # First commit — check if there's anything staged at all
        if [[ -z "$(snapshot_git diff --cached --name-only 2>/dev/null)" ]]; then
            echo "No files to snapshot. Are the mount directories (home/, log/) empty?"
            return 0
        fi
    fi

    snapshot_git commit -m "$message"
    echo "Snapshot created."
}

cmd_log() {
    require_init
    snapshot_git log --oneline --decorate "$@"
}

cmd_diff() {
    require_init
    snapshot_git diff "$@"
}

cmd_show() {
    require_init
    snapshot_git show "$@"
}

cmd_status() {
    require_init

    # Stage everything so status reflects the full picture
    snapshot_git add -A

    echo "Changes since last snapshot:"
    echo ""
    if snapshot_git diff --cached --quiet 2>/dev/null && snapshot_git rev-parse HEAD &>/dev/null; then
        echo "  (no changes)"
    else
        snapshot_git diff --cached --stat 2>/dev/null || echo "  (first snapshot pending — run 'create' to commit)"
    fi
}

cmd_help() {
    cat <<'EOF'
Usage: snapshot-agents.sh <command> [args]

Snapshot agent runtime state (home directories including Maildir, logs)
using a separate git repository that doesn't interfere with the main source repo.

Commands:
  init              Initialize the snapshot repository
  create [message]  Take a snapshot (default message: current timestamp)
  log [git-args]    Show snapshot history (pass extra args to git log)
  diff [git-args]   Show changes since last snapshot
  show [git-args]   Show a specific snapshot
  status            Summarize what changed since last snapshot
  help              Show this help

Examples:
  snapshot-agents.sh init
  snapshot-agents.sh create "after alice finished task 3"
  snapshot-agents.sh log -5
  snapshot-agents.sh diff HEAD~1
  snapshot-agents.sh status

Makefile targets:
  make snapshot-init             Initialize the snapshot repo
  make snapshot                  Take a snapshot
  make snapshot MSG="my note"    Take a snapshot with a custom message
  make snapshot-log              Show snapshot history
  make snapshot-diff             Show changes since last snapshot
  make snapshot-status           Summarize changes since last snapshot
EOF
}

# --- Main dispatch ---
case "${1:-help}" in
    init)
        cmd_init
        ;;
    create)
        shift
        cmd_create "${1:-}"
        ;;
    log)
        shift
        cmd_log "$@"
        ;;
    diff)
        shift
        cmd_diff "$@"
        ;;
    show)
        shift
        cmd_show "$@"
        ;;
    status)
        cmd_status
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        echo "Error: Unknown command '$1'" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
