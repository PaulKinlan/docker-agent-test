#!/bin/bash
# create-agent.sh — Create a new agent user with optional persona and API keys
#
# Usage: create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER>=<key>]...
#
# This script:
#   1. Creates a Linux user (home dir populated from /etc/skel)
#   2. Adds the user to the 'agents' group
#   3. Builds the agent's agents.md from base persona + optional specialist persona + custom instructions
#   4. Creates an agent-writable .claude/ directory (with skills/ subdirectory)
#      and a root-owned read-only config.json inside it
#   5. Configures per-agent API keys if provided
#   6. Enables and starts the agent@<username> systemd service
#
# Options:
#   --persona <name>            Apply a specialist persona (e.g., coder, researcher)
#   --instructions <text>       Custom instructions appended to the agent's agents.md
#   --api-key <PROVIDER>=<key>  Set an API key for this agent (can be repeated)
#
# Persona resolution:
#   - The base persona (/etc/agent-personas/base.md) is always applied
#   - If --persona <name> is given, the matching file from /etc/agent-personas/<name>.md
#     is appended after the base persona
#   - Without --persona, the agent gets only the base persona
#
# Examples:
#   create-agent.sh alice --api-key ANTHROPIC_API_KEY=sk-ant-xxx
#   create-agent.sh bob --persona coder --api-key OPENAI_API_KEY=sk-xxx
#   create-agent.sh carol --persona coder --instructions "Focus on Python backend code"

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
INSTRUCTIONS=""
API_KEYS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --persona)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --persona requires a value." >&2
                echo "Usage: create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER>=<key>]..." >&2
                exit 1
            fi
            PERSONA="$2"
            shift 2
            ;;
        --instructions)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --instructions requires a value." >&2
                echo "Usage: create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER>=<key>]..." >&2
                exit 1
            fi
            INSTRUCTIONS="$2"
            shift 2
            ;;
        --api-key)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --api-key requires a value in PROVIDER=key format." >&2
                echo "Usage: create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER>=<key>]..." >&2
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
            echo "Usage: create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER>=<key>]..." >&2
            exit 1
            ;;
        *)
            if [[ -z "$USERNAME" ]]; then
                USERNAME="$1"
            else
                echo "Error: Unexpected argument '$1'." >&2
                echo "Usage: create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER>=<key>]..." >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    echo "Usage: create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER>=<key>]..." >&2
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
# Extract the role description from the persona file for the GECOS field,
# so other agents can discover this user's role via getent passwd.
GECOS="Agent"
if [[ -n "$PERSONA" ]]; then
    PERSONA_FILE="${PERSONAS_DIR}/${PERSONA%.md}.md"
    ROLE_LINE=$(grep -m1 '^\- \*\*Role\*\*:' "$PERSONA_FILE" 2>/dev/null || true)
    if [[ -n "$ROLE_LINE" ]]; then
        # Strip markdown: "- **Role**: Software Development Agent" -> "Software Development Agent"
        GECOS=$(echo "$ROLE_LINE" | sed 's/^- \*\*Role\*\*: *//')
    fi
    PURPOSE_LINE=$(grep -m1 '^\- \*\*Purpose\*\*:' "$PERSONA_FILE" 2>/dev/null || true)
    if [[ -n "$PURPOSE_LINE" ]]; then
        PURPOSE=$(echo "$PURPOSE_LINE" | sed 's/^- \*\*Purpose\*\*: *//')
        GECOS="$GECOS (${PERSONA%.md}) - $PURPOSE"
    else
        GECOS="$GECOS (${PERSONA%.md})"
    fi
fi
# Create persona group if it doesn't exist, so users with the same persona
# can be addressed collectively (e.g., mail to coder-all).
GROUPS="agents"
if [[ -n "$PERSONA" ]]; then
    PERSONA_GROUP="${PERSONA%.md}"
    if ! getent group "$PERSONA_GROUP" &>/dev/null; then
        groupadd "$PERSONA_GROUP"
        echo "  -> Created persona group: $PERSONA_GROUP"
    fi
    GROUPS="agents,$PERSONA_GROUP"
