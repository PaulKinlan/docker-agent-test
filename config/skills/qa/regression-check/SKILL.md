---
name: regression-check
description: Verify recent changes have not broken existing functionality
---

# Regression Check

## When to Use

Use this skill after code changes, merges, or refactors to confirm that existing functionality still works correctly.

## Procedure

### 1. Identify What Changed

```bash
cd ~/workspace

echo "=== Files changed ==="
git diff --stat HEAD~3 2>/dev/null || git diff --stat 2>/dev/null

echo ""
echo "=== Recent commits ==="
git log --oneline -10 2>/dev/null

echo ""
echo "=== Changed functions/classes ==="
git diff HEAD~3 2>/dev/null | grep -E '^\+.*(function |def |class |const .* = )' | head -20
```

If no git history is available, compare against a known baseline:

```bash
# Check file modification times
find . -name '*.js' -o -name '*.py' -o -name '*.sh' \
  | xargs ls -lt 2>/dev/null | head -20
```

### 2. Run the Full Test Suite

```bash
cd ~/workspace

echo "=== Running full test suite ==="
if [ -f package.json ]; then
  npm test 2>&1 | tee /tmp/regression-tests.txt
  TEST_EXIT=$?
elif [ -f pyproject.toml ] || [ -f setup.py ]; then
  python3 -m pytest tests/ -v 2>&1 | tee /tmp/regression-tests.txt
  TEST_EXIT=$?
elif ls tests/*.sh 2>/dev/null; then
  for t in tests/*.sh; do
    echo "--- Running $t ---"
    bash "$t" 2>&1
    echo "Exit: $?"
  done | tee /tmp/regression-tests.txt
  TEST_EXIT=$?
else
  echo "No test suite found"
  TEST_EXIT=1
fi

echo "Test suite exit code: $TEST_EXIT"
```

### 3. Compare Against Baseline

If a baseline test result exists:

```bash
# Compare test counts
BASELINE="/tmp/baseline-tests.txt"
CURRENT="/tmp/regression-tests.txt"

if [ -f "$BASELINE" ]; then
  echo "=== Baseline vs Current ==="
  BASELINE_PASS=$(grep -cE '(PASS|ok |passed|✓)' "$BASELINE" 2>/dev/null || echo 0)
  CURRENT_PASS=$(grep -cE '(PASS|ok |passed|✓)' "$CURRENT" 2>/dev/null || echo 0)
  BASELINE_FAIL=$(grep -cE '(FAIL|not ok|failed|✗)' "$BASELINE" 2>/dev/null || echo 0)
  CURRENT_FAIL=$(grep -cE '(FAIL|not ok|failed|✗)' "$CURRENT" 2>/dev/null || echo 0)

  echo "Passing tests: $BASELINE_PASS -> $CURRENT_PASS"
  echo "Failing tests: $BASELINE_FAIL -> $CURRENT_FAIL"

  if [ "$CURRENT_FAIL" -gt "$BASELINE_FAIL" ]; then
    echo "WARNING: New failures detected!"
  fi
  if [ "$CURRENT_PASS" -lt "$BASELINE_PASS" ]; then
    echo "WARNING: Fewer passing tests than baseline!"
  fi
else
  echo "No baseline found — recording current as baseline"
  cp "$CURRENT" "$BASELINE"
fi
```

### 4. Identify New Failures

For each failure that was NOT present in the baseline:

```bash
# Extract failing test names
grep -E '(FAIL|not ok|FAILED|ERROR)' /tmp/regression-tests.txt | while read line; do
  echo ""
  echo "=== New Failure ==="
  echo "Test: $line"
  echo ""

  # Try to find the related change
  TEST_FILE=$(echo "$line" | grep -oE '[a-zA-Z0-9_/.-]+\.(test|spec)\.[jt]s' | head -1)
  if [ -n "$TEST_FILE" ]; then
    echo "Checking if test file itself changed:"
    git diff --stat HEAD~3 -- "$TEST_FILE" 2>/dev/null || echo "  (no git info)"
  fi
done
```

### 5. Document Each Regression

For each new failure, produce:

```markdown
### Regression: [Test name]
- **Introduced by:** [commit hash or change description]
- **File:** [test file path]
- **Reproduction:** `[command to reproduce]`
- **Expected:** [what should happen]
- **Actual:** [what actually happens]
- **Root cause:** [brief analysis if known]
```

### 6. Test Related Functionality Manually

If the changed code has no automated tests, test manually:

```bash
# Identify what the changed code does
CHANGED_FILES=$(git diff --name-only HEAD~3 2>/dev/null)

for f in $CHANGED_FILES; do
  echo "=== Testing $f ==="
  case "$f" in
    *.sh)
      bash -n "$f" && echo "Syntax: OK" || echo "Syntax: FAIL"
      bash "$f" --help 2>&1 | head -5
      ;;
    *.js)
      node --check "$f" && echo "Syntax: OK" || echo "Syntax: FAIL"
      ;;
    *.py)
      python3 -m py_compile "$f" && echo "Syntax: OK" || echo "Syntax: FAIL"
      ;;
  esac
done
```

### 7. Record Results

```bash
RESULT_FILE="/home/shared/regression-$(date +%Y%m%d).md"

if [ "$TEST_EXIT" -eq 0 ] && [ "$CURRENT_FAIL" -le "${BASELINE_FAIL:-0}" ]; then
  cat > "$RESULT_FILE" <<EOF
# Regression Check: CLEAN

**Date:** $(date +%Y-%m-%d)
**Test suite exit code:** $TEST_EXIT
**Passing:** $CURRENT_PASS
**Failing:** $CURRENT_FAIL (same as or fewer than baseline)

No regressions detected. All existing tests continue to pass.
EOF
else
  cat > "$RESULT_FILE" <<EOF
# Regression Check: FAILURES FOUND

**Date:** $(date +%Y-%m-%d)
**Test suite exit code:** $TEST_EXIT
**Passing:** $CURRENT_PASS (baseline: ${BASELINE_PASS:-unknown})
**Failing:** $CURRENT_FAIL (baseline: ${BASELINE_FAIL:-unknown})

## New Failures

[document each regression using the template above]

## Recommendation
[fix / revert / investigate]
EOF
fi

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "regression-check" \
  --type "report" \
  --path "$RESULT_FILE" \
  --description "Regression check results"
```

## Quality Checklist

- [ ] All changed files identified
- [ ] Full test suite executed (not just changed tests)
- [ ] Results compared against baseline
- [ ] Every new failure documented with reproduction steps
- [ ] Root cause identified or investigation noted
- [ ] Manual testing done for code without automated tests
- [ ] Results recorded in shared workspace
