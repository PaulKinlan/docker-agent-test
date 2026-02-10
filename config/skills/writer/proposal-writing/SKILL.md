---
name: proposal-writing
description: Write business or technical proposals that propose a course of action with rationale, costs, and implementation plan
---

# Proposal Writing

## When to Use

Use this skill when tasked with writing a proposal, project pitch, RFC, business case, or any persuasive document that recommends a course of action. This is for knowledge work proposals -- recommending strategies, initiatives, process changes, or investments -- not for writing code documentation or API specs.

Common scenarios:
- Proposing a new initiative, project, or program
- Writing an RFC (Request for Comments) for a technical or process change
- Building a business case for investment or resource allocation
- Pitching an approach to solve an identified problem
- Recommending a vendor, tool, or strategy with justification

## Principles

1. **Lead with the problem, not the solution.** The reader must feel the pain before they will accept the cure. Spend proportionate effort defining the problem clearly.
2. **Quantify wherever possible.** "This will save approximately 40 hours per month" is persuasive. "This will save time" is not.
3. **Acknowledge costs and risks honestly.** A proposal that ignores downsides loses credibility. Address them head-on and show you have mitigation plans.
4. **Write for the decision-maker.** The first page should contain everything they need to say yes or no. Details come after.
5. **One proposal, one recommendation.** If you have multiple options, make a clear recommendation. Do not present a menu and ask the reader to choose.

## Output Template

```markdown
# Proposal: [Title]

**Date:** YYYY-MM-DD
**Author:** [agent name]
**Status:** Draft | Under Review | Approved | Rejected
**Decision Required By:** [date or milestone]

## Problem Statement

### Current Situation
[What is happening now. Be specific and factual.]

### Impact
[Why this matters. Quantify: cost, time lost, risk exposure, missed opportunity.]
| Impact Area | Metric | Current Value | Target Value |
|-------------|--------|---------------|--------------|
| [area] | [metric] | [current] | [desired] |

### Root Cause
[Why the current situation exists. What underlying factors drive it.]

## Proposed Solution

### Overview
[2-3 sentence summary of what is proposed]

### How It Works
[Detailed description of the proposed approach. Break into numbered steps or phases if complex.]

### Why This Approach
[Rationale for choosing this approach over alternatives. Reference specific criteria.]

## Benefits

| Benefit | Description | Estimated Value | Timeline to Realize |
|---------|-------------|-----------------|---------------------|
| [benefit 1] | [description] | [quantified] | [when] |
| [benefit 2] | [description] | [quantified] | [when] |

## Costs and Resources

| Item | Cost | Type | Notes |
|------|------|------|-------|
| [item 1] | [amount] | [one-time/recurring] | [details] |
| [item 2] | [amount] | [one-time/recurring] | [details] |
| **Total** | **[amount]** | | |

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| [risk 1] | [H/M/L] | [H/M/L] | [what we will do about it] |
| [risk 2] | [H/M/L] | [H/M/L] | [what we will do about it] |

## Alternatives Considered

| Alternative | Pros | Cons | Why Not Chosen |
|------------|------|------|----------------|
| [option A] | [pros] | [cons] | [reason] |
| Do nothing | [pros] | [cons] | [reason] |

## Implementation Plan

### Phase 1: [Name] (Weeks 1-N)
- [ ] [Deliverable 1]
- [ ] [Deliverable 2]

### Phase 2: [Name] (Weeks N-M)
- [ ] [Deliverable 3]
- [ ] [Deliverable 4]

### Timeline

| Phase | Start | End | Key Milestone | Owner |
|-------|-------|-----|---------------|-------|
| Phase 1 | [date] | [date] | [milestone] | [who] |
| Phase 2 | [date] | [date] | [milestone] | [who] |

## Success Criteria

| Criterion | Measurement | Target | Evaluation Date |
|-----------|-------------|--------|-----------------|
| [criterion] | [how measured] | [target value] | [when to check] |

## Decision Requested

[Exactly what you are asking the reader to approve, fund, or authorize. Be specific.]
```

## Procedure

### 1. Gather Background Materials

