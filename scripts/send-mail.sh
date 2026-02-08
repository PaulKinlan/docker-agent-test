#!/bin/bash
# send-mail.sh — Send a mail message to an agent user
#
# Usage: send-mail.sh <recipient> [--from <user>] [--subject <text>] -- <message>
#
# Sends a local mail message to the specified agent. By default, mail is sent
# from root. Use --from to send as a specific user (the command runs as that user).
#
# Options:
#   --from <user>       Send mail as this user (logs in as the user to send)
#   --subject <text>    Set the mail subject (default: "Message")
#
# Examples:
#   send-mail.sh alice -- "Hello from root"
#   send-mail.sh alice --from bob -- "Hello from bob"
#   send-mail.sh alice --from bob --subject "Meeting" -- "Let's sync up"

set -euo pipefail

readonly USAGE="Usage: send-mail.sh <recipient> [--from <user>] [--subject <text>] -- <message>"

# --- Host/container detection ---
# If not running inside the container, proxy the command through docker exec.
# Override the container name with AGENT_HOST_CONTAINER if needed.
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    exec docker exec "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$@"
fi

# --- Parse arguments ---
RECIPIENT=""
FROM_USER=""
SUBJECT="Message"
MESSAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --from requires a value." >&2
                echo "$USAGE" >&2
                exit 1
            fi
            FROM_USER="$2"
            shift 2
            ;;
        --subject)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --subject requires a value." >&2
                echo "$USAGE" >&2
                exit 1
            fi
            SUBJECT="$2"
            shift 2
            ;;
        --)
            shift
            MESSAGE="$*"
            break
            ;;
        -*)
            echo "Error: Unknown option '$1'." >&2
            echo "$USAGE" >&2
            exit 1
            ;;
        *)
            if [[ -z "$RECIPIENT" ]]; then
                RECIPIENT="$1"
            else
                # Treat remaining args as message if no -- separator was used
                MESSAGE="$*"
                break
            fi
            shift
            ;;
    esac
done

if [[ -z "$RECIPIENT" ]]; then
    echo "Error: Recipient is required." >&2
    echo "$USAGE" >&2
    exit 1
fi

if [[ -z "$MESSAGE" ]]; then
    echo "Error: Message is required." >&2
    echo "$USAGE" >&2
    exit 1
fi

# Validate recipient exists (as a user or a mail alias)
if ! id "$RECIPIENT" &>/dev/null; then
    # Check if it's a known mail alias
    if ! grep -q "^${RECIPIENT}:" /etc/smtpd/aliases 2>/dev/null; then
        echo "Error: Recipient '$RECIPIENT' is not a user or a known mail alias." >&2
        exit 1
    fi
fi

# Validate sender exists (if specified)
if [[ -n "$FROM_USER" ]]; then
    if ! id "$FROM_USER" &>/dev/null; then
        echo "Error: Sender '$FROM_USER' does not exist." >&2
        exit 1
    fi
fi

# Send the mail
if [[ -n "$FROM_USER" ]]; then
    printf '%s\n' "$MESSAGE" | runuser -u "$FROM_USER" -- mail -s "$SUBJECT" "$RECIPIENT"
    echo "Mail sent to $RECIPIENT from $FROM_USER."
else
    printf '%s\n' "$MESSAGE" | mail -s "$SUBJECT" "$RECIPIENT"
    echo "Mail sent to $RECIPIENT from root."
fi
