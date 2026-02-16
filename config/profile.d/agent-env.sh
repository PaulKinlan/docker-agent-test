#!/bin/bash
# agent-env.sh — Global environment for all agent users
# Sourced on every interactive login shell

# Identify this as an agent host container
export AGENT_HOST=1
export AGENT_PLATFORM="docker"

# Restrictive umask for all agent users: files are private by default
umask 077

# Use Maildir format for local mail (delivered by OpenSMTPD to ~/Maildir/)
export MAIL="$HOME/Maildir"

# Add agent scripts to PATH if not already present
if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    export PATH="/usr/local/bin:$PATH"
fi