```bash
TASK_ID="$1"
TOPIC="$2"

# Read the task description
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'

# Find all related documents in workspace
echo "=== Related Documents ==="
rg -l -i "$TOPIC" /home/shared/ ~/workspace/ 2>/dev/null \
  | grep -E '\.(md|txt|csv|json|yaml)$' | head -20

# Check for prior research or analysis that informs this proposal
echo ""
echo "=== Prior Research ==="
find /home/shared/ -name '*research*' -o -name '*analysis*' -o -name '*review*' \
  | grep -i "$TOPIC" 2>/dev/null

# Check for existing proposals on related topics
echo ""
echo "=== Existing Proposals ==="
find /home/shared/ ~/workspace/ -name '*proposal*' -o -name '*rfc*' -o -name '*pitch*' \
  2>/dev/null | head -10

# Read relevant artifacts
echo ""
echo "=== Registered Artifacts ==="
bash /home/shared/scripts/artifact.sh list 2>/dev/null \
  | jq -r '.[] | select(.name | test("'"$TOPIC"'"; "i")) | "\(.name) — \(.path)"' 2>/dev/null
```

### 2. Define the Problem

This is the most critical step. A poorly defined problem produces a weak proposal.

```bash
# Create a problem definition worksheet
WORK_DIR="/tmp/proposal-${TOPIC}"
mkdir -p "$WORK_DIR"

cat > "$WORK_DIR/problem-definition.md" <<'EOF'
## Problem Definition Worksheet

### What is happening?
[Observable facts, not interpretations]

### Who is affected?
[Specific stakeholders or teams]

### What is the measurable impact?
[Numbers: cost, time, frequency, error rate]

### How long has this been happening?
[Duration and trend: getting worse, stable, improving?]

### What has already been tried?
[Prior attempts and why they did not fully succeed]

### What will happen if we do nothing?
[Projected impact of inaction over 3, 6, 12 months]
EOF
```

### 3. Research and Quantify the Impact

```bash
# Pull data from available sources to quantify the problem
echo "=== Quantifying Impact ==="

# Search for metrics, numbers, or data related to the problem
rg -n '\b\d+\.?\d*\s*(%|percent|hours|days|dollars|\$|cost|spent|lost|error|fail)' \
  /home/shared/ ~/workspace/ 2>/dev/null | head -20

# Check for any data files with relevant metrics
find /home/shared/ -name '*.csv' -o -name '*.json' \
  | xargs grep -li "$TOPIC" 2>/dev/null

# Look at task history for patterns
bash /home/shared/scripts/task.sh list 2>/dev/null \
  | jq '[.[] | select(.description | test("'"$TOPIC"'"; "i"))] | length' 2>/dev/null
```

### 4. Develop the Proposed Solution

```bash
# Outline the solution — ensure each element is concrete
cat > "$WORK_DIR/solution-outline.md" <<'EOF'
## Solution Outline

### What will change?
1. [Concrete change 1]
2. [Concrete change 2]
3. [Concrete change 3]

### What stays the same?
- [Unchanged element — important for managing scope expectations]

### What resources are needed?
- People: [who and how much of their time]
- Tools: [what tools or systems]
- Budget: [dollar amount or effort estimate]
- Time: [duration]

### How will we know it worked?
- [Success metric 1 with target value]
- [Success metric 2 with target value]
EOF
```

### 5. Assess Costs, Risks, and Alternatives

```bash
# Build a cost estimate
python3 <<'PYEOF'
import json

costs = [
    {"item": "Example item 1", "cost": 0, "type": "one-time", "notes": ""},
    {"item": "Example item 2", "cost": 0, "type": "recurring/month", "notes": ""},
]

total_onetime = sum(c["cost"] for c in costs if c["type"] == "one-time")
total_recurring = sum(c["cost"] for c in costs if "recurring" in c["type"])

print(f"One-time costs:  ${total_onetime:,.0f}")
print(f"Recurring costs: ${total_recurring:,.0f}/month")
print(f"First-year total: ${total_onetime + total_recurring * 12:,.0f}")

# Output as table
print("\n| Item | Cost | Type | Notes |")
print("|------|------|------|-------|")
for c in costs:
    print(f"| {c['item']} | ${c['cost']:,.0f} | {c['type']} | {c['notes']} |")
PYEOF
```

For risks:

```bash
# Build a risk register
cat > "$WORK_DIR/risks.md" <<'EOF'
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| [What could go wrong] | [H/M/L] | [H/M/L] | [Specific action to reduce] |

Scoring guide:
- H likelihood: >50% chance of occurring
- M likelihood: 10-50% chance
- L likelihood: <10% chance
- H impact: blocks the initiative or causes significant damage
- M impact: delays or degrades the initiative
- L impact: minor inconvenience, easily absorbed
EOF
```

### 6. Build the Implementation Timeline

```bash
# Create a phased implementation plan
cat > "$WORK_DIR/timeline.md" <<'EOF'
| Phase | Duration | Deliverables | Dependencies | Owner |
|-------|----------|-------------|-------------|-------|
| 1: [Name] | [N weeks] | [what is delivered] | [what must happen first] | [who] |
| 2: [Name] | [N weeks] | [what is delivered] | [Phase 1 complete] | [who] |
| 3: [Name] | [N weeks] | [what is delivered] | [Phase 2 complete] | [who] |

Key milestones:
- Week N: [milestone — a decision point or deliverable]
- Week M: [milestone]
EOF
```

