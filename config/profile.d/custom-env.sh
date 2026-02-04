#!/bin/bash
# custom-env.sh - Global environment settings for all users
# This file is sourced by all interactive shells

# Custom global environment variables
export CUSTOM_VAR="This is a custom global variable"

# Add custom bin directories to PATH if they exist
if [ -d "/usr/local/custom/bin" ]; then
    export PATH="/usr/local/custom/bin:$PATH"
fi

# Custom greeting message
echo "Welcome to Arch Linux Docker Container!"
