#!/bin/bash
# create-agent.sh — Create a new agent user
#
# Usage: create-agent.sh <username>
#
# This script:
#   1. Creates a Linux user (home dir populated from /etc/skel)
#   2. Adds the user to the 'agents' group
#   3. Creates a root-owned .claude/ directory in the user's home
#      (readable by the user, writable only by root)
#   4. Enables and starts the agent@<username> systemd service

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: create-agent.sh <username>" >&2
    exit 1
fi

USERNAME="$1"

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

echo "Creating agent user: $USERNAME"

# 1. Create user with home directory (populated from /etc/skel)
useradd -m -s /bin/bash -G agents "$USERNAME"

# Lock down home directory so other agents cannot read it
chmod 700 "/home/$USERNAME"
echo "  -> User created with home at /home/$USERNAME (mode 700)"

# 2. Create .claude/ directory owned by root, readable by the user
CLAUDE_DIR="/home/$USERNAME/.claude"
mkdir -p "$CLAUDE_DIR"
chown root:root "$CLAUDE_DIR"
chmod 755 "$CLAUDE_DIR"

# Seed with an empty config placeholder
cat > "$CLAUDE_DIR/config.json" <<'CONF'
{
  "agent": {
    "enabled": true
  }
}
CONF
chown root:root "$CLAUDE_DIR/config.json"
chmod 644 "$CLAUDE_DIR/config.json"
echo "  -> .claude/ directory created (root-owned, user-readable)"

# 3. Enable and start the agent service for this user
systemctl enable "agent@${USERNAME}.service"
systemctl start "agent@${USERNAME}.service"
echo "  -> agent@${USERNAME}.service enabled and started"

echo "Agent '$USERNAME' is ready."
