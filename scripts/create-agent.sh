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
#   5. Configures git identity (user.name, user.email)
#   6. Sets up SSH known_hosts for common git forges (github.com, gitlab.com)
#   7. Configures per-agent API keys if provided
#   8. Enables and starts the agent@<username> systemd service
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

# Create Maildir structure for local mail delivery (OpenSMTPD delivers to ~/Maildir/new/)
MAILDIR="/home/$USERNAME/Maildir"
mkdir -p "$MAILDIR/new" "$MAILDIR/cur" "$MAILDIR/tmp"
chown -R "$USERNAME:$USERNAME" "$MAILDIR"
chmod 700 "$MAILDIR"
echo "  -> Maildir created at $MAILDIR"

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

# 4. Configure git identity
# Set user.name from username (+ persona) and user.email from username@agent-host.
# Use git config directly on the file to avoid shell injection from persona names.
GIT_NAME="$USERNAME"
if [[ -n "$PERSONA" ]]; then
    GIT_NAME="$USERNAME (${PERSONA%.md})"
fi
GIT_EMAIL="${USERNAME}@agent-host"
git config --file "/home/$USERNAME/.gitconfig" user.name "$GIT_NAME"
git config --file "/home/$USERNAME/.gitconfig" user.email "$GIT_EMAIL"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.gitconfig"
echo "  -> Git identity: $GIT_NAME <$GIT_EMAIL>"

# 5. Set up SSH known_hosts for common forges (non-interactive git clone/push)
# This is best-effort — agent creation must not fail in air-gapped environments.
SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
ssh-keyscan -t ed25519,rsa github.com gitlab.com 2>/dev/null > "$SSH_DIR/known_hosts" || true
if [[ -s "$SSH_DIR/known_hosts" ]]; then
    echo "  -> SSH known_hosts populated (github.com, gitlab.com)"
else
    echo "  Warning: ssh-keyscan returned no keys (network unavailable?); SSH may prompt for host verification." >&2
fi
chmod 644 "$SSH_DIR/known_hosts"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"

# 6. Configure per-agent API keys if provided
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

# 7. Enable and start the agent service via systemd
# Wait for systemd to finish booting if it hasn't yet (basic.target gates
# service start). This prevents races when create-agent.sh runs early in boot.
if ! timeout --kill-after=5 30 systemctl is-active basic.target &>/dev/null; then
    echo "  Waiting for systemd boot to complete..."
    timeout --kill-after=5 60 systemctl is-system-running --wait 2>/dev/null || true
fi

# Start the mail watcher (event-driven mail processing)
WATCHER_LOG="/var/log/mail-watcher-${USERNAME}.log"
WATCHER_PID="/run/mail-watcher-${USERNAME}.pid"

echo "  Starting mail watcher..."
nohup su - "$USERNAME" -c "MAIL=/home/$USERNAME/Maildir /usr/local/bin/mail-watcher.sh" \
    > "$WATCHER_LOG" 2>&1 &
WATCHER_PID_VAL=$!
echo "$WATCHER_PID_VAL" > "$WATCHER_PID"
echo "  -> Mail watcher started (PID $WATCHER_PID_VAL, log: $WATCHER_LOG)"

# Reload systemd to pick up the new service instance
systemctl daemon-reload

echo "  Enabling agent@${USERNAME}.service..."
timeout --kill-after=5 10 systemctl enable "agent@${USERNAME}.service"

echo "  Starting agent@${USERNAME}.service..."
if timeout --kill-after=5 15 systemctl start "agent@${USERNAME}.service"; then
    echo "  -> agent@${USERNAME}.service is active"
else
    echo "  Error: agent@${USERNAME}.service failed to start." >&2
    echo "  Recent journal entries:" >&2
    journalctl -u "agent@${USERNAME}.service" --no-pager -n 20 2>/dev/null \
        | sed 's/^/    /' >&2
    echo "  Service status:" >&2
    systemctl status "agent@${USERNAME}.service" --no-pager 2>/dev/null \
        | sed 's/^/    /' >&2
    exit 1
fi

echo "Agent '$USERNAME' is ready."
