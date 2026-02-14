---
name: delegation-workflow
description: Discover team members, delegate tasks, and track progress to completion
---

# Delegation Workflow

## When to Use

Use this skill when you need to coordinate work across multiple agents, assign tasks, and ensure they are completed.

## Procedure

### 1. Discover Team Members

```bash
echo "=== Team Discovery ==="

# List all agent users in the agents group
AGENTS=$(getent group agents 2>/dev/null | cut -d: -f4 | tr ',' '\n')

for agent in $AGENTS; do
  [ -z "$agent" ] && continue
  ROLE=$(getent passwd "$agent" 2>/dev/null | cut -d: -f5)
  HOME_DIR=$(getent passwd "$agent" 2>/dev/null | cut -d: -f6)

  echo "Agent: $agent"
  echo "  Role: $ROLE"
  echo "  Home: $HOME_DIR"

  # Check if agent is alive (recent heartbeat)
  HEARTBEAT_FILE="$HOME_DIR/.heartbeat"
  if [ -f "$HEARTBEAT_FILE" ]; then
    LAST_BEAT=$(cat "$HEARTBEAT_FILE" 2>/dev/null)
    echo "  Last heartbeat: $LAST_BEAT"
  else
    echo "  Last heartbeat: unknown"
  fi

  # Check agent's current task load
  CURRENT_TASKS=$(bash /home/shared/scripts/task.sh list --owner "$agent" --status in_progress 2>/dev/null | jq 'length' 2>/dev/null || echo "unknown")
  echo "  Active tasks: $CURRENT_TASKS"
  echo ""
done
```

### 2. Record Team in MEMORY.md

```bash
cat >> ~/MEMORY.md <<EOF

## Team Roster ($(date +%Y-%m-%d))
$(for agent in $AGENTS; do
  [ -z "$agent" ] && continue
  ROLE=$(getent passwd "$agent" 2>/dev/null | cut -d: -f5)
  echo "- **$agent**: $ROLE"
done)
EOF
```

### 3. Assess Task Fit

Match tasks to agents based on their role:

| Task Type | Best Agent Role | Fallback |
|-----------|----------------|----------|
| Write code, fix bugs | coder | devops |
| Research, gather info | researcher | analyst |
| Design system, architecture | architect | planner |
| Security review, audit | security | reviewer |
| Write tests, QA | qa | coder |
| Write documentation | writer | researcher |
| Review documents | editor | writer |
| Review code | reviewer | coder |
| Plan, decompose tasks | planner | architect |
| Analyze data, metrics | analyst | researcher |
| Docker, CI/CD, infra | devops | coder |
| Triage, routing | ops | manager |

### 4. Delegate via Mail

Send a clear delegation message to the assigned agent:

```bash
AGENT="coder"
TASK_SUBJECT="Implement input validation for task.sh"

# Create the task on the board first
TASK_ID=$(bash /home/shared/scripts/task.sh add \
  --subject "$TASK_SUBJECT" \
  --description "Add argument validation to task.sh add command. Validate: task ID format (alphanumeric+hyphens), subject not empty, status is one of pending/in_progress/completed/failed." \
  --owner "$AGENT" \
  --depends "" 2>/dev/null | jq -r '.id' 2>/dev/null)

echo "Created task: $TASK_ID"

# Send mail with clear instructions
mail -s "Task assigned: $TASK_SUBJECT" "$AGENT" <<EOF
You have been assigned task $TASK_ID.

## What to Do
Add argument validation to the task.sh add command.

## Input
- Source file: /home/shared/scripts/task.sh
- Spec: task IDs must be alphanumeric+hyphens, subject must not be empty, status must be one of pending/in_progress/completed/failed

## Output
- Modified /home/shared/scripts/task.sh with validation added
- Tests passing
- Update task status when complete: bash /home/shared/scripts/task.sh update $TASK_ID --status completed --result "description of what was done"

## Priority
Normal — complete when current work allows.
EOF

echo "Delegation sent to: $AGENT"
```

### 5. Track Progress

Set up tracking in your TODO.md:

```bash
cat >> ~/TODO.md <<EOF

## Delegated Tasks

| Task ID | Subject | Owner | Status | Delegated | Notes |
|---------|---------|-------|--------|-----------|-------|
| $TASK_ID | $TASK_SUBJECT | $AGENT | pending | $(date +%Y-%m-%d) | |
EOF
```

### 6. Follow Up

Periodically check on delegated tasks:

```bash
echo "=== Task Status Check ==="

# Check all tasks you own or delegated
bash /home/shared/scripts/task.sh list 2>/dev/null | jq '
  .[] | select(.status != "completed") |
  {id: .id, subject: .subject, owner: .owner, status: .status}
' 2>/dev/null

echo ""
echo "=== Agent Mail Check ==="
# Check if agents have sent replies (Maildir format)
mail -f ~/Maildir -H 2>/dev/null | tail -20

echo ""
echo "=== Stalled Tasks ==="
# Find tasks that have been in_progress too long
bash /home/shared/scripts/task.sh list --status in_progress 2>/dev/null | jq '
  .[] | select(.updated_at) |
  {id: .id, subject: .subject, owner: .owner, updated: .updated_at}
' 2>/dev/null
```

### 7. Handle Blocked or Failed Tasks

```bash
# If a task is stuck, send a follow-up
STUCK_TASK_ID="T-001"
STUCK_AGENT="coder"

mail -s "Follow-up: task $STUCK_TASK_ID status?" "$STUCK_AGENT" <<EOF
Checking in on task $STUCK_TASK_ID.

Are you blocked? If so, please reply with:
1. What you have completed so far
2. What is blocking you
3. What you need to unblock

If you need the task reassigned, reply with "reassign" and the reason.
EOF
```

### 8. Reassign if Needed

```bash
OLD_AGENT="coder"
NEW_AGENT="devops"
TASK_ID="T-001"

bash /home/shared/scripts/task.sh update "$TASK_ID" --owner "$NEW_AGENT" 2>/dev/null

mail -s "Task reassigned: $TASK_ID" "$NEW_AGENT" <<EOF
Task $TASK_ID has been reassigned to you from $OLD_AGENT.

Please review the task details:
  bash /home/shared/scripts/task.sh get $TASK_ID

Any partial work is at: [location if known]
EOF

mail -s "Task $TASK_ID reassigned" "$OLD_AGENT" <<EOF
Task $TASK_ID has been reassigned to $NEW_AGENT.
No further action needed from you on this task.
EOF
```

## Quality Checklist

- [ ] Team members discovered and roles recorded in MEMORY.md
- [ ] Tasks created on the task board with clear subject and description
- [ ] Each delegation mail includes: what to do, input location, output location, priority
- [ ] TODO.md tracks all delegated tasks
- [ ] Follow-up checks run periodically
- [ ] Blocked or failed tasks are addressed (unblocked or reassigned)
- [ ] Completed tasks are acknowledged
