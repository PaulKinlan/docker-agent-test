#!/bin/bash
# load-preset.sh — Load a swarm preset: create agents, wire task DAG, send kickoff mail
#
# Reads a JSON preset file and compiles it into calls to existing primitives:
#   create-agent.sh, task.sh add, send-mail.sh
#
# Usage:
#   load-preset.sh <file> [--dry-run] [--skip-existing]
#
# Options:
#   --dry-run         Print commands without executing
#   --skip-existing   Skip agents that already exist (for re-runs)
#
# Environment variables in the preset (${VAR} or ${VAR:-default}) are expanded
# via bash parameter expansion before parsing. Pass them as env vars:
#   TOPIC="AI Agents" load-preset.sh presets/content-pipeline.json
#
# Examples:
#   load-preset.sh presets/content-pipeline.json
#   load-preset.sh presets/content-pipeline.json --dry-run
#   load-preset.sh presets/codebase-audit.json --skip-existing

set -euo pipefail

readonly USAGE="Usage: load-preset.sh <file> [--dry-run] [--skip-existing] [--check-vars]"

# --- Host/container detection ---
if [[ ! -f /.dockerenv ]]; then
    CONTAINER="${AGENT_HOST_CONTAINER:-agent-host}"
    # Copy preset into container and run there
    PRESET_FILE="${1:-}"
    if [[ -z "$PRESET_FILE" ]]; then
        echo "Error: Preset file is required." >&2
        echo "$USAGE" >&2
        exit 1
    fi
    if [[ ! -f "$PRESET_FILE" ]]; then
        echo "Error: File not found: $PRESET_FILE" >&2
        exit 1
    fi
    # Copy preset into container via stdin (docker cp targets the overlay
    # filesystem which is hidden by systemd's tmpfs mount on /tmp)
    TMPNAME="/tmp/preset-$$.json"
    docker exec -i "$CONTAINER" tee "$TMPNAME" > /dev/null < "$PRESET_FILE"
    # Forward remaining args, replacing the file path with the container-side path
    shift
    # Pass environment variables that might be needed for envsubst
    ENV_ARGS=()
    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        ENV_ARGS+=(-e "$key=$value")
    done < <(env | grep -v '^_=' | grep -v '^SHLVL=' | grep -v '^PWD=' || true)
    docker exec "${ENV_ARGS[@]}" "$CONTAINER" /usr/local/bin/"$(basename "$0")" "$TMPNAME" "$@"
    EXIT_CODE=$?
    docker exec "$CONTAINER" rm -f "$TMPNAME"
    exit $EXIT_CODE
fi

# --- Parse arguments ---
PRESET_FILE=""
DRY_RUN=false
SKIP_EXISTING=false
CHECK_VARS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=true; shift ;;
        --skip-existing) SKIP_EXISTING=true; shift ;;
        --check-vars)   CHECK_VARS=true; shift ;;
        -*)
            echo "Error: Unknown option '$1'." >&2
            echo "$USAGE" >&2
            exit 1
            ;;
        *)
            if [[ -z "$PRESET_FILE" ]]; then
                PRESET_FILE="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$PRESET_FILE" ]]; then
    echo "Error: Preset file is required." >&2
    echo "$USAGE" >&2
    exit 1
fi

if [[ ! -f "$PRESET_FILE" ]]; then
    echo "Error: File not found: $PRESET_FILE" >&2
    exit 1
fi

# --- Phase 1: VALIDATE ---

echo "=== Phase 1: Validate ==="

# Expand environment variables if preset contains ${...} patterns.
# We use bash eval with a heredoc instead of envsubst because envsubst
# does not support ${VAR:-default} syntax — it leaves the literal string
# unchanged when VAR is unset. Bash parameter expansion handles both
# ${VAR} and ${VAR:-default} natively.
RAW=$(cat "$PRESET_FILE")

# --- Check/report environment variables ---
# Extract ${VAR} and ${VAR:-default} patterns from the raw preset
declare -A VAR_DEFAULTS=()
declare -a VAR_NAMES_ORDERED=()
while IFS= read -r varexpr; do
    [[ -z "$varexpr" ]] && continue
    VARNAME="${varexpr%%:-*}"
    if [[ "$varexpr" == *":-"* ]]; then
        VARDEFAULT="${varexpr#*:-}"
    else
        VARDEFAULT=""
    fi
    if [[ -z "${VAR_DEFAULTS[$VARNAME]+isset}" ]]; then
        VAR_NAMES_ORDERED+=("$VARNAME")
        VAR_DEFAULTS[$VARNAME]="$VARDEFAULT"
    fi
