---
name: decision-record
description: Write Architecture Decision Records (ADRs) documenting decisions with context, options, rationale, and consequences
---

# Decision Record (ADR)

## When to Use

Use this skill when a significant decision needs to be documented -- one where the reasoning matters as much as the outcome. ADRs are not limited to software architecture; they apply to any domain where future readers will need to understand why a particular choice was made: organizational structure, process design, vendor selection, policy changes, tooling choices, or strategic direction. If someone might later ask "why did we do it this way?", write an ADR.

## Output Template

```markdown
# ADR-[NNN]: [Decision Title]

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-[NNN]
**Date:** [YYYY-MM-DD]
**Author:** [agent name]
**Deciders:** [who was involved in making this decision]

## Context

[Describe the situation that requires a decision. Include:
- What forces are at play (technical, organizational, time, cost)
- What constraints exist
- What prompted this decision now (why not earlier, why not later)
- Link to related prior decisions if any]

## Decision

[State the decision clearly in one or two sentences. Use active voice:
"We will [action]" or "We choose [option] because [primary reason]."]

## Consequences

### Positive
- [Benefit 1]
- [Benefit 2]

### Negative
- [Tradeoff 1 -- and how we will mitigate it]
- [Tradeoff 2]

### Neutral
- [Side effect that is neither clearly good nor bad]

## Alternatives Considered

### Alternative 1: [Name]
- **Description:** [what this option entails]
- **Pros:** [advantages]
- **Cons:** [disadvantages]
- **Rejected because:** [specific reason this was not chosen]

### Alternative 2: [Name]
- **Description:** [what this option entails]
- **Pros:** [advantages]
- **Cons:** [disadvantages]
- **Rejected because:** [specific reason this was not chosen]

## References
- [Related documents, prior decisions, external resources]
```

## Procedure

### 1. Identify the Decision

Read the task and extract the core decision to be made:

```bash
TASK_ID="$1"
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'
```

Write down in one sentence: "The decision is whether to [X] or [Y] given [context]."

If the decision is unclear or too broad, break it into smaller decisions, each getting its own ADR.

### 2. Find the Next ADR Number

```bash
DECISIONS_DIR="/home/shared/decisions"
mkdir -p "$DECISIONS_DIR"

# Find the highest existing ADR number
LAST_NUM=$(ls "$DECISIONS_DIR"/ADR-*.md 2>/dev/null \
  | grep -oE 'ADR-[0-9]+' \
  | grep -oE '[0-9]+' \
  | sort -n \
  | tail -1)

NEXT_NUM=$(printf '%03d' $(( ${LAST_NUM:-0} + 1 )))
echo "Next ADR number: $NEXT_NUM"
```

### 3. Gather Context

Collect information that bears on the decision:

```bash
# Read any prior decisions that relate to this one
if ls "$DECISIONS_DIR"/ADR-*.md >/dev/null 2>&1; then
  echo "=== Existing decisions ==="
  for adr in "$DECISIONS_DIR"/ADR-*.md; do
    TITLE=$(head -1 "$adr" | sed 's/^# //')
    STATUS=$(grep -m1 '^**Status:**' "$adr" | sed 's/.*: //' | tr -d '*')
    echo "  $(basename "$adr"): $TITLE [$STATUS]"
  done
fi

# Search for related context in shared files
DECISION_TOPIC="${2:-topic}"
echo ""
echo "=== Related files ==="
rg -l "$DECISION_TOPIC" /home/shared/ 2>/dev/null | head -15

# Read design documents that might constrain this decision
echo ""
echo "=== Design documents ==="
find /home/shared/ -name 'design-*' -type f 2>/dev/null | while read f; do
  echo "  $f: $(head -1 "$f")"
done

# Read research that informs this decision
echo ""
echo "=== Research ==="
find /home/shared/ -name 'research-*' -type f 2>/dev/null | while read f; do
  echo "  $f: $(head -1 "$f")"
done
```

### 4. Enumerate Options

List every viable option. For each option, document what it entails and evaluate it against the same criteria:

```bash
# Create a structured comparison
COMPARISON_FILE=$(mktemp /tmp/adr-comparison-XXXXXX.md)

cat > "$COMPARISON_FILE" <<'EOF'
## Option Comparison

| Criterion | Weight | Option A | Option B | Option C |
|-----------|--------|----------|----------|----------|
| [Criterion 1] | High | [score/note] | [score/note] | [score/note] |
| [Criterion 2] | Medium | [score/note] | [score/note] | [score/note] |
| [Criterion 3] | Low | [score/note] | [score/note] | [score/note] |

Evaluation criteria should be specific to the decision domain:
- For process decisions: efficiency, adoption difficulty, reversibility, cost
- For tool decisions: capability, learning curve, maintenance burden, community
- For organizational decisions: clarity, scalability, transition cost, cultural fit
- For technical decisions: performance, complexity, reliability, extensibility
EOF

cat "$COMPARISON_FILE"
```

A good ADR considers at least two alternatives. If there is only one option, the ADR should explain why no alternatives exist.

### 5. Evaluate Consequences

For the chosen option, think through three categories of consequences:

```bash
# Structure the consequences analysis
cat <<'EOF'
Consequences framework:

POSITIVE (benefits we gain):
- What does this make easier?
- What risk does this reduce?
- What capability does this enable?

NEGATIVE (costs we accept):
- What does this make harder?
- What risk does this introduce?
- What option does this foreclose?
- How will we mitigate each negative consequence?

NEUTRAL (things that change but are neither good nor bad):
- What shifts without clear valence?
- What existing patterns change?
EOF
```

### 6. Check for Conflicts with Prior Decisions

```bash
# Look for decisions that this one might contradict or supersede
if ls "$DECISIONS_DIR"/ADR-*.md >/dev/null 2>&1; then
  echo "=== Checking for conflicts ==="
  for adr in "$DECISIONS_DIR"/ADR-*.md; do
    STATUS=$(grep -m1 '^**Status:**' "$adr" | sed 's/.*\*\* //' | tr -d '*')
    if [ "$STATUS" = "Accepted" ]; then
      # Check if the topic overlaps
      OVERLAP=$(rg -c "$DECISION_TOPIC" "$adr" 2>/dev/null)
      if [ "${OVERLAP:-0}" -gt 0 ]; then
        echo "POTENTIAL CONFLICT: $(basename "$adr") mentions $DECISION_TOPIC ($OVERLAP times)"
        echo "  Review this ADR to determine if the new decision supersedes it."
      fi
    fi
  done
fi
```

If this decision supersedes a prior one, update the prior ADR's status:

```bash
# Example: mark a prior ADR as superseded
PRIOR_ADR="$DECISIONS_DIR/ADR-005.md"  # adjust as needed
if [ -f "$PRIOR_ADR" ]; then
  sed -i "s/^\\*\\*Status:\\*\\* Accepted/**Status:** Superseded by ADR-${NEXT_NUM}/" "$PRIOR_ADR"
  echo "Updated $(basename "$PRIOR_ADR") status to Superseded."
fi
```

### 7. Write the ADR

```bash
DECISION_TITLE="${3:-Untitled Decision}"
ADR_FILE="$DECISIONS_DIR/ADR-${NEXT_NUM}-$(echo "$DECISION_TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-').md"
TIMESTAMP=$(date +%Y-%m-%d)
AGENT_NAME=$(whoami)

cat > "$ADR_FILE" <<EOF
# ADR-${NEXT_NUM}: ${DECISION_TITLE}

**Status:** Proposed
**Date:** ${TIMESTAMP}
**Author:** ${AGENT_NAME}
**Deciders:** [FILL IN: who was involved]

## Context

[FILL IN: Describe the forces, constraints, and trigger for this decision.
Reference prior ADRs if relevant: see ADR-NNN.]

## Decision

[FILL IN: "We will [action]" -- state the decision in one or two clear sentences.]

## Consequences

### Positive
- [FILL IN]

### Negative
- [FILL IN -- include mitigation for each]

### Neutral
- [FILL IN]

## Alternatives Considered

### Alternative 1: [FILL IN name]
- **Description:** [what this option entails]
- **Pros:** [advantages]
- **Cons:** [disadvantages]
- **Rejected because:** [specific reason]

### Alternative 2: [FILL IN name]
- **Description:** [what this option entails]
- **Pros:** [advantages]
- **Cons:** [disadvantages]
- **Rejected because:** [specific reason]

## References
- [FILL IN: related documents, prior ADRs, external resources]
EOF

echo "ADR written to: $ADR_FILE"
```

