#!/bin/bash
# create-agent.sh — Create a new agent user with optional persona and API keys
#
# Usage: create-agent.sh <username> [--persona <name>] [--api-key <PROVIDER>=<key>]...
#
# This script:
#   1. Creates a Linux user (home dir populated from /etc/skel)
#   2. Adds the user to the 'agents' group
#   3. Builds the agent's agents.md from base persona + optional specialist persona
#   4. Creates a root-owned .claude/ directory in the user's home
#      (readable by the user, writable only by root)
#   5. Configures per-agent API keys if provided
#   6. Enables and starts the agent@<username> systemd service
#
# Options:
#   --persona <name>        Apply a specialist persona (e.g., coder, researcher)
#   --api-key <PROVIDER>=<key>  Set an API key for this agent (can be repeated)
#
# Persona resolution:
#   - The base persona (/etc/agent-personas/base.md) is always applied
#   - If --persona <name> is given, the matching file from /etc/agent-personas/<name>.md
#     is appended after the base persona
#   - Without --persona, the agent gets only the base persona
#
# API key examples:
#   create-agent.sh alice --api-key ANTHROPIC_API_KEY=sk-ant-xxx
#   create-agent.sh bob --persona coder --api-key OPENAI_API_KEY=sk-xxx

set -euo pipefail

# --- Host/container detection ---
# If not running inside the container, proxy the command through docker exec.
# Override the container name with AGENT_HOST_CONTAINER if needed.
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

PERSONAS_DIR="/etc/agent-personas"

# --- Parse arguments ---
USERNAME=""
PERSONA=""
API_KEYS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --persona)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --persona requires a value." >&2
                echo "Usage: create-agent.sh <username> [--persona <name>] [--api-key <PROVIDER>=<key>]..." >&2
                exit 1
            fi
            PERSONA="$2"
            shift 2
            ;;
        --api-key)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --api-key requires a value in PROVIDER=key format." >&2
                echo "Usage: create-agent.sh <username> [--persona <name>] [--api-key <PROVIDER>=<key>]..." >&2
                exit 1
            fi
            if [[ ! "$2" =~ ^[A-Z_][A-Z0-9_]*=.+$ ]]; then
                echo "Error: Invalid API key format '$2'. Use PROVIDER=key format (e.g., ANTHROPIC_API_KEY=sk-xxx)." >&2
                exit 1
            fi
            API_KEYS+=("$2")
            shift 2
            ;;
        -*)
            echo "Error: Unknown option '$1'." >&2
            echo "Usage: create-agent.sh <username> [--persona <name>] [--api-key <PROVIDER>=<key>]..." >&2
            exit 1
            ;;
        *)
            if [[ -z "$USERNAME" ]]; then
                USERNAME="$1"
            else
                echo "Error: Unexpected argument '$1'." >&2
                echo "Usage: create-agent.sh <username> [--persona <name>] [--api-key <PROVIDER>=<key>]..." >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    echo "Usage: create-agent.sh <username> [--persona <name>] [--api-key <PROVIDER>=<key>]..." >&2
    exit 1
fi

# Validate username (alphanumeric + hyphens/underscores, 1-32 chars)
if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "Error: Invalid username '$USERNAME'." >&2
    echo "Must start with a lowercase letter or underscore, contain only [a-z0-9_-], max 32 chars." >&2
    exit 1
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    echo "Error: User '$USERNAME' already exists." >&2
    exit 1
fi