done < <(grep -oP '\$\{\K[A-Z_][A-Z0-9_]*(?::-[^}]*)?' "$PRESET_FILE")

if [[ "$CHECK_VARS" == "true" ]]; then
    for VARNAME in "${VAR_NAMES_ORDERED[@]}"; do
        DEFAULT="${VAR_DEFAULTS[$VARNAME]}"
        CURRENT="${!VARNAME:-}"
        if [[ -n "$CURRENT" ]]; then
            echo "  $VARNAME=$CURRENT (set)"
        elif [[ -n "$DEFAULT" ]]; then
            echo "  $VARNAME (default: $DEFAULT)"
        else
            echo "  $VARNAME (required, no default)"
        fi
    done
    exit 0
fi

# Check for unset variables and report
MISSING_REQUIRED=()
for VARNAME in "${VAR_NAMES_ORDERED[@]}"; do
    DEFAULT="${VAR_DEFAULTS[$VARNAME]}"
    CURRENT="${!VARNAME:-}"
    if [[ -z "$CURRENT" && -z "$DEFAULT" ]]; then
        MISSING_REQUIRED+=("$VARNAME")
    elif [[ -z "$CURRENT" && -n "$DEFAULT" ]]; then
        echo "  -> $VARNAME not set, using default: $DEFAULT"
    fi
done

if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
    echo "Error: Required variables not set (no default value):" >&2
    for v in "${MISSING_REQUIRED[@]}"; do
        echo "  $v" >&2
    done
    echo "" >&2
    echo "Set them before running:" >&2
    echo "  ${MISSING_REQUIRED[*]}=<value> load-preset.sh $PRESET_FILE" >&2
    exit 1
fi

