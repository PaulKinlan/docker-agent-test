#!/bin/bash
# update-agent.sh — Update an existing agent's persona
#
# Usage: update-agent.sh <username> --persona <name>
#
# This script:
#   1. Validates the agent user exists
#   2. Validates the requested persona exists
#   3. Rebuilds agents.md from base persona + new specialist persona
#   4. Updates .claude/config.json with the new persona
#   5. Restarts the agent@<username> systemd service
#
# Persona resolution:
#   - The base persona (/etc/agent-personas/base.md) is always applied
#   - The --persona <name> flag selects the specialist persona to append
#   - Use --persona base to reset to only the base persona (no specialist)

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --persona)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --persona requires a value." >&2
                echo "Usage: update-agent.sh <username> --persona <name>" >&2
                exit 1
            fi
            PERSONA="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option '$1'." >&2
            echo "Usage: update-agent.sh <username> --persona <name>" >&2
            exit 1
            ;;
        *)
            if [[ -z "$USERNAME" ]]; then
                USERNAME="$1"
            else
                echo "Error: Unexpected argument '$1'." >&2
                echo "Usage: update-agent.sh <username> --persona <name>" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    echo "Usage: update-agent.sh <username> --persona <name>" >&2
    exit 1
fi

if [[ -z "$PERSONA" ]]; then
    echo "Error: --persona is required." >&2
    echo "Usage: update-agent.sh <username> --persona <name>" >&2
    exit 1
fi

# Check if user exists
if ! id "$USERNAME" &>/dev/null; then
    echo "Error: User '$USERNAME' does not exist." >&2
    exit 1
fi

# Check the user is in the agents group
if ! id -nG "$USERNAME" | grep -qw agents; then
    echo "Error: User '$USERNAME' is not an agent (not in 'agents' group)." >&2
    exit 1
fi

# Validate persona (unless resetting to base-only)
if [[ "$PERSONA" != "base" ]]; then
    PERSONA_FILE="${PERSONAS_DIR}/${PERSONA%.md}.md"
    if [[ ! -f "$PERSONA_FILE" ]]; then
        echo "Error: Persona '${PERSONA}' not found at ${PERSONA_FILE}" >&2
        echo "Available personas:" >&2
        for f in "${PERSONAS_DIR}"/*.md; do
            name="$(basename "$f" .md)"
            [[ "$name" == "base" ]] && continue
            echo "  - $name" >&2
        done
        echo "  - base (reset to base persona only)" >&2
        exit 1
    fi
fi

echo "Updating agent persona: $USERNAME"

# 1. Rebuild agents.md from base persona + optional specialist persona
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

    # Append specialist persona if not resetting to base-only
    if [[ "$PERSONA" != "base" ]]; then
        PERSONA_FILE="${PERSONAS_DIR}/${PERSONA%.md}.md"
        echo ""
        echo "---"
        echo ""
        cat "$PERSONA_FILE"
    fi
} > "$AGENTS_MD"

chown "$USERNAME:$USERNAME" "$AGENTS_MD"
chmod 644 "$AGENTS_MD"

if [[ "$PERSONA" != "base" ]]; then
    echo "  -> Persona: base + ${PERSONA%.md}"
else
    echo "  -> Persona: base (default)"
fi

# 2. Update .claude/config.json with new persona
CLAUDE_DIR="/home/$USERNAME/.claude"
mkdir -p "$CLAUDE_DIR"
cat > "$CLAUDE_DIR/config.json" <<CONF
{
  "agent": {
    "enabled": true,
    "persona": "${PERSONA}"
  }
}
CONF
chown root:root "$CLAUDE_DIR/config.json"
chmod 644 "$CLAUDE_DIR/config.json"
echo "  -> config.json updated"

# 3. Restart the agent service to pick up the new persona
if systemctl is-enabled "agent@${USERNAME}.service" &>/dev/null; then
    systemctl restart --no-block "agent@${USERNAME}.service"
    echo "  -> agent@${USERNAME}.service restarting"
else
    echo "  -> Warning: agent@${USERNAME}.service is not enabled (skipped restart)"
fi

echo "Agent '$USERNAME' persona updated to '${PERSONA}'."