# Validate persona if specified
if [[ -n "$PERSONA" ]]; then
    # Allow .md extension to be omitted
    PERSONA_FILE="${PERSONAS_DIR}/${PERSONA%.md}.md"
    if [[ ! -f "$PERSONA_FILE" ]]; then
        echo "Error: Persona '${PERSONA}' not found at ${PERSONA_FILE}" >&2
        echo "Available personas:" >&2
        for f in "${PERSONAS_DIR}"/*.md; do
            name="$(basename "$f" .md)"
            [[ "$name" == "base" ]] && continue
            echo "  - $name" >&2
        done
        exit 1
    fi
fi

echo "Creating agent user: $USERNAME"

# 1. Create user with home directory (populated from /etc/skel)
useradd -m -s /bin/bash -G agents "$USERNAME"

# Lock down home directory so other agents cannot read it
chmod 700 "/home/$USERNAME"
echo "  -> User created with home at /home/$USERNAME (mode 700)"

# 2. Build agents.md from base persona + optional specialist persona
AGENTS_MD="/home/$USERNAME/agents.md"
{
    # Always include the base persona
    if [[ -f "${PERSONAS_DIR}/base.md" ]]; then
        cat "${PERSONAS_DIR}/base.md"
    else
        echo "# Agent Configuration"
        echo ""
        echo "No base persona found. Configure this agent by editing this file."
    fi

    # Append specialist persona if specified
    if [[ -n "$PERSONA" ]]; then
        PERSONA_FILE="${PERSONAS_DIR}/${PERSONA%.md}.md"
        echo ""
        echo "---"
        echo ""
        cat "$PERSONA_FILE"
    fi
} > "$AGENTS_MD"

chown "$USERNAME:$USERNAME" "$AGENTS_MD"
chmod 644 "$AGENTS_MD"

if [[ -n "$PERSONA" ]]; then
    echo "  -> Persona: base + ${PERSONA%.md}"
else
    echo "  -> Persona: base (default)"
fi

# 3. Create .claude/ directory owned by the agent user
# The SDK needs to create subdirectories at runtime (sessions, projects, todos, etc.)
# so the directory must be agent-writable. The config.json is root-owned read-only.
CLAUDE_DIR="/home/$USERNAME/.claude"
mkdir -p "$CLAUDE_DIR"
chown "$USERNAME:$USERNAME" "$CLAUDE_DIR"
chmod 755 "$CLAUDE_DIR"

# Seed config with agent metadata including persona info (root-owned, read-only to agent)
cat > "$CLAUDE_DIR/config.json" <<CONF
{
  "agent": {
    "enabled": true,
    "persona": "${PERSONA:-base}"
  }
}
CONF
chown root:root "$CLAUDE_DIR/config.json"
chmod 644 "$CLAUDE_DIR/config.json"
echo "  -> .claude/ directory created (agent-writable, config.json root-owned)"

# 4. Configure per-agent API keys if provided
if [[ ${#API_KEYS[@]} -gt 0 ]]; then
    API_KEYS_FILE="$CLAUDE_DIR/api-keys.env"
    {
        echo "# API keys for agent: $USERNAME"
        echo "# Managed by create-agent.sh - use manage-api-keys.sh to modify"
        echo "# Generated: $(date -Iseconds)"
        echo ""
        for key_pair in "${API_KEYS[@]}"; do
            echo "$key_pair"
        done
    } > "$API_KEYS_FILE"
    chown root:root "$API_KEYS_FILE"
    chmod 640 "$API_KEYS_FILE"
    # Allow the agent user to read the file via group
    chgrp "$(id -gn "$USERNAME")" "$API_KEYS_FILE"
    echo "  -> API keys configured (${#API_KEYS[@]} key(s))"
fi

# 5. Enable and start the agent service for this user
# All systemctl calls use timeout with --kill-after to prevent indefinite
# hangs caused by D-Bus communication failures in Docker containers.
echo "  Enabling agent@${USERNAME}.service..."
if ! timeout --kill-after=5 10 systemctl enable "agent@${USERNAME}.service" 2>&1; then
    echo "  Warning: systemctl enable timed out or failed (continuing anyway)" >&2
fi

# Ensure systemd has picked up the new instance before starting
echo "  Reloading systemd daemon..."
if ! timeout --kill-after=5 10 systemctl daemon-reload 2>&1; then
    echo "  Warning: systemctl daemon-reload timed out or failed (continuing anyway)" >&2
fi

# Wait for basic.target (the After= dependency in agent@.service).
# In Docker, systemctl is-system-running may never report "running", so
# poll the specific target we need instead.
echo "  Waiting for basic.target..."
BOOT_WAIT=0
BOOT_TIMEOUT=60
while ! systemctl is-active --quiet basic.target 2>/dev/null; do
    if (( BOOT_WAIT >= BOOT_TIMEOUT )); then
        echo "  Warning: basic.target not reached after ${BOOT_TIMEOUT}s (continuing anyway)." >&2
        break
    fi
    sleep 1
    ((BOOT_WAIT++))
done
if (( BOOT_WAIT > 0 && BOOT_WAIT < BOOT_TIMEOUT )); then
    echo "  basic.target reached after ${BOOT_WAIT}s."
fi

# Start the service (timeout prevents Docker/D-Bus hangs)
echo "  Starting agent@${USERNAME}.service..."
START_OUTPUT=$(timeout --kill-after=5 30 systemctl start "agent@${USERNAME}.service" 2>&1) || {
    echo "  Warning: systemctl start returned an error." >&2
    if [[ -n "$START_OUTPUT" ]]; then
        echo "$START_OUTPUT" >&2
    fi
}

# Verify the service is actually running (handles slow start and queued jobs)
echo "  Verifying service status..."
SERVICE_OK=false
for i in $(seq 1 10); do
    if systemctl is-active --quiet "agent@${USERNAME}.service" 2>/dev/null; then
        SERVICE_OK=true
        break
    fi
    sleep 1
done

if [[ "$SERVICE_OK" != "true" ]]; then
    echo "" >&2
    echo "  Error: agent@${USERNAME}.service is not running." >&2
    echo "" >&2
    echo "  Service status:" >&2
    timeout --kill-after=5 10 systemctl status "agent@${USERNAME}.service" --no-pager 2>&1 | sed 's/^/    /' >&2 || true
    echo "" >&2
    # Show journal output if any
    JOURNAL_OUTPUT=$(timeout --kill-after=5 10 journalctl -u "agent@${USERNAME}.service" --no-pager -n 20 2>&1) || true
    if [[ -n "$JOURNAL_OUTPUT" ]] && ! echo "$JOURNAL_OUTPUT" | grep -q "No entries"; then
        echo "  Journal logs:" >&2
        echo "$JOURNAL_OUTPUT" | sed 's/^/    /' >&2
    else
        echo "  No journal entries found for this service." >&2
        echo "  This usually means the process never started." >&2
        echo "  Check if basic.target is active: systemctl is-active basic.target" >&2
    fi
    echo "" >&2
    echo "  Diagnostics:" >&2
    echo "    basic.target: $(systemctl is-active basic.target 2>/dev/null || echo 'not active')" >&2
    echo "    system state: $(systemctl is-system-running 2>/dev/null || echo 'unknown')" >&2
    echo "" >&2
    echo "  Check logs with: journalctl -u agent@${USERNAME}.service" >&2
    exit 1
fi

echo "  -> agent@${USERNAME}.service enabled and active"

echo "Agent '$USERNAME' is ready."
