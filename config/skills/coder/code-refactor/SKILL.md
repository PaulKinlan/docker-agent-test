---
name: code-refactor
description: Refactor code for improved quality without changing behavior
---

# Code Refactor

## When to Use

Use this skill when the task calls for improving code quality, readability, or maintainability without changing external behavior.

## Procedure

### 1. Read and Understand Existing Code

Before changing anything, understand what the code does:

```bash
cd ~/workspace

# Read the target file(s) thoroughly
cat src/target-module.js

# Understand how it is used — find all callers
rg "require.*target-module" --type js
rg "import.*target-module" --type js
rg "target-module" --type js -l
```

### 2. Run Existing Tests for a Baseline

```bash
# Run tests and save output as baseline
npm test 2>&1 | tee /tmp/baseline-tests.txt
BASELINE_EXIT=$?
echo "Baseline exit code: $BASELINE_EXIT"

# Count passing tests
grep -cE '(PASS|ok |passed|✓)' /tmp/baseline-tests.txt || true
```

If there are no tests, note this and be extra careful -- consider writing tests first.

### 3. Identify Refactoring Targets

Look for these specific code smells:

```bash
TARGET="src/"

# Long functions (>40 lines)
awk '/^(function|const.*=>|def |async function)/{name=$0; start=NR} NR-start==40{print FILENAME":"start": Long function: "name}' $TARGET*.js $TARGET*.py 2>/dev/null

# Duplicated code blocks (approximate)
awk 'NR>1{if($0==prev && length($0)>20) print FILENAME":"NR": Duplicate line: "$0; prev=$0}' $TARGET*.js $TARGET*.py 2>/dev/null

# Deep nesting (>4 levels)
rg "^(\s{16,}|\t{4,})\S" $TARGET --line-number | head -20

# Unclear variable names (single letters, except loop vars)
rg "\b(let|const|var)\s+[a-z]\s*=" $TARGET --type js | grep -v "for\s*(" | head -20

# Missing error handling
rg "\.catch\(\s*\(\s*\)\s*=>" $TARGET --type js  # empty catch
rg "except:\s*$" $TARGET --type py                # bare except
rg "catch\s*\(.*\)\s*\{\s*\}" $TARGET --type js   # empty catch block

# Console.log used as error handling
rg "catch.*console\.(log|error)" $TARGET --type js | head -10
```

### 4. Refactor One Thing at a Time

Work in small increments. After each change, re-run tests:

**Step A — Extract function:**
```bash
# Make the change
# ... edit the file ...

# Verify tests still pass
npm test 2>&1
echo "Exit code after extract: $?"
```

**Step B — Rename for clarity:**
```bash
# Rename variable/function across all files
OLD_NAME="processData"
NEW_NAME="parseAndValidateInput"

rg "$OLD_NAME" -l | while read f; do
  sed -i "s/$OLD_NAME/$NEW_NAME/g" "$f"
done

# Verify tests still pass
npm test 2>&1
echo "Exit code after rename: $?"
```

**Step C — Reduce nesting:**
```bash
# Apply early returns / guard clauses
# ... edit the file ...

# Verify tests still pass
npm test 2>&1
echo "Exit code after de-nesting: $?"
```

**Step D — Remove duplication:**
```bash
# Extract common code into shared function
# ... edit the file ...

# Verify tests still pass
npm test 2>&1
echo "Exit code after dedup: $?"
```

### 5. Do NOT Change Behavior

Refactoring rules:
- Inputs and outputs must remain identical
- Error messages and exit codes must remain identical
- Side effects (file writes, network calls) must remain identical
- If you find a bug, document it separately -- do NOT fix it in the refactor

```bash
# If you find a bug, log it
cat >> ~/notes.md <<EOF
## Bug Found During Refactor (task $TASK_ID)
- File: src/module.js:42
- Description: Off-by-one in loop boundary
- Impact: Last item in array is skipped
- Note: Not fixed — behavior preservation required during refactor
EOF
```

### 6. Final Validation

```bash
# Run full test suite
npm test 2>&1 | tee /tmp/refactor-tests.txt
REFACTOR_EXIT=$?

# Compare with baseline
echo "Baseline exit: $BASELINE_EXIT, Refactor exit: $REFACTOR_EXIT"
diff <(grep -E '(PASS|FAIL|ok|not ok)' /tmp/baseline-tests.txt | sort) \
     <(grep -E '(PASS|FAIL|ok|not ok)' /tmp/refactor-tests.txt | sort)

# Check no functional changes leaked in
git diff --stat
```

### 7. Commit with Refactor-Specific Message

```bash
git add -A
git commit -m "Refactor: extract validation into helper functions

- Extract validateInput() from processRequest (was 80 lines, now 25)
- Rename 'x' to 'requestPayload' for clarity
- Remove duplicated error formatting (now in formatError())
- No behavior changes — all existing tests pass unchanged"
```

## Refactoring Targets Checklist

- [ ] Duplication: extracted into shared functions
- [ ] Long functions: broken into focused helpers (each <30 lines)
- [ ] Deep nesting: replaced with early returns / guard clauses
- [ ] Unclear names: renamed to describe purpose
- [ ] Missing error handling: added proper try/catch with meaningful messages
- [ ] Dead code: removed (not commented out)
- [ ] All tests pass with identical results to baseline
- [ ] Bugs found are documented separately, not fixed in this changeset
