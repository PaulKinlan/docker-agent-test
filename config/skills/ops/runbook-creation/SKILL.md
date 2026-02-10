---
name: runbook-creation
description: Create operational runbooks with step-by-step procedures, decision points, and rollback instructions
---

# Runbook Creation

## When to Use

Use this skill when you need to produce a step-by-step operational guide for handling a specific scenario. Runbooks are used by operators who need to execute a procedure reliably under pressure -- every step must be concrete, copy-paste-ready, and unambiguous. Typical scenarios include incident response, maintenance windows, deployment procedures, data recovery, and capacity management.

## Output Template

```markdown
# Runbook: [Scenario Title]

**Version:** 1.0
**Author:** [agent name]
**Created:** [YYYY-MM-DD]
**Last Tested:** [YYYY-MM-DD or "Not yet tested"]
**Estimated Duration:** [time estimate]

## Scenario
[One-paragraph description of when this runbook applies. Include trigger conditions -- what event or observation causes an operator to reach for this runbook.]

## Prerequisites
- [ ] [Access, credentials, or permissions required]
- [ ] [Tools or software that must be available]
- [ ] [Data or configuration that must exist beforehand]
- [ ] [People who must be notified or on standby]

## Procedure

### Step 1: [Action Name]
**Purpose:** [Why this step is necessary]
```
[exact command to run]
```
**Expected output:** [what the operator should see]
**If unexpected:** [what to do if output differs -- go to Step N or see Rollback]

### Step 2: [Action Name]
...

### Decision Point: [Condition]
- **If [condition A]:** proceed to Step N
- **If [condition B]:** proceed to Step M
- **If unclear:** escalate (see Escalation section)

## Verification
[Commands to confirm the procedure succeeded]

## Rollback Procedure
[Numbered steps to undo the changes if something goes wrong]

## Escalation
| Condition | Contact | Method | Template |
|-----------|---------|--------|----------|
| [when to escalate] | [who] | [how] | [message] |

## Notes
- [Edge cases, known issues, lessons learned]
```

## Procedure

### 1. Identify the Scenario

Read the task and determine what operational scenario the runbook should cover:

```bash
TASK_ID="$1"
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'

# Check if there are existing runbooks to avoid duplication
find /home/shared/ -name 'runbook-*' -o -name 'RUNBOOK-*' 2>/dev/null | while read f; do
  echo "=== Existing: $f ==="
  head -5 "$f"
done
```

Write down:
- The specific scenario (what triggers this runbook)
- Who will execute it (their skill level and available tools)
- What the successful end state looks like

### 2. Gather Context and Constraints

Collect the information needed to write accurate, runnable commands:

```bash
# Identify what tools are available in the target environment
for cmd in bash jq python3 curl rg find systemctl journalctl docker mail; do
  which "$cmd" >/dev/null 2>&1 && echo "Available: $cmd" || echo "Missing: $cmd"
done

# Check shared scripts that might be referenced
ls /home/shared/scripts/ 2>/dev/null

# Read any related documentation or prior runbooks
find /home/shared/ -name '*.md' 2>/dev/null | xargs grep -li "$SCENARIO_KEYWORD" 2>/dev/null | head -10

# Check for relevant configuration
find /home/shared/ -name '*.json' -o -name '*.yaml' -o -name '*.conf' 2>/dev/null | head -10
```

### 3. Document Prerequisites

List everything the operator needs before starting. Verify each prerequisite is checkable:

```bash
# Generate a prerequisite checklist by testing the current environment
PREREQS_FILE=$(mktemp /tmp/prereqs-XXXXXX.md)

cat > "$PREREQS_FILE" <<'EOF'
## Prerequisites

- [ ] Access to the target system (verify: `whoami && hostname`)
- [ ] Required tools installed (verify: `which jq python3 bash`)
- [ ] Shared scripts accessible (verify: `ls /home/shared/scripts/`)
- [ ] Task board is operational (verify: `bash /home/shared/scripts/task.sh list 2>/dev/null | head -1`)
- [ ] Sufficient disk space (verify: `df -h / | tail -1`)
EOF

cat "$PREREQS_FILE"
```