fi
# Create user without -m (useradd -m fails on Docker bind mounts from macOS
# due to VirtioFS permission mapping issues). We create the home dir manually.
useradd -M -s /bin/bash -G "$GROUPS" -c "$GECOS" -d "/home/$USERNAME" "$USERNAME"

# Manually create home directory and populate from /etc/skel
mkdir -p "/home/$USERNAME"
cp -a /etc/skel/. "/home/$USERNAME/"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
chmod 700 "/home/$USERNAME"
echo "  -> User created with home at /home/$USERNAME (mode 700)"

# Regenerate mail aliases (adds new agent to the 'all' group alias)
/usr/local/bin/sync-aliases.sh

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

    # Append custom instructions if provided
    if [[ -n "$INSTRUCTIONS" ]]; then
        echo ""
        echo "---"
        echo ""
        echo "## Custom Instructions"
        echo ""
        echo "$INSTRUCTIONS"
    fi
} > "$AGENTS_MD"

chown "$USERNAME:$USERNAME" "$AGENTS_MD"
chmod 644 "$AGENTS_MD"

if [[ -n "$PERSONA" ]]; then
    echo "  -> Persona: base + ${PERSONA%.md}"
else
    echo "  -> Persona: base (default)"
fi

if [[ -n "$INSTRUCTIONS" ]]; then
    echo "  -> Custom instructions appended to agents.md"
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
# Create skills directory for Claude Code skills
mkdir -p "$CLAUDE_DIR/skills"
chown "$USERNAME:$USERNAME" "$CLAUDE_DIR/skills"

# Install skill packs from /etc/agent-skills/
SKILLS_SRC="/etc/agent-skills"
AGENT_SKILLS="$CLAUDE_DIR/skills"

install_skills_from() {
    local src_dir="$1"
    [[ -d "$src_dir" ]] || return 0
    for skill_dir in "$src_dir"/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        # Never overwrite existing skills (preserves agent customizations)
        if [[ ! -d "$AGENT_SKILLS/$skill_name" ]]; then
            cp -r "$skill_dir" "$AGENT_SKILLS/$skill_name"
            chown -R "$USERNAME:$USERNAME" "$AGENT_SKILLS/$skill_name"
        fi
    done
}

# Universal skills (for all agents)
install_skills_from "$SKILLS_SRC/_universal"

# Persona-specific skills
if [[ -n "$PERSONA" ]]; then
    install_skills_from "$SKILLS_SRC/${PERSONA%.md}"
fi

SKILL_COUNT=$(find "$AGENT_SKILLS" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
echo "  -> Skills installed: $SKILL_COUNT"

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

# 5. Start the agent process
# We use direct process launch instead of systemd services because systemd's
# cgroup-based process spawning is broken in Docker Desktop (macOS) with
# cgroup v2 and systemd v256+. The container's systemd boots targets fine
# but ExecStart processes get exit=255 with 0B memory (never actually exec'd).
#
# Direct launch via nohup+su gives us:
#   - Process runs as the agent user (same as systemd User= would)
#   - Logs go to a file (since journald is also broken)
#   - PID tracked via a pidfile for stop/health-check scripts
AGENT_LOG="/var/log/agent-${USERNAME}.log"
AGENT_PID="/run/agent-${USERNAME}.pid"

echo "  Starting agent process..."
nohup su - "$USERNAME" -c "/usr/local/bin/run-agent.sh" \
    > "$AGENT_LOG" 2>&1 &
AGENT_PID_VAL=$!
echo "$AGENT_PID_VAL" > "$AGENT_PID"

# Verify the process is running
sleep 3
if kill -0 "$AGENT_PID_VAL" 2>/dev/null; then
    echo "  -> Agent process started (PID $AGENT_PID_VAL, log: $AGENT_LOG)"
else
    echo "  Error: Agent process died immediately." >&2
    echo "  Log output:" >&2
    tail -20 "$AGENT_LOG" 2>/dev/null | sed 's/^/    /' >&2
    exit 1
fi

echo "Agent '$USERNAME' is ready."
