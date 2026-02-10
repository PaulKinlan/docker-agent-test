---
name: focused-pr
description: Create focused, well-scoped changesets with clear commit messages
---

# Focused PR (Changeset)

## When to Use

Use this skill whenever you commit code. Every commit should be a focused, self-contained unit of change.

## Procedure

### 1. Understand the Scope

Before writing any code, define what this changeset will and will NOT include:

```bash
# Re-read the task to confirm scope
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'
```

Write a one-sentence summary of what this changeset does. If you cannot summarize it in one sentence, the scope is too broad -- split it.

### 2. Work on a Branch

```bash
cd ~/workspace
BRANCH_NAME="task-${TASK_ID}-short-description"
git checkout -b "$BRANCH_NAME"
```

### 3. Make Minimal Changes

Rules:
- Change only what is necessary for the stated goal
- Do NOT fix unrelated issues you notice (note them separately)
- Do NOT refactor adjacent code unless that is the task
- Do NOT add features beyond what was requested
- One logical change per commit

### 4. Review Your Own Changes

Before committing, review everything:

```bash
# See what files changed
git diff --stat

# Review the full diff
git diff

# Check for unintended changes
git diff | grep -E '^\+.*console\.(log|debug|warn)' && echo "WARNING: Debug logging found"
git diff | grep -E '^\+.*#.*TODO|FIXME|HACK' && echo "WARNING: TODO/FIXME found"
git diff | grep -E '^\+.*(\/\/|#).*REMOVE|DELETE|TEMP' && echo "WARNING: Temporary code found"
git diff | grep -E '^\-' | head -20  # Check what was removed — was it intentional?
```

### 5. Check for Common Mistakes

```bash
# Commented-out code (should be deleted, not commented)
git diff | grep -E '^\+\s*(//|#)\s*(function|def |class |const |let |var |import )' \
  && echo "WARNING: Commented-out code found — delete it instead"

# Hardcoded paths or credentials
git diff | grep -E '^\+.*(\/home\/[a-z]|\/Users\/|password|secret|api.?key)' \
  && echo "WARNING: Possible hardcoded path or credential"

# Large files
git diff --stat | awk '{print $NF, $1}' | sort -rn | head -5
```

### 6. Write a Clear Commit Message

Format:
```
<imperative summary, max 50 chars>

- Specific change 1
- Specific change 2
- Specific change 3
```

Examples of good summaries:
- `Add input validation to task.sh`
- `Fix off-by-one in pagination logic`
- `Remove deprecated auth middleware`

Examples of bad summaries:
- `Update files` (too vague)
- `Fixed the bug with the thing` (past tense, unclear)
- `Add validation, fix formatting, update docs` (too many things)

```bash
# Stage specific files (not git add -A)
git add src/module.js tests/module.test.js

# Commit with structured message
git commit -m "Add input validation to task.sh

- Validate task ID format before database lookup
- Return exit code 1 with usage message for invalid IDs
- Add tests for empty, malformed, and valid task IDs"
```

### 7. Verify the Commit

```bash
# Confirm the commit looks right
git log --oneline -1
git show --stat HEAD

# Ensure tests still pass after commit
npm test 2>&1 || python3 -m pytest tests/ -v 2>&1
```

### 8. Note Anything Out of Scope

If you noticed issues while working that are outside this changeset's scope:

```bash
# Log observations for future tasks
cat >> ~/notes.md <<EOF

## Observed Issues (from task $TASK_ID)
- [file:line] Description of issue noticed but not fixed
- [file:line] Potential improvement not in scope
EOF
```

## Commit Message Checklist

- [ ] Summary line is imperative mood ("Add X" not "Added X")
- [ ] Summary line is 50 characters or fewer
- [ ] Blank line between summary and body
- [ ] Body uses bullet points describing specific changes
- [ ] No unrelated changes in the diff
- [ ] No debug logging, commented-out code, or temporary hacks
- [ ] Tests pass after the commit
