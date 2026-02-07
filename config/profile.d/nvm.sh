#!/bin/bash
# nvm.sh — Load nvm (Node Version Manager) for all users
# nvm is installed system-wide at /usr/local/share/nvm
# Agents can use `nvm install <version>` to manage their own Node versions

export NVM_DIR="/usr/local/share/nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
fi
if [ -s "$NVM_DIR/bash_completion" ]; then
    . "$NVM_DIR/bash_completion"
fi