Each prerequisite must include a verification command so the operator can confirm it before proceeding.

### 4. Write the Step-by-Step Procedure

For each step, write: purpose, exact command, expected output, and failure path.

```bash
SCENARIO_NAME="$2"  # e.g., "data-recovery" or "capacity-scale-up"
RUNBOOK_FILE="/home/shared/runbook-$(date +%Y%m%d)-${SCENARIO_NAME}.md"

# Start the runbook
cat > "$RUNBOOK_FILE" <<HEADER
# Runbook: ${SCENARIO_NAME}

**Version:** 1.0
**Author:** $(whoami)
**Created:** $(date +%Y-%m-%d)
**Last Tested:** Not yet tested
**Estimated Duration:** [FILL IN]

## Scenario
[FILL IN: One paragraph describing when to use this runbook]

## Prerequisites
- [ ] [FILL IN]

## Procedure

HEADER

echo "Runbook skeleton created at: $RUNBOOK_FILE"
```

For each step, follow this pattern:

```bash
# Append a step to the runbook
STEP_NUM=1
STEP_NAME="Assess current state"
STEP_PURPOSE="Establish a baseline before making any changes"
STEP_COMMAND='bash /home/shared/scripts/task.sh list --status in_progress 2>/dev/null | jq "length"'
STEP_EXPECTED="A number indicating how many tasks are in progress"
STEP_FAILURE="If the command fails, verify the task board is accessible (see Prerequisites)"

cat >> "$RUNBOOK_FILE" <<STEP
### Step ${STEP_NUM}: ${STEP_NAME}
**Purpose:** ${STEP_PURPOSE}
\`\`\`bash
${STEP_COMMAND}
\`\`\`
**Expected output:** ${STEP_EXPECTED}
**If unexpected:** ${STEP_FAILURE}

STEP
```

### 5. Add Decision Points

Identify branching logic in the procedure and write explicit decision trees:

```bash
cat >> "$RUNBOOK_FILE" <<'DECISION'
### Decision Point: Evaluate System Load

Check current resource usage:
```bash
# Check CPU and memory
top -bn1 | head -5
df -h / | tail -1
```

Evaluate the results:
- **If CPU < 80% and disk < 70%:** proceed to Step 4 (standard procedure)
- **If CPU >= 80% or disk >= 70%:** proceed to Step 5 (resource constrained path)
- **If any service is down:** STOP and proceed to Escalation

DECISION
```

### 6. Write Verification Commands

Add commands that confirm the procedure achieved its goal:

```bash
cat >> "$RUNBOOK_FILE" <<'VERIFY'
## Verification

Run these checks to confirm the procedure succeeded:

```bash
# Check 1: Verify expected outcome
echo "=== Verification ==="

# Check that tasks are in the expected state
bash /home/shared/scripts/task.sh list --status completed 2>/dev/null | jq 'length'

# Check that artifacts were registered
bash /home/shared/scripts/artifact.sh list 2>/dev/null | jq 'length'

# Check that no error conditions remain
find /home/shared/ -name '*.error' -newer /tmp/runbook-start 2>/dev/null
ERRORS=$?
if [ "$ERRORS" -eq 0 ]; then
  echo "PASS: No error files found"
else
  echo "FAIL: Error files present -- investigate before closing"
fi
```

**All checks must pass before marking the procedure complete.**

VERIFY
```

### 7. Write the Rollback Procedure

Document how to undo every change made by the procedure:

```bash
cat >> "$RUNBOOK_FILE" <<'ROLLBACK'
## Rollback Procedure

If the procedure fails at any step, execute these steps in reverse order:

### Rollback Step 1: Restore Previous State
```bash
# Identify what was changed
echo "Checking for changes since runbook started..."
find /home/shared/ -newer /tmp/runbook-start -type f 2>/dev/null

