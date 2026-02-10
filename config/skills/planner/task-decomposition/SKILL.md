---
name: task-decomposition
description: Break a high-level goal into concrete actionable tasks with dependencies
---

# Task Decomposition

## When to Use

Use this skill when given a high-level goal that needs to be broken into specific, assignable tasks for a team of agents.

## Procedure

### 1. Read and Understand the Goal

```bash
# Read the goal from the task or input
GOAL_FILE="${1:-/home/shared/goal.md}"
cat "$GOAL_FILE" 2>/dev/null

# Or read from task board
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description' 2>/dev/null
```

Write down:
- **End state:** What does "done" look like? What artifact(s) exist when complete?
- **Constraints:** Deadlines, technology limits, available tools, team size
- **Assumptions:** What are we taking for granted?

### 2. Discover Available Team Members

```bash
echo "=== Available Agents ==="
# List all agent users in the system
getent group agents 2>/dev/null | cut -d: -f4 | tr ',' '\n' | while read agent; do
  if [ -n "$agent" ]; then
    # Get their role from passwd GECOS field
    ROLE=$(getent passwd "$agent" 2>/dev/null | cut -d: -f5)
    echo "  $agent — $ROLE"
  fi
done

echo ""
echo "=== Agent Capabilities ==="
# Check each agent's persona/skills
for agent_home in /home/*/; do
  agent=$(basename "$agent_home")
  [ "$agent" = "shared" ] && continue
  if [ -f "$agent_home/.claude/CLAUDE.md" ]; then
    echo "--- $agent ---"
    head -5 "$agent_home/.claude/CLAUDE.md" 2>/dev/null
  fi
done
```

### 3. Decompose into Tasks

Break the goal into tasks following these rules:

1. **Each task has exactly one owner.** If two personas need to collaborate, create separate tasks with a dependency between them.
2. **Each task has a clear deliverable.** Not "work on X" but "produce X and write it to /home/shared/path."
3. **Each task has explicit inputs and outputs.** Where does the input come from? Where does the output go?
4. **Maximize parallelism.** Tasks that can run concurrently should have no dependency between them.
5. **No cycles in the dependency graph.** Task A depends on B, B depends on A is forbidden.

### 4. Define Each Task

For each task, specify:

```markdown
### Task [ID]: [Subject]
- **Owner:** [persona/agent name]
- **Description:** [What to do — specific and actionable]
- **Input:** [What to read, where to find it]
- **Output:** [What to produce, where to put it]
- **Depends on:** [Task IDs that must complete first, or "none"]
- **Estimate:** [S/M/L — Small: <30min, Medium: 30min-2hr, Large: 2hr+]
```

### 5. Build the Dependency Graph

```bash
# Visualize as text DAG
cat <<'EOF'
Goal: [High-level goal]

  T1 (researcher) ──┐
                     ├──> T3 (architect) ──> T5 (coder) ──> T7 (qa)
  T2 (researcher) ──┘                        │
                                              └──> T6 (writer) ──> T8 (editor)
  T4 (security) ─────────────────────────────────────────────────> T7 (qa)
EOF
```

### 6. Validate the Decomposition

Run these checks:

```bash
# Check 1: Every task has exactly one owner
echo "=== Owner check ==="
# (Manually verify each task has one owner field)

# Check 2: No dependency cycles
echo "=== Cycle check ==="
# List all edges and check for cycles
cat <<'EOF' > /tmp/deps.txt
T3 T1
T3 T2
T5 T3
T6 T3
T7 T5
T7 T4
T8 T6
EOF
# Simple cycle detection: if tsort fails, there is a cycle
tsort /tmp/deps.txt 2>&1
if [ $? -ne 0 ]; then
  echo "ERROR: Dependency cycle detected!"
else
  echo "OK: No cycles"
fi

# Check 3: Clear end state
echo "=== End state check ==="
echo "Final deliverable tasks (no task depends on them):"
# Tasks that appear in column 1 but never in column 2
comm -23 <(cut -d' ' -f1 /tmp/deps.txt | sort -u) <(cut -d' ' -f2 /tmp/deps.txt | sort -u)

# Check 4: Parallelism
echo "=== Parallelism check ==="
echo "Tasks with no dependencies (can start immediately):"
# Tasks in column 2 that never appear in column 1
comm -23 <(cut -d' ' -f2 /tmp/deps.txt | sort -u) <(cut -d' ' -f1 /tmp/deps.txt | sort -u)
```

### 7. Write to Task Board

```bash
# Add each task to the shared task board
bash /home/shared/scripts/task.sh add \
  --subject "Research authentication options" \
  --description "Survey available auth libraries for Node.js. Compare JWT vs session-based. Write findings to /home/shared/research-auth.md" \
  --owner "researcher" \
  --depends ""

bash /home/shared/scripts/task.sh add \
  --subject "Design auth architecture" \
  --description "Based on research, design auth system. Produce design doc at /home/shared/design-auth.md" \
  --owner "architect" \
  --depends "T1"

# ... continue for all tasks
```

### 8. Write the Spec to Shared Workspace

```bash
SPEC_FILE="/home/shared/taskplan-$(date +%Y%m%d).md"

cat > "$SPEC_FILE" <<'EOF'
# Task Plan: [Goal]

**Date:** YYYY-MM-DD
**Planner:** [agent name]

## Goal
[High-level goal statement]

## End State
[What "done" looks like — specific deliverables]

## Task Breakdown

### T1: [Subject] (owner: [persona])
- Description: ...
- Input: ...
- Output: ...
- Depends: none

### T2: ...

## Dependency Graph
```
T1 ──> T3 ──> T5
T2 ──> T3
```

## Parallelism
- Wave 1 (parallel): T1, T2, T4
- Wave 2 (after wave 1): T3
- Wave 3 (after wave 2): T5, T6
- Wave 4 (final): T7, T8

## Risks
- [What could go wrong and how to mitigate]
EOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "task-plan" \
  --type "plan" \
  --path "$SPEC_FILE" \
  --description "Task decomposition plan for: [goal]"
```

## Quality Checklist

- [ ] End state is specific and testable
- [ ] Every task has exactly one owner
- [ ] Every task has specific input and output locations
- [ ] No dependency cycles (tsort succeeds)
- [ ] Parallelism is maximized (tasks that CAN run in parallel DO)
- [ ] Owner assignments match persona capabilities
- [ ] Tasks are written to the task board
- [ ] Spec is written to shared workspace and registered as artifact
