---
name: code-review
description: Review code for correctness, security, performance, and style
---

# Code Review

## When to Use

Use this skill when tasked with reviewing code changes, pull requests, or newly written code before it is accepted.

## Review Categories

| Category | Priority | Focus |
|----------|----------|-------|
| **Critical** | Must fix before accepting | Bugs, security vulnerabilities, data loss risks |
| **Important** | Should fix | Missing error handling, performance issues, unclear logic |
| **Minor** | Consider fixing | Style inconsistencies, naming improvements, minor cleanup |
| **Positive** | Acknowledge | Good patterns, clean code, thoughtful design |

## Procedure

### 1. Understand the Context

```bash
# What is this change supposed to do?
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description' 2>/dev/null

# What files changed?
cd ~/workspace
git diff --stat HEAD~1 2>/dev/null || echo "No git history — reviewing all files"
git log --oneline -5 2>/dev/null

# Read the full diff
git diff HEAD~1 2>/dev/null | head -500
```

### 2. Correctness Review

Does the code actually work?

```bash
TARGET="${1:-~/workspace/src}"

# Check: does it handle the stated requirements?
# (Read the code and trace the logic manually)

# Check: edge cases
echo "=== Potential edge cases ==="
# Null/undefined checks
rg '=== null|== null|=== undefined|== undefined|is None' "$TARGET" --type-add 'code:*.{js,py,ts}' --type code -n | head -10
echo "(Verify every nullable value is checked before use)"

# Array bounds
rg '\[0\]|\[-1\]|\.length\b|len\(' "$TARGET" --type-add 'code:*.{js,py,ts}' --type code -n | head -10
echo "(Verify array access is bounds-checked)"

# Check: error handling
rg 'catch|except|\.catch|on\(.error' "$TARGET" --type-add 'code:*.{js,py,ts}' --type code -n | head -10
echo "(Verify errors are handled, not swallowed)"

# Check: does it return/exit correctly in all paths?
rg 'return |process\.exit|sys\.exit' "$TARGET" --type-add 'code:*.{js,py,ts}' --type code -n | head -10
```

### 3. Security Review

```bash
echo "=== Security checks ==="

# No hardcoded secrets
rg -n -i '(password|secret|token|api.?key)\s*[:=]\s*["\x27][a-zA-Z0-9]' "$TARGET" \
  --type-add 'code:*.{js,py,ts,sh}' --type code | head -5

# No user input in dangerous functions
rg -n '(eval|exec|system|popen)\s*\(' "$TARGET" --type-add 'code:*.{js,py,ts}' --type code | head -5

# Input validation present
rg -n '(validate|sanitize|escape|parseInt|Number\(|\.trim\(\))' "$TARGET" \
  --type-add 'code:*.{js,py,ts}' --type code | head -10
echo "(Verify user input is validated before use)"

# No path traversal
rg -n '(req\.(params|query|body).*\.(join|resolve|readFile))' "$TARGET" --type js | head -5
```

### 4. Performance Review

```bash
echo "=== Performance checks ==="

# Nested loops (potential O(n^2))
rg -n 'for.*\{' "$TARGET" --type-add 'code:*.{js,ts}' --type code -A 5 \
  | grep -B 1 'for.*\{' | head -10
echo "(Check if nested loops are necessary)"

# Unbounded growth
rg -n '\.push\(|\.append\(|\.concat\(' "$TARGET" --type-add 'code:*.{js,py,ts}' --type code -B 2 \
  | grep -v 'splice\|pop\|shift\|slice\|limit' | head -10
echo "(Verify arrays/lists have size limits)"

# Resource cleanup
rg -n '(open\(|createReadStream|createConnection|connect\()' "$TARGET" \
  --type-add 'code:*.{js,py,ts}' --type code | head -10
echo "(Verify opened resources are closed — look for .close(), finally, using, with)"

# Synchronous I/O in async code
rg -n '(readFileSync|writeFileSync|execSync)' "$TARGET" --type js | head -5
echo "(Sync I/O blocks the event loop)"
```

### 5. Style Review

```bash
echo "=== Style checks ==="

# Dead code
rg -n '^\s*(//|#)\s*(function|def |class |const |let |var |import )' "$TARGET" \
  --type-add 'code:*.{js,py,ts,sh}' --type code | head -5
echo "(Commented-out code should be deleted)"

# Console.log left in
rg -n 'console\.(log|debug)\(' "$TARGET" --type-add 'code:*.{js,ts}' --type code \
  | grep -v 'test\|spec' | head -5
echo "(Debug logging should be removed or use proper logger)"

# Naming conventions
rg -n '\b(data|info|temp|tmp|foo|bar|baz|x|y|z)\b\s*=' "$TARGET" \
  --type-add 'code:*.{js,py,ts}' --type code | grep -v 'for\s*(' | head -10
echo "(Vague variable names — consider more descriptive names)"

# Consistent formatting
head -3 $(find "$TARGET" -name '*.js' -o -name '*.py' | head -5) 2>/dev/null
echo "(Check: consistent indentation, semicolons, quote style)"
```

### 6. Run Tests

```bash
cd ~/workspace
npm test 2>&1 | tail -10 || python3 -m pytest tests/ -v 2>&1 | tail -10
echo "Test exit code: $?"
```

### 7. Write the Review

```bash
REVIEW_FILE="/home/shared/code-review-$(date +%Y%m%d)-${TASK_ID}.md"

cat > "$REVIEW_FILE" <<'EOF'
# Code Review

**Task:** [task ID and description]
**Reviewer:** [agent name]
**Date:** YYYY-MM-DD
**Verdict:** Approve / Request Changes / Reject

## Summary
[1-2 sentences: overall quality assessment]

## Critical (must fix)
### C1: [title]
- **File:** [path:line]
- **Issue:** [description]
- **Fix:** [specific suggestion]

## Important (should fix)
### I1: [title]
- **File:** [path:line]
- **Issue:** [description]
- **Suggestion:** [specific suggestion]

## Minor (consider)
### M1: [title]
- **File:** [path:line]
- **Note:** [description]

## Positive
- [Something well done — be specific]
- [Good pattern worth noting]

## Test Results
- Tests run: N
- Tests passed: N
- Tests failed: N
EOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "code-review-${TASK_ID}" \
  --type "review" \
  --path "$REVIEW_FILE" \
  --description "Code review for task $TASK_ID"
```

## Quality Checklist

- [ ] Context understood (what the change is supposed to do)
- [ ] Correctness: logic traced, edge cases considered, error handling verified
- [ ] Security: no secrets, no injection, input validated
- [ ] Performance: no O(n^2), no unbounded growth, resources closed
- [ ] Style: no dead code, consistent formatting, clear naming
- [ ] Tests run and results recorded
- [ ] Every finding has file, line, issue description, and specific fix suggestion
- [ ] Positive aspects acknowledged
- [ ] Verdict is clear (approve/request changes/reject)
