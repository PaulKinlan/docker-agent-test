---
name: triage-routing
description: Classify incoming requests and route to the appropriate specialist agent
---

# Triage and Routing

## When to Use

Use this skill when a new request, issue, or task arrives that needs to be classified and sent to the right agent.

## Classification Table

| Request Type | Primary Persona | Secondary Persona | Keywords |
|-------------|----------------|-------------------|----------|
| Bug report | coder | qa | bug, broken, crash, error, fail, wrong |
| Feature request | planner | architect | add, new, feature, implement, support |
| Security issue | security | coder | vulnerability, CVE, leak, auth, injection, XSS |
| Documentation | writer | editor | docs, readme, guide, explain, how-to |
| Performance | coder | analyst | slow, timeout, memory, CPU, optimize, latency |
| Data analysis | analyst | researcher | data, metrics, report, statistics, trends |
| Architecture | architect | planner | design, system, scale, migrate, refactor (large) |
| Code review | reviewer | coder | review, PR, changeset, approve |
| Infrastructure | devops | coder | docker, CI, deploy, build, pipeline, container |
| Research | researcher | analyst | research, compare, evaluate, investigate |
| Test/QA | qa | coder | test, quality, regression, coverage, validate |
| Edit/review doc | editor | writer | review, proofread, edit, clarity |

## Urgency Levels

| Level | Criteria | Response Time | Examples |
|-------|----------|---------------|----------|
| **Urgent** | System down, data loss risk, security breach | Immediate — interrupt current work | Production crash, credential leak, data corruption |
| **Normal** | Bug affecting users, blocking task | Next available slot | Feature broken, test failures, blocked dependency |
| **Low** | Nice-to-have, non-blocking improvement | When current work completes | Refactoring suggestion, docs improvement, minor style |

## Procedure

### 1. Read the Incoming Request

```bash
# Read from mail (Maildir format)
mail -f ~/Maildir -H 2>/dev/null | tail -20

# Or read from task board (unassigned tasks)
bash /home/shared/scripts/task.sh list --status pending 2>/dev/null | jq '
  .[] | select(.owner == null or .owner == "" or .owner == "unassigned") |
  {id: .id, subject: .subject, description: .description}
' 2>/dev/null

# Or read from a specific file
cat /home/shared/inbox/*.txt 2>/dev/null
```

### 2. Classify the Request

Determine type and urgency:

```bash
REQUEST_TEXT="$1"  # The request text

# Auto-classify by keyword matching
classify_type() {
  local text=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  if echo "$text" | grep -qE 'bug|broken|crash|error|fail|wrong|not working'; then
    echo "bug"
  elif echo "$text" | grep -qE 'vulnerab|cve|leak|auth.*bypass|inject|xss|security'; then
    echo "security"
  elif echo "$text" | grep -qE 'slow|timeout|memory|cpu|optimi|latency|performance'; then
    echo "performance"
  elif echo "$text" | grep -qE 'add|new|feature|implement|support|request'; then
    echo "feature"
  elif echo "$text" | grep -qE 'doc|readme|guide|explain|how.to|write.*up'; then
    echo "documentation"
  elif echo "$text" | grep -qE 'data|metric|report|statistic|trend|analy'; then
    echo "data"
  elif echo "$text" | grep -qE 'docker|ci|deploy|build|pipeline|container|infra'; then
    echo "infrastructure"
  elif echo "$text" | grep -qE 'review|pr|changeset|approve|code.*review'; then
    echo "code-review"
  elif echo "$text" | grep -qE 'test|quality|regression|coverage|validate|qa'; then
    echo "test"
  elif echo "$text" | grep -qE 'design|system|scale|migrat|architect'; then
    echo "architecture"
  elif echo "$text" | grep -qE 'research|compare|evaluat|investigat'; then
    echo "research"
  else
    echo "general"
  fi
}

classify_urgency() {
  local text=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  if echo "$text" | grep -qE 'urgent|down|breach|data.loss|critical|emergency|asap|production'; then
    echo "urgent"
  elif echo "$text" | grep -qE 'bug|block|fail|broken|not working'; then
    echo "normal"
  else
    echo "low"
  fi
}

TYPE=$(classify_type "$REQUEST_TEXT")
URGENCY=$(classify_urgency "$REQUEST_TEXT")

echo "Type: $TYPE"
echo "Urgency: $URGENCY"
```

### 3. Find the Best Agent