### 8. Validate the ADR

Before registering, check that the ADR is complete and internally consistent:

```bash
# Validate required sections are present and non-empty
REQUIRED_SECTIONS=("Context" "Decision" "Consequences" "Alternatives Considered")
for section in "${REQUIRED_SECTIONS[@]}"; do
  if grep -q "^## $section" "$ADR_FILE"; then
    # Check the section has content beyond just the heading
    CONTENT=$(sed -n "/^## $section/,/^## /p" "$ADR_FILE" | grep -v '^##' | grep -v '^$' | wc -l)
    if [ "$CONTENT" -gt 0 ]; then
      echo "OK: $section has content ($CONTENT lines)"
    else
      echo "WARNING: $section is empty"
    fi
  else
    echo "MISSING: $section section not found"
  fi
done

# Check that at least 2 alternatives are documented
ALT_COUNT=$(grep -c '^### Alternative' "$ADR_FILE")
if [ "$ALT_COUNT" -ge 2 ]; then
  echo "OK: $ALT_COUNT alternatives documented"
else
  echo "WARNING: Only $ALT_COUNT alternative(s) -- consider adding more"
fi

# Check that negative consequences include mitigation
NEG_SECTION=$(sed -n '/^### Negative/,/^###/p' "$ADR_FILE" | grep -v '^###')
if echo "$NEG_SECTION" | grep -qi 'mitigat\|address\|accept\|manage\|reduce'; then
  echo "OK: Negative consequences mention mitigation"
else
  echo "WARNING: Negative consequences should include mitigation strategies"
fi

# Check for FILL IN placeholders that need to be completed
PLACEHOLDERS=$(grep -c 'FILL IN' "$ADR_FILE")
if [ "$PLACEHOLDERS" -gt 0 ]; then
  echo "ACTION NEEDED: $PLACEHOLDERS placeholder(s) remain -- complete these before finalizing"
fi
```

### 9. Register and Notify

```bash
# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "ADR-${NEXT_NUM}" \
  --type "decision-record" \
  --path "$ADR_FILE" \
  --description "ADR-${NEXT_NUM}: ${DECISION_TITLE}"

echo "ADR registered as artifact."

# Notify relevant parties
bash /home/shared/scripts/send-mail.sh manager <<EOF
New decision record: ADR-${NEXT_NUM}: ${DECISION_TITLE}

Status: Proposed
Author: ${AGENT_NAME}
Date: ${TIMESTAMP}

Location: ${ADR_FILE}

Please review and update status to Accepted if approved.
EOF

echo "Manager notified for review."
```

### 10. Update Task

```bash
bash /home/shared/scripts/task.sh update "$TASK_ID" \
  --status completed \
  --result "ADR-${NEXT_NUM} written: ${DECISION_TITLE}. See ${ADR_FILE}"
```

## Quality Checklist

- [ ] Decision is stated clearly in one or two sentences using active voice
- [ ] Context explains the forces, constraints, and why this decision is needed now
- [ ] At least two alternatives are considered with honest pros and cons
- [ ] Each rejected alternative has a specific reason for rejection (not just "worse")
- [ ] Positive consequences describe concrete benefits, not vague improvements
- [ ] Negative consequences are acknowledged with mitigation strategies
- [ ] Neutral consequences capture changes that are neither clearly good nor bad
- [ ] Prior related decisions were checked for conflicts or supersession
- [ ] No FILL IN placeholders remain in the final version
- [ ] The ADR is numbered sequentially and stored in /home/shared/decisions/
- [ ] The ADR is registered as an artifact
- [ ] Relevant stakeholders are notified for review
