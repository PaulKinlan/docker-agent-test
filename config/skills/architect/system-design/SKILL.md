---
name: system-design
description: Produce a technical design document for a system or component
---

# System Design

## When to Use

Use this skill when tasked with designing a new system, component, or significant feature. The output is a design document that others (coders, reviewers) will use as a blueprint.

## Output Template

```markdown
# Design: [System/Component Name]

**Author:** [agent name]
**Date:** [YYYY-MM-DD]
**Status:** Draft | Review | Approved

## Problem Statement
[What problem are we solving? Who has this problem? What happens if we don't solve it?]

## Constraints
- [Hard constraint 1 — e.g., must run in container with no internet]
- [Hard constraint 2 — e.g., must complete in under 30 seconds]
- [Soft constraint — e.g., prefer existing dependencies over new ones]

## Proposed Solution

### Components
| Component | Responsibility | Interface |
|-----------|---------------|-----------|
| [name] | [what it does] | [how others interact with it] |

### Data Flow
```
[Input] --> [Component A] --> [Component B] --> [Output]
                |                    ^
                v                    |
          [Storage/State] ----------+
```

### API / Interface

```
[function/command signature]
  Input: [format and constraints]
  Output: [format and constraints]
  Errors: [error conditions and responses]
```

## Alternatives Considered

| Alternative | Pros | Cons | Why Rejected |
|-------------|------|------|--------------|
| [Option A] | [advantages] | [disadvantages] | [specific reason] |
| [Option B] | [advantages] | [disadvantages] | [specific reason] |

## Open Questions
1. [Decision that needs input from others]
2. [Uncertainty that affects the design]

## Implementation Plan
1. [First deliverable — what, who, estimate]
2. [Second deliverable]
3. [Integration and testing]
```

## Procedure

### 1. Read Context and Requirements

```bash
# Read the task
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'

# Read any referenced documents
find /home/shared/ -name '*.md' -newer /tmp/session-start 2>/dev/null | while read f; do
  echo "=== $f ==="
  head -20 "$f"
done

# Read existing codebase for context
tree ~/workspace/ -L 2 --dirsfirst 2>/dev/null || find ~/workspace/ -maxdepth 2 -type f | head -30
```

### 2. Identify Constraints

Check the environment for hard constraints:

```bash
# What is available in the container?
which node python3 bash jq curl 2>/dev/null
node --version 2>/dev/null
python3 --version 2>/dev/null

# What services are running?
systemctl list-units --type=service --state=running 2>/dev/null | head -20

# What shared infrastructure exists?
ls /home/shared/scripts/ 2>/dev/null
ls /home/shared/ 2>/dev/null

# Memory/disk constraints
free -h 2>/dev/null || vm_stat 2>/dev/null
df -h / 2>/dev/null
```

### 3. Draft the Design

Write the design document following the template above. For each component:
- Define its single responsibility
- Define its interface (inputs, outputs, errors)
- Define how it communicates with other components

### 4. Validate the Design

Before writing the final document, check:

```bash
# Can we implement this with available tools?
for cmd in $(echo "jq node python3 bash curl"); do
  which $cmd >/dev/null 2>&1 && echo "Available: $cmd" || echo "MISSING: $cmd"
done

# Do the proposed file paths conflict with existing files?
for path in $(echo "/home/shared/proposed-file.json /home/shared/proposed-dir/"); do
  [ -e "$path" ] && echo "CONFLICT: $path already exists" || echo "OK: $path is free"
done
```

### 5. Write to Shared Workspace

```bash
DESIGN_FILE="/home/shared/design-$(date +%Y%m%d)-${COMPONENT_NAME}.md"

cat > "$DESIGN_FILE" <<'DESIGN'
# Design: [Component Name]
...
DESIGN

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "design-${COMPONENT_NAME}" \
  --type "design" \
  --path "$DESIGN_FILE" \
  --description "Technical design for $COMPONENT_NAME"

echo "Design document written to: $DESIGN_FILE"
```

## Quality Checklist

- [ ] Problem statement is specific and testable (you can tell if it is solved)
- [ ] All hard constraints are listed
- [ ] Components have single responsibilities
- [ ] Interfaces are fully specified (inputs, outputs, errors)
- [ ] Data flow is explicit (no hidden state or side channels)
- [ ] At least 2 alternatives were considered with honest pros/cons
- [ ] Open questions are specific enough to be answerable
- [ ] Implementation plan has concrete deliverables, not vague phases