# Restore from backup if one was created in Step 1
if [ -d "/home/shared/backup-$(date +%Y%m%d)" ]; then
  echo "Backup found. Restoring..."
  cp -r "/home/shared/backup-$(date +%Y%m%d)/"* /home/shared/
  echo "Restore complete."
else
  echo "No backup found. Manual intervention required."
fi
```

### Rollback Step 2: Notify Stakeholders
```bash
bash /home/shared/scripts/send-mail.sh manager <<EOF
Runbook rollback executed.
Scenario: ${SCENARIO_NAME}
Reason: [FILL IN the failure reason]
Current state: [FILL IN current system state]
Action needed: [FILL IN what needs to happen next]
EOF
```

### Rollback Step 3: Update Task Board
```bash
bash /home/shared/scripts/task.sh update "$TASK_ID" \
  --status blocked \
  --result "Runbook failed at step [N]. Rollback executed. See runbook for details."
```

ROLLBACK
```

### 8. Add Escalation Paths

```bash
cat >> "$RUNBOOK_FILE" <<'ESCALATION'
## Escalation

| Condition | Contact | Method | Message Template |
|-----------|---------|--------|------------------|
| Procedure fails after rollback | manager | `bash /home/shared/scripts/send-mail.sh manager` | "Runbook [name] failed. Rollback completed but manual intervention needed. Details: [describe]" |
| Data loss suspected | manager, security | `bash /home/shared/scripts/send-mail.sh manager && bash /home/shared/scripts/send-mail.sh security` | "Potential data loss during [scenario]. Affected scope: [describe]. Immediate review requested." |
| Uncertain which path to take | architect | `bash /home/shared/scripts/send-mail.sh architect` | "Runbook [name] reached decision point at step [N]. Condition unclear: [describe]. Awaiting guidance." |

### Notification Templates

**Procedure started:**
```bash
bash /home/shared/scripts/send-mail.sh manager <<EOF
Runbook started: [scenario name]
Operator: $(whoami)
Time: $(date -Iseconds)
Task: $TASK_ID
Expected duration: [estimate]
EOF
```

**Procedure completed:**
```bash
bash /home/shared/scripts/send-mail.sh manager <<EOF
Runbook completed: [scenario name]
Operator: $(whoami)
Time: $(date -Iseconds)
Duration: [actual time]
Result: SUCCESS / PARTIAL / ROLLED BACK
Verification: All checks passed / [describe failures]
EOF
```

ESCALATION
```

### 9. Test Every Command

Before finalizing, verify that each command in the runbook is syntactically correct:

```bash
# Extract all code blocks and syntax-check them
grep -A1 '```bash' "$RUNBOOK_FILE" | grep -v '```' | grep -v '^--$' | while read line; do
  bash -n <(echo "$line") 2>&1 && echo "OK: $line" || echo "SYNTAX ERROR: $line"
done
```

### 10. Register the Runbook

```bash
bash /home/shared/scripts/artifact.sh register \
  --name "runbook-${SCENARIO_NAME}" \
  --type "runbook" \
  --path "$RUNBOOK_FILE" \
  --description "Operational runbook for ${SCENARIO_NAME}"

echo "Runbook registered: $RUNBOOK_FILE"
```

## Quality Checklist

- [ ] Scenario description clearly states when this runbook applies (trigger conditions)
- [ ] Every prerequisite has a verification command
- [ ] Every step has: purpose, exact command, expected output, and failure path
- [ ] All commands are copy-paste-ready (no placeholders that the operator must guess)
- [ ] Decision points have explicit conditions and destinations (step numbers)
- [ ] Rollback procedure undoes every change made by the forward procedure
- [ ] Verification section confirms the end state with runnable checks
- [ ] Escalation paths specify: condition, contact, method, and message template
- [ ] Notification templates are provided for start, completion, and failure
- [ ] All bash commands pass syntax checking (`bash -n`)
- [ ] Estimated duration is realistic and stated
- [ ] No step requires information not provided in the runbook or prerequisites