### 7. Write the Proposal

```bash
PROPOSAL_FILE="/home/shared/proposal-$(date +%Y%m%d)-${TOPIC}.md"

# Assemble the proposal from the working materials
# Read each working file and integrate into the template
cat "$WORK_DIR/problem-definition.md"
cat "$WORK_DIR/solution-outline.md"
cat "$WORK_DIR/risks.md"
cat "$WORK_DIR/timeline.md"

# Write the final proposal (use the Output Template above as structure)
cat > "$PROPOSAL_FILE" <<'PROPOSAL'
# Proposal: [Title]

**Date:** YYYY-MM-DD
**Author:** [agent name]
**Status:** Draft
**Decision Required By:** [date]

## Problem Statement
...

## Proposed Solution
...

## Benefits
...

## Costs and Resources
...

## Risks and Mitigations
...

## Alternatives Considered
...

## Implementation Plan
...

## Success Criteria
...

## Decision Requested
[Exactly what approval or authorization is being sought]
PROPOSAL

echo "Proposal written to: $PROPOSAL_FILE"
```

### 8. Self-Review Before Submission

Run these checks on your draft:

```bash
PROPOSAL_FILE="/home/shared/proposal-$(date +%Y%m%d)-${TOPIC}.md"

echo "=== Proposal Quality Checks ==="

# Check: Does the problem section have numbers?
echo "--- Quantified impact ---"
rg '\d+' "$PROPOSAL_FILE" | head -10
QUANT_COUNT=$(rg -c '\b\d+\.?\d*\s*(%|hours|days|\$|cost)' "$PROPOSAL_FILE" 2>/dev/null || echo 0)
echo "Quantified claims found: $QUANT_COUNT"
[ "$QUANT_COUNT" -lt 3 ] && echo "WARNING: Proposal needs more quantified evidence"

# Check: Are all required sections present?
echo ""
echo "--- Required sections ---"
for section in "Problem Statement" "Proposed Solution" "Benefits" "Costs" "Risks" "Alternatives" "Implementation" "Success Criteria" "Decision Requested"; do
  if rg -q "$section" "$PROPOSAL_FILE" 2>/dev/null; then
    echo "  OK: $section"
  else
    echo "  MISSING: $section"
  fi
done

# Check: Is the "do nothing" alternative addressed?
echo ""
echo "--- Do-nothing alternative ---"
if rg -qi "do nothing\|status quo\|no action\|inaction" "$PROPOSAL_FILE" 2>/dev/null; then
  echo "  OK: Do-nothing scenario addressed"
else
  echo "  WARNING: Missing do-nothing/status quo alternative"
fi

# Check: Word count (proposals should be thorough but not bloated)
echo ""
echo "--- Length ---"
WC=$(wc -w < "$PROPOSAL_FILE")
echo "  Word count: $WC"
[ "$WC" -lt 300 ] && echo "  WARNING: Proposal may be too thin (< 300 words)"
[ "$WC" -gt 3000 ] && echo "  WARNING: Proposal may be too long (> 3000 words). Consider tightening."
```

### 9. Register and Notify

```bash
bash /home/shared/scripts/artifact.sh register \
  --name "proposal-${TOPIC}" \
  --type "proposal" \
  --path "$PROPOSAL_FILE" \
  --description "Proposal: ${TOPIC}"

# Notify the requesting agent or reviewer
bash /home/shared/scripts/send-mail.sh \
  --to "$REQUESTING_AGENT" \
  --subject "Proposal ready for review: ${TOPIC}" \
  --body "Draft proposal available at: $PROPOSAL_FILE"
```

## Quality Checklist

- [ ] Problem statement is specific, factual, and quantified (not vague or emotional)
- [ ] Impact is measured with numbers, not adjectives
- [ ] Proposed solution is concrete with specific deliverables
- [ ] Benefits are quantified with estimated values and timelines
- [ ] Costs include both one-time and recurring, with a first-year total
- [ ] At least 3 risks identified, each with a specific mitigation
- [ ] "Do nothing" is included as an alternative considered
- [ ] Implementation plan has phases, deliverables, and owners
- [ ] Success criteria are measurable with target values and evaluation dates
- [ ] Decision requested is explicit and specific
- [ ] Document leads with the most important information (decision-maker can decide from page 1)
- [ ] Report is registered as an artifact in the shared workspace
