---
name: test-and-validate
description: Run tests, validate output, and verify correctness before marking work complete
---

# Test and Validate

## When to Use

Use this skill before marking any coding task as complete. Every deliverable must be validated.

## Procedure

### 1. Identify the Test Framework

```bash
cd ~/workspace
PROJECT_DIR=$(pwd)

# Node.js — check package.json for test script
if [ -f package.json ]; then
  echo "=== package.json test script ==="
  jq -r '.scripts.test // "none"' package.json
  echo "=== test framework ==="
  jq -r '.devDependencies // .dependencies | keys[]' package.json 2>/dev/null \
    | grep -E 'jest|mocha|vitest|tap|ava' || echo "Using node:test (built-in)"
fi

# Python — check for pytest/unittest
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ]; then
  echo "=== Python test framework ==="
  pip list 2>/dev/null | grep -iE 'pytest|unittest2|nose' || echo "Using unittest (built-in)"
fi

# Look for test directories
find . -type d -name 'test*' -maxdepth 3 2>/dev/null
find . -type f -name '*test*' -o -name '*spec*' | head -20
```

### 2. Run the Test Suite

**Node.js:**
```bash
npm test 2>&1 | tee /tmp/test-output.txt
TEST_EXIT=$?
echo "Exit code: $TEST_EXIT"
```

**Python:**
```bash
python3 -m pytest tests/ -v 2>&1 | tee /tmp/test-output.txt
TEST_EXIT=$?
echo "Exit code: $TEST_EXIT"
```

**Shell scripts:**
```bash
# Verify script has valid syntax
bash -n script.sh
echo "Syntax check exit code: $?"

# Verify --help works
bash script.sh --help
echo "Help exit code: $?"

# Run with sample input
echo '{"test": true}' | bash script.sh
echo "Sample run exit code: $?"
```

### 3. Fix Failures

If tests fail:
1. Read the failure output carefully — identify the specific assertion or error
2. Fix the code (not the test, unless the test is wrong)
3. Re-run the failing test in isolation first:

```bash
# Node.js — run single test
npx jest --testPathPattern="failing-test" 2>&1
# or
node --test tests/failing-test.js 2>&1

# Python — run single test
python3 -m pytest tests/test_module.py::test_function -v 2>&1
```

4. Then re-run the full suite to confirm no regressions

### 4. Manual Validation for Scripts and CLIs

```bash
SCRIPT="path/to/script.sh"

# Check help/usage
bash "$SCRIPT" --help
echo "--- Exit code: $? (expect 0) ---"

# Test with valid input
bash "$SCRIPT" valid-arg
echo "--- Exit code: $? (expect 0) ---"

# Test with invalid input
bash "$SCRIPT" --nonexistent 2>&1
echo "--- Exit code: $? (expect non-zero) ---"

# Test with empty input
echo "" | bash "$SCRIPT"
echo "--- Exit code: $? (expect non-zero or graceful handling) ---"
```

### 5. Verify No Syntax Errors Across Changed Files

```bash
# Find recently changed files
CHANGED_FILES=$(find . -name '*.js' -o -name '*.py' -o -name '*.sh' -o -name '*.ts' \
  | xargs ls -t 2>/dev/null | head -20)

for f in $CHANGED_FILES; do
  case "$f" in
    *.js)  node --check "$f" && echo "OK: $f" || echo "FAIL: $f" ;;
    *.py)  python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f" ;;
    *.sh)  bash -n "$f" && echo "OK: $f" || echo "FAIL: $f" ;;
    *.ts)  npx tsc --noEmit "$f" 2>&1 && echo "OK: $f" || echo "FAIL: $f" ;;
  esac
done
```

### 6. Record Test Results in Task Completion

When updating your task status, include test results:

```bash
bash /home/shared/scripts/task.sh update "$TASK_ID" \
  --status completed \
  --result "All tests passing. 12/12 tests passed. Manual validation of CLI flags confirmed."
```

## Validation Checklist

- [ ] Test suite runs and all tests pass (exit code 0)
- [ ] No syntax errors in any changed files
- [ ] Scripts handle --help, valid input, invalid input, and empty input
- [ ] Edge cases tested (empty strings, large inputs, special characters)
- [ ] Exit codes are correct (0 for success, non-zero for errors)
- [ ] No leftover debug output (console.log, print statements used for debugging)
- [ ] Test results recorded in task completion notes