if echo "$RAW" | grep -q '${'; then
    PRESET=$(eval "cat <<__PRESET_EOF__
$RAW
__PRESET_EOF__
")
    echo "  -> Environment variables expanded"
else
    PRESET="$RAW"
fi

# Validate JSON
if ! echo "$PRESET" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON in $PRESET_FILE" >&2
    exit 1
fi

# Required fields
PRESET_NAME=$(echo "$PRESET" | jq -r '.name // empty')
if [[ -z "$PRESET_NAME" ]]; then
    echo "Error: Preset missing required field 'name'." >&2
    exit 1
fi

AGENT_COUNT=$(echo "$PRESET" | jq '.agents | length')
if [[ "$AGENT_COUNT" -eq 0 ]]; then
    echo "Error: Preset must declare at least one agent." >&2
    exit 1
fi

TASK_COUNT=$(echo "$PRESET" | jq '.tasks | length')
if [[ "$TASK_COUNT" -eq 0 ]]; then
    echo "Error: Preset must declare at least one task." >&2
    exit 1
fi

# Collect declared agent names and task IDs for cross-referencing
AGENT_NAMES=$(echo "$PRESET" | jq -r '.agents[].name')
TASK_IDS=$(echo "$PRESET" | jq -r '.tasks[].id')

# Every task owner must reference a declared agent
while IFS= read -r owner; do
    if ! echo "$AGENT_NAMES" | grep -qx "$owner"; then
        echo "Error: Task owner '$owner' is not a declared agent." >&2
        exit 1
    fi
done < <(echo "$PRESET" | jq -r '.tasks[].owner')

# Every blocked_by entry must reference a declared task ID
while IFS= read -r dep; do
    [[ -z "$dep" || "$dep" == "null" ]] && continue
    if ! echo "$TASK_IDS" | grep -qx "$dep"; then
        echo "Error: blocked_by references unknown task '$dep'." >&2
        exit 1
    fi
done < <(echo "$PRESET" | jq -r '.tasks[].blocked_by[]? // empty')

# Topological sort — iterative, detect cycles
# Build ordered list of task IDs where blockers come before dependents
declare -a TOPO_ORDER=()
declare -A PLACED=()

TASK_ID_LIST=()
while IFS= read -r tid; do
    TASK_ID_LIST+=("$tid")
done < <(echo "$TASK_IDS")

MAX_ITER=${#TASK_ID_LIST[@]}
for (( iter=0; iter<=MAX_ITER; iter++ )); do
    if [[ ${#TOPO_ORDER[@]} -eq ${#TASK_ID_LIST[@]} ]]; then
        break
    fi
    PROGRESS=false
    for tid in "${TASK_ID_LIST[@]}"; do
        [[ -n "${PLACED[$tid]:-}" ]] && continue
        # Check all blockers are placed
        ALL_PLACED=true
        while IFS= read -r dep; do
            [[ -z "$dep" || "$dep" == "null" ]] && continue
            if [[ -z "${PLACED[$dep]:-}" ]]; then
                ALL_PLACED=false
                break
            fi
        done < <(echo "$PRESET" | jq -r --arg id "$tid" '.tasks[] | select(.id == $id) | .blocked_by[]? // empty')
        if [[ "$ALL_PLACED" == "true" ]]; then
            TOPO_ORDER+=("$tid")
            PLACED[$tid]=1
            PROGRESS=true
        fi
    done
    if [[ "$PROGRESS" == "false" && ${#TOPO_ORDER[@]} -lt ${#TASK_ID_LIST[@]} ]]; then
        echo "Error: Cycle detected in task dependencies." >&2
        echo "  Placed: ${TOPO_ORDER[*]}" >&2
        echo "  Remaining:" >&2
        for tid in "${TASK_ID_LIST[@]}"; do
            [[ -z "${PLACED[$tid]:-}" ]] && echo "    $tid" >&2
        done
        exit 1
    fi
done

echo "  -> Preset '$PRESET_NAME': $AGENT_COUNT agents, $TASK_COUNT tasks"
echo "  -> Task order: ${TOPO_ORDER[*]}"
echo "  -> Validation passed"

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "=== DRY RUN — commands that would execute ==="
    echo ""

    echo "# Phase 2: Create agents"
    for i in $(seq 0 $((AGENT_COUNT - 1))); do
        NAME=$(echo "$PRESET" | jq -r ".agents[$i].name")
        PERSONA=$(echo "$PRESET" | jq -r ".agents[$i].persona // empty")
        INSTRUCTIONS=$(echo "$PRESET" | jq -r ".agents[$i].instructions // empty")
        CMD="create-agent.sh $NAME"
        [[ -n "$PERSONA" ]] && CMD="$CMD --persona $PERSONA"
        [[ -n "$INSTRUCTIONS" ]] && CMD="$CMD --instructions \"$INSTRUCTIONS\""
        echo "  $CMD"
    done

    echo ""
    echo "# Phase 3: Create tasks (topological order)"
    for tid in "${TOPO_ORDER[@]}"; do
        TASK_JSON=$(echo "$PRESET" | jq -c --arg id "$tid" '.tasks[] | select(.id == $id)')
        SUBJECT=$(echo "$TASK_JSON" | jq -r '.subject')
        OWNER=$(echo "$TASK_JSON" | jq -r '.owner')
        DESC=$(echo "$TASK_JSON" | jq -r '.description // empty')
        DEPS=$(echo "$TASK_JSON" | jq -r '.blocked_by // [] | join(",")')
        CMD="task.sh add \"$SUBJECT\" --owner $OWNER"
        [[ -n "$DESC" ]] && CMD="$CMD --description \"$DESC\""
        [[ -n "$DEPS" ]] && CMD="$CMD --blocked-by <resolved:$DEPS>"
        echo "  $CMD  # id=$tid"
    done

    MAIL_COUNT=$(echo "$PRESET" | jq '.mail // [] | length')
    if [[ "$MAIL_COUNT" -gt 0 ]]; then
        echo ""
        echo "# Phase 4: Send kickoff mail"
        for i in $(seq 0 $((MAIL_COUNT - 1))); do
            TO=$(echo "$PRESET" | jq -r ".mail[$i].to")
            SUBJ=$(echo "$PRESET" | jq -r ".mail[$i].subject // \"Preset loaded\"")
            BODY=$(echo "$PRESET" | jq -r ".mail[$i].body // \"\"")
            echo "  send-mail.sh $TO --subject \"$SUBJ\" -- \"$BODY\""
        done
    fi

    echo ""
    echo "=== End dry run ==="
    exit 0
fi

# --- Phase 2: CREATE AGENTS ---

echo ""
echo "=== Phase 2: Create agents ==="

for i in $(seq 0 $((AGENT_COUNT - 1))); do
    NAME=$(echo "$PRESET" | jq -r ".agents[$i].name")
    PERSONA=$(echo "$PRESET" | jq -r ".agents[$i].persona // empty")
    INSTRUCTIONS=$(echo "$PRESET" | jq -r ".agents[$i].instructions // empty")

    if [[ "$SKIP_EXISTING" == "true" ]] && id "$NAME" &>/dev/null; then
        echo "  -> Skipping $NAME (already exists)"
        continue
    fi

    ARGS=("$NAME")
    [[ -n "$PERSONA" ]] && ARGS+=(--persona "$PERSONA")
    [[ -n "$INSTRUCTIONS" ]] && ARGS+=(--instructions "$INSTRUCTIONS")

    echo "  -> Creating agent: $NAME${PERSONA:+ (persona=$PERSONA)}"
    /usr/local/bin/create-agent.sh "${ARGS[@]}"
done

# --- Phase 3: CREATE TASKS (topological order) ---

echo ""
echo "=== Phase 3: Create tasks ==="

declare -A ID_MAP=()  # symbolic -> real task ID

for tid in "${TOPO_ORDER[@]}"; do
    TASK_JSON=$(echo "$PRESET" | jq -c --arg id "$tid" '.tasks[] | select(.id == $id)')
    SUBJECT=$(echo "$TASK_JSON" | jq -r '.subject')
    OWNER=$(echo "$TASK_JSON" | jq -r '.owner')
    DESC=$(echo "$TASK_JSON" | jq -r '.description // empty')
    DEPS_JSON=$(echo "$TASK_JSON" | jq -r '.blocked_by // []')

    ARGS=("$SUBJECT" --owner "$OWNER")
    [[ -n "$DESC" ]] && ARGS+=(--description "$DESC")

    # Resolve symbolic blocked_by -> real IDs
    DEP_COUNT=$(echo "$DEPS_JSON" | jq 'length')
    if [[ "$DEP_COUNT" -gt 0 ]]; then
        REAL_DEPS=()
        while IFS= read -r dep; do
            REAL_ID="${ID_MAP[$dep]:-}"
            if [[ -z "$REAL_ID" ]]; then
                echo "Error: Could not resolve dependency '$dep' for task '$tid'." >&2
                exit 1
            fi
            REAL_DEPS+=("$REAL_ID")
        done < <(echo "$DEPS_JSON" | jq -r '.[]')
        BLOCKED_BY=$(IFS=','; echo "${REAL_DEPS[*]}")
        ARGS+=(--blocked-by "$BLOCKED_BY")
    fi

    REAL_ID=$(/usr/local/bin/task.sh add "${ARGS[@]}")
    ID_MAP[$tid]="$REAL_ID"
    echo "  -> $tid => $REAL_ID: $SUBJECT (owner=$OWNER)"
done

# --- Phase 4: SEND KICKOFF MAIL (best-effort) ---

MAIL_COUNT=$(echo "$PRESET" | jq '.mail // [] | length')
if [[ "$MAIL_COUNT" -gt 0 ]]; then
    echo ""
    echo "=== Phase 4: Send kickoff mail ==="

    for i in $(seq 0 $((MAIL_COUNT - 1))); do
        TO=$(echo "$PRESET" | jq -r ".mail[$i].to")
        SUBJ=$(echo "$PRESET" | jq -r ".mail[$i].subject // \"Preset loaded\"")
        BODY=$(echo "$PRESET" | jq -r ".mail[$i].body // \"\"")

        echo "  -> Mail to $TO: $SUBJ"
        /usr/local/bin/send-mail.sh "$TO" --subject "$SUBJ" -- "$BODY" || {
            echo "  Warning: Failed to send mail to $TO (continuing)" >&2
        }
    done
fi

# --- Phase 5: EMIT STATE ---

echo ""
echo "=== Phase 5: Save state ==="

# Build ID map as JSON
ID_MAP_JSON="{"
FIRST=true
for tid in "${TOPO_ORDER[@]}"; do
    [[ "$FIRST" == "true" ]] && FIRST=false || ID_MAP_JSON+=","
    ID_MAP_JSON+="\"$tid\":\"${ID_MAP[$tid]}\""
done
ID_MAP_JSON+="}"

# Build agents list as JSON array
AGENTS_JSON=$(echo "$AGENT_NAMES" | jq -R . | jq -s .)

# Write state file
STATE_FILE="/home/shared/.preset-state.json"
jq -n \
    --arg preset "$PRESET_NAME" \
    --arg loaded_at "$(date -Iseconds)" \
    --argjson id_map "$ID_MAP_JSON" \
    --argjson agents "$AGENTS_JSON" \
    '{preset: $preset, loaded_at: $loaded_at, id_map: $id_map, agents: $agents}' \
    > "$STATE_FILE"

echo "  -> State saved to $STATE_FILE"
echo ""
echo "=== Preset '$PRESET_NAME' loaded ==="
echo "  Agents: $AGENT_COUNT"
echo "  Tasks:  $TASK_COUNT"
echo "  Mail:   $MAIL_COUNT"
echo ""
echo "  View task graph:  task.sh graph"
echo "  View swarm status: swarm-status.sh"
