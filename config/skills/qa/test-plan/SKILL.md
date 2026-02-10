---
name: test-plan
description: Create a structured test plan with specific test cases and expected results
---

# Test Plan

## When to Use

Use this skill when tasked with writing a test plan, validating a feature, or when you need to systematically verify that a component works correctly.

## Output Template

```markdown
# Test Plan: [Feature/Component Name]

**Date:** YYYY-MM-DD
**Author:** [agent name]
**Target:** [file or component under test]
**Status:** Draft | Executing | Complete

## Scope
[What is being tested. What is explicitly NOT being tested.]

## Prerequisites
- [Dependency or setup step 1]
- [Dependency or setup step 2]

## Test Cases — Normal Operation

| ID | Description | Input | Expected Output | Status |
|----|-------------|-------|-----------------|--------|
| N1 | [typical use] | [specific input] | [specific output] | Pass/Fail/Blocked |
| N2 | ... | ... | ... | ... |

## Test Cases — Boundary Conditions

| ID | Description | Input | Expected Output | Status |
|----|-------------|-------|-----------------|--------|
| B1 | [edge case] | [specific input] | [specific output] | Pass/Fail/Blocked |
| B2 | ... | ... | ... | ... |

## Test Cases — Error Conditions

| ID | Description | Input | Expected Output | Status |
|----|-------------|-------|-----------------|--------|
| E1 | [invalid input] | [specific input] | [specific error] | Pass/Fail/Blocked |
| E2 | ... | ... | ... | ... |

## Results Summary
| Category | Total | Passed | Failed | Blocked |
|----------|-------|--------|--------|---------|
| Normal | N | N | N | N |
| Boundary | N | N | N | N |
| Error | N | N | N | N |
| **Total** | **N** | **N** | **N** | **N** |
```

## Procedure

### 1. Read the Specification

```bash
# Read the task or feature description
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'

# Read the source code to understand behavior
cat ~/workspace/src/target-module.js

# Read any existing tests
find ~/workspace/tests/ -name '*target*' -exec cat {} \;
```

### 2. Identify Normal Cases

These are the "happy path" scenarios — typical, expected usage:

```bash
# Example: testing a CLI tool
SCRIPT="~/workspace/scripts/tool.sh"

# N1: Basic valid input
bash "$SCRIPT" add --name "test-item" --type "task"
echo "Exit: $?"
# Expected: exit 0, item created

# N2: Multiple items
bash "$SCRIPT" add --name "item-1" --type "task"
bash "$SCRIPT" add --name "item-2" --type "task"
bash "$SCRIPT" list
echo "Exit: $?"
# Expected: exit 0, both items listed
```

### 3. Identify Boundary Conditions

Test the edges of valid input:

```bash
# B1: Empty string input
bash "$SCRIPT" add --name "" --type "task"
echo "Exit: $?"
# Expected: exit 1, validation error

# B2: Very long input
bash "$SCRIPT" add --name "$(python3 -c 'print("a"*10000)')" --type "task"
echo "Exit: $?"
# Expected: exit 1 or truncated gracefully

# B3: Special characters
bash "$SCRIPT" add --name 'test "with" <special> & chars' --type "task"
echo "Exit: $?"
# Expected: exit 0, characters properly escaped

# B4: Unicode
bash "$SCRIPT" add --name "test-unicode-cafe" --type "task"
echo "Exit: $?"
# Expected: exit 0, unicode preserved
```

### 4. Identify Error Conditions

Test invalid input and failure scenarios:

```bash
# E1: Missing required argument
bash "$SCRIPT" add 2>&1
echo "Exit: $?"
# Expected: exit 1, usage message

# E2: Invalid flag
bash "$SCRIPT" add --nonexistent "value" 2>&1
echo "Exit: $?"
# Expected: exit 1, error message

# E3: File not found
bash "$SCRIPT" get --id "nonexistent-id" 2>&1
echo "Exit: $?"
# Expected: exit 1, "not found" message

# E4: Permission denied (if applicable)
chmod 000 /tmp/test-file
bash "$SCRIPT" read --file /tmp/test-file 2>&1
echo "Exit: $?"
chmod 644 /tmp/test-file
# Expected: exit 1, permission error
```

### 5. Execute All Test Cases

Run each test case and record the actual result:

```bash
PASS=0
FAIL=0
BLOCKED=0

run_test() {
  local id="$1"
  local desc="$2"
  local cmd="$3"
  local expected_exit="$4"

  echo -n "Test $id: $desc ... "
  eval "$cmd" > /tmp/test-output-$id.txt 2>&1
  actual_exit=$?

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL + 1))
    echo "  Output: $(cat /tmp/test-output-$id.txt | head -5)"
  fi
}

run_test "N1" "Basic valid input" "bash $SCRIPT add --name test --type task" 0
run_test "E1" "Missing required arg" "bash $SCRIPT add" 1
# ... more tests ...

echo ""
echo "Results: $PASS passed, $FAIL failed, $BLOCKED blocked"
```

### 6. Record Test Plan and Results

```bash
TESTPLAN_FILE="/home/shared/testplan-$(date +%Y%m%d)-${COMPONENT}.md"

# Write the test plan with results filled in
# Use the template above, filling in actual Status column

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "testplan-${COMPONENT}" \
  --type "test-plan" \
  --path "$TESTPLAN_FILE" \
  --description "Test plan and results for $COMPONENT"
```

## Quality Checklist

- [ ] Every test case has a specific input (not "valid input" but the actual value)
- [ ] Every test case has a specific expected output (not "should work" but the exact result)
- [ ] Normal cases cover typical usage patterns
- [ ] Boundary cases test empty, large, special-character, and edge inputs
- [ ] Error cases test missing args, invalid args, not-found, and permission issues
- [ ] All test cases have been executed and Status column is filled
- [ ] Results summary table is accurate
- [ ] Failed tests have explanations or linked bug reports
