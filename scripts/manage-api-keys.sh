#!/bin/bash
# manage-api-keys.sh — Manage API keys for agents
#
# Usage:
#   manage-api-keys.sh set <username> <PROVIDER>=<key> [<PROVIDER>=<key> ...]
#   manage-api-keys.sh get <username> [PROVIDER]
#   manage-api-keys.sh remove <username> <PROVIDER> [<PROVIDER> ...]
#   manage-api-keys.sh clear <username>
#   manage-api-keys.sh list-providers
#
# This script manages per-agent API keys stored in ~/.claude/api-keys.env
# Keys are root-owned but readable by the agent user.
#
# Examples:
#   manage-api-keys.sh set alice ANTHROPIC_API_KEY=sk-ant-xxx
#   manage-api-keys.sh set bob OPENAI_API_KEY=sk-xxx MISTRAL_API_KEY=xxx
#   manage-api-keys.sh get alice
#   manage-api-keys.sh get alice ANTHROPIC_API_KEY
#   manage-api-keys.sh remove alice OPENAI_API_KEY
#   manage-api-keys.sh clear alice
#   manage-api-keys.sh list-providers

set -euo pipefail

# --- Host/container detection ---
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

# Known API key providers (for validation and documentation)
readonly KNOWN_PROVIDERS=(
    "ANTHROPIC_API_KEY"
    "OPENAI_API_KEY"
    "GOOGLE_API_KEY"
    "GEMINI_API_KEY"
    "MISTRAL_API_KEY"
    "COHERE_API_KEY"
    "GROQ_API_KEY"
    "TOGETHER_API_KEY"
    "FIREWORKS_API_KEY"
    "PERPLEXITY_API_KEY"
    "REPLICATE_API_TOKEN"
    "HUGGINGFACE_API_KEY"
    "HF_TOKEN"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_DEFAULT_REGION"
    "AZURE_OPENAI_API_KEY"
    "AZURE_OPENAI_ENDPOINT"
    "GITHUB_TOKEN"
    "GH_TOKEN"
)

usage() {
    cat <<'EOF'
Usage:
  manage-api-keys.sh set <username> <PROVIDER>=<key> [<PROVIDER>=<key> ...]
  manage-api-keys.sh get <username> [PROVIDER]
  manage-api-keys.sh remove <username> <PROVIDER> [<PROVIDER> ...]
  manage-api-keys.sh clear <username>
  manage-api-keys.sh list-providers

Commands:
  set            Set one or more API keys for an agent
  get            Show API keys for an agent (values masked by default)
  remove         Remove specific API keys from an agent
  clear          Remove all API keys from an agent
  list-providers List known API key provider names

Examples:
  manage-api-keys.sh set alice ANTHROPIC_API_KEY=sk-ant-xxx
  manage-api-keys.sh set bob OPENAI_API_KEY=sk-xxx MISTRAL_API_KEY=xxx
  manage-api-keys.sh get alice
  manage-api-keys.sh remove alice OPENAI_API_KEY
  manage-api-keys.sh clear alice
EOF
    exit 1
}

validate_username() {
    local username="$1"
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "Error: Invalid username '$username'." >&2
        exit 1
    fi
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist." >&2
        exit 1
    fi
    if ! id -nG "$username" | grep -qw agents; then
        echo "Error: User '$username' is not in the 'agents' group." >&2
        exit 1
    fi
}

get_api_keys_file() {
    local username="$1"
    echo "/home/${username}/.claude/api-keys.env"
}

ensure_claude_dir() {
    local username="$1"
    local claude_dir="/home/${username}/.claude"
    if [[ ! -d "$claude_dir" ]]; then
        mkdir -p "$claude_dir"
        chown root:root "$claude_dir"
        chmod 755 "$claude_dir"
    fi
}