```bash
# Map type to persona
case "$TYPE" in
  bug)             PRIMARY="coder"; SECONDARY="qa" ;;
  security)        PRIMARY="security"; SECONDARY="coder" ;;
  performance)     PRIMARY="coder"; SECONDARY="analyst" ;;
  feature)         PRIMARY="planner"; SECONDARY="architect" ;;
  documentation)   PRIMARY="writer"; SECONDARY="editor" ;;
  data)            PRIMARY="analyst"; SECONDARY="researcher" ;;
  infrastructure)  PRIMARY="devops"; SECONDARY="coder" ;;
  code-review)     PRIMARY="reviewer"; SECONDARY="coder" ;;
  test)            PRIMARY="qa"; SECONDARY="coder" ;;
  architecture)    PRIMARY="architect"; SECONDARY="planner" ;;
  research)        PRIMARY="researcher"; SECONDARY="analyst" ;;
  *)               PRIMARY="coder"; SECONDARY="planner" ;;
esac

echo "Primary: $PRIMARY"
echo "Secondary: $SECONDARY"

# Check if primary agent is available
PRIMARY_AGENT=""
SECONDARY_AGENT=""

getent group agents 2>/dev/null | cut -d: -f4 | tr ',' '\n' | while read agent; do
  ROLE=$(getent passwd "$agent" 2>/dev/null | cut -d: -f5)
  case "$ROLE" in
    *$PRIMARY*) [ -z "$PRIMARY_AGENT" ] && PRIMARY_AGENT="$agent" ;;
    *$SECONDARY*) [ -z "$SECONDARY_AGENT" ] && SECONDARY_AGENT="$agent" ;;
  esac
done

# Choose agent: prefer primary, fall back to secondary
TARGET_AGENT="${PRIMARY_AGENT:-$SECONDARY_AGENT}"
echo "Routing to: $TARGET_AGENT"
```

### 4. Forward with Triage Notes

```bash
TASK_ID="$2"  # If a task already exists
TARGET_AGENT="${TARGET_AGENT:-coder}"

# Create task if not exists
if [ -z "$TASK_ID" ]; then
  TASK_ID=$(bash /home/shared/scripts/task.sh add \
    --subject "$(echo "$REQUEST_TEXT" | head -1 | cut -c1-80)" \
    --description "$REQUEST_TEXT" \
    --owner "$TARGET_AGENT" 2>/dev/null | jq -r '.id' 2>/dev/null)
else
  bash /home/shared/scripts/task.sh update "$TASK_ID" --owner "$TARGET_AGENT" 2>/dev/null
fi

# Send with triage context
mail -s "[${URGENCY^^}] Triaged: $(echo "$REQUEST_TEXT" | head -1 | cut -c1-60)" "$TARGET_AGENT" <<EOF
## Triage Notes
- **Type:** $TYPE
- **Urgency:** $URGENCY
- **Task ID:** $TASK_ID
- **Triaged by:** $(whoami)
- **Triaged at:** $(date -Iseconds)

## Original Request
$REQUEST_TEXT

## Suggested Approach
$(case "$TYPE" in
  bug)        echo "1. Reproduce the issue\n2. Identify root cause\n3. Fix and add test\n4. Verify fix" ;;
  security)   echo "1. Assess severity and impact\n2. Determine if actively exploitable\n3. Implement fix\n4. Verify remediation" ;;
  feature)    echo "1. Clarify requirements\n2. Design approach\n3. Decompose into subtasks\n4. Delegate implementation" ;;
  documentation) echo "1. Identify audience\n2. Read source material\n3. Draft document\n4. Verify code examples work" ;;
  *)          echo "Review the request and proceed according to your role's standard procedures." ;;
esac)

Please update the task when you begin and when you complete:
  bash /home/shared/scripts/task.sh update $TASK_ID --status in_progress
  bash /home/shared/scripts/task.sh update $TASK_ID --status completed --result "..."
EOF

echo "Routed task $TASK_ID to $TARGET_AGENT"
```

### 5. Log the Triage Decision

```bash
mkdir -p ~/triage

cat >> ~/triage/log.jsonl <<EOF
{"timestamp":"$(date -Iseconds)","task_id":"$TASK_ID","request_summary":"$(echo "$REQUEST_TEXT" | head -1 | tr '"' "'")","type":"$TYPE","urgency":"$URGENCY","routed_to":"$TARGET_AGENT","triaged_by":"$(whoami)"}
EOF

echo "Triage logged to ~/triage/log.jsonl"
```

### 6. Handle Urgent Requests

For urgent items, take additional steps:

```bash
if [ "$URGENCY" = "urgent" ]; then
  echo "=== URGENT HANDLING ==="

  # Check if the agent is active
  HEARTBEAT=$(cat /home/$TARGET_AGENT/.heartbeat 2>/dev/null)
  echo "Agent heartbeat: $HEARTBEAT"

  # If agent seems inactive, notify manager or try secondary
  if [ -z "$HEARTBEAT" ]; then
    echo "WARNING: Primary agent may be inactive. Notifying manager."
    mail -s "[URGENT] Agent $TARGET_AGENT unresponsive — task $TASK_ID needs attention" manager <<EOF
Urgent task $TASK_ID was routed to $TARGET_AGENT but they appear inactive.
Type: $TYPE
Request: $(echo "$REQUEST_TEXT" | head -3)

Please reassign or escalate.
EOF
  fi
fi
```

## Quality Checklist

- [ ] Request has been read and understood
- [ ] Type classified correctly (matches keywords and context)
- [ ] Urgency assessed (urgent/normal/low)
- [ ] Best agent identified based on type-to-persona mapping
- [ ] Task created on the task board with owner assigned
- [ ] Delegation mail sent with: triage notes, original request, suggested approach
- [ ] Triage decision logged in ~/triage/log.jsonl
- [ ] Urgent requests have additional follow-up (heartbeat check, escalation)