# Mask API key value for display (show first 4 and last 4 chars)
mask_key() {
    local key="$1"
    local len=${#key}
    if [[ $len -le 8 ]]; then
        echo "********"
    else
        echo "${key:0:4}...${key: -4}"
    fi
}

cmd_set() {
    if [[ $# -lt 2 ]]; then
        echo "Error: 'set' requires a username and at least one KEY=value pair." >&2
        usage
    fi

    local username="$1"
    shift
    validate_username "$username"
    ensure_claude_dir "$username"

    local api_keys_file
    api_keys_file="$(get_api_keys_file "$username")"

    # Parse and validate key=value pairs
    declare -A new_keys
    for arg in "$@"; do
        if [[ ! "$arg" =~ ^[A-Z_][A-Z0-9_]*=.+$ ]]; then
            echo "Error: Invalid format '$arg'. Use PROVIDER=key format." >&2
            exit 1
        fi
        local provider="${arg%%=*}"
        local value="${arg#*=}"
        new_keys["$provider"]="$value"
    done

    # Load existing keys if file exists
    declare -A existing_keys
    if [[ -f "$api_keys_file" ]]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            # Remove any surrounding whitespace
            key="$(echo "$key" | xargs)"
            existing_keys["$key"]="$value"
        done < "$api_keys_file"
    fi

    # Merge new keys into existing
    for provider in "${!new_keys[@]}"; do
        existing_keys["$provider"]="${new_keys[$provider]}"
    done

    # Write back all keys
    {
        echo "# API keys for agent: $username"
        echo "# Managed by manage-api-keys.sh - do not edit directly"
        echo "# Generated: $(date -Iseconds)"
        echo ""
        for provider in "${!existing_keys[@]}"; do
            echo "${provider}=${existing_keys[$provider]}"
        done
    } > "$api_keys_file"

    chown root:root "$api_keys_file"
    chmod 640 "$api_keys_file"
    # Allow the agent user to read the file via group
    chgrp "$(id -gn "$username")" "$api_keys_file"

    echo "API keys updated for agent '$username':"
    for provider in "${!new_keys[@]}"; do
        echo "  $provider = $(mask_key "${new_keys[$provider]}")"
    done
}

cmd_get() {
    if [[ $# -lt 1 ]]; then
        echo "Error: 'get' requires a username." >&2
        usage
    fi

    local username="$1"
    local specific_provider="${2:-}"
    validate_username "$username"

    local api_keys_file
    api_keys_file="$(get_api_keys_file "$username")"

    if [[ ! -f "$api_keys_file" ]]; then
        echo "No API keys configured for agent '$username'."
        return 0
    fi

    echo "API keys for agent '$username':"
    local found=false
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key="$(echo "$key" | xargs)"

        if [[ -n "$specific_provider" ]]; then
            if [[ "$key" == "$specific_provider" ]]; then
                echo "  $key = $(mask_key "$value")"
                found=true
            fi
        else
            echo "  $key = $(mask_key "$value")"
            found=true
        fi
    done < "$api_keys_file"

    if [[ "$found" == "false" ]]; then
        if [[ -n "$specific_provider" ]]; then
            echo "  (no key found for $specific_provider)"
        else
            echo "  (no keys configured)"
        fi
    fi
}

cmd_remove() {
    if [[ $# -lt 2 ]]; then
        echo "Error: 'remove' requires a username and at least one provider name." >&2
        usage
    fi

    local username="$1"
    shift
    validate_username "$username"

    local api_keys_file
    api_keys_file="$(get_api_keys_file "$username")"

    if [[ ! -f "$api_keys_file" ]]; then
        echo "No API keys configured for agent '$username'."
        return 0
    fi

    # Load existing keys
    declare -A existing_keys
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key="$(echo "$key" | xargs)"
        existing_keys["$key"]="$value"
    done < "$api_keys_file"

    # Remove specified keys
    local removed=()
    for provider in "$@"; do
        if [[ -v existing_keys["$provider"] ]]; then
            unset 'existing_keys[$provider]'
            removed+=("$provider")
        else
            echo "Warning: '$provider' not found for agent '$username'." >&2
        fi
    done

    # Write back remaining keys
    if [[ ${#existing_keys[@]} -eq 0 ]]; then
        rm -f "$api_keys_file"
        echo "All API keys removed for agent '$username'."
    else
        {
            echo "# API keys for agent: $username"
            echo "# Managed by manage-api-keys.sh - do not edit directly"
            echo "# Generated: $(date -Iseconds)"
            echo ""
            for provider in "${!existing_keys[@]}"; do
                echo "${provider}=${existing_keys[$provider]}"
            done
        } > "$api_keys_file"
        chown root:root "$api_keys_file"
        chmod 640 "$api_keys_file"
        chgrp "$(id -gn "$username")" "$api_keys_file"

        if [[ ${#removed[@]} -gt 0 ]]; then
            echo "Removed API keys for agent '$username': ${removed[*]}"
        fi
    fi
}

cmd_clear() {
    if [[ $# -lt 1 ]]; then
        echo "Error: 'clear' requires a username." >&2
        usage
    fi

    local username="$1"
    validate_username "$username"

    local api_keys_file
    api_keys_file="$(get_api_keys_file "$username")"

    if [[ -f "$api_keys_file" ]]; then
        rm -f "$api_keys_file"
        echo "All API keys cleared for agent '$username'."
    else
        echo "No API keys configured for agent '$username'."
    fi
}

cmd_list_providers() {
    echo "Known API key providers:"
    echo ""
    for provider in "${KNOWN_PROVIDERS[@]}"; do
        echo "  $provider"
    done
    echo ""
    echo "Note: You can use any PROVIDER_NAME=value format, not just these."
}

# --- Main ---
if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
    set)
        cmd_set "$@"
        ;;
    get)
        cmd_get "$@"
        ;;
    remove)
        cmd_remove "$@"
        ;;
    clear)
        cmd_clear "$@"
        ;;
    list-providers)
        cmd_list_providers
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'." >&2
        usage
        ;;
esac
