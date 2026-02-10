---
name: competitive-analysis
description: Analyze competing products, tools, or approaches and produce a structured comparison report
---

# Competitive Analysis

## When to Use

Use this skill when tasked with comparing competing products, tools, services, vendors, or approaches. This is for evaluating external options against each other and against organizational needs — not for comparing internal code implementations (use the analyst/comparative-analysis skill for weighted scoring of internal options).

Common scenarios:
- Evaluating vendor products for procurement decisions
- Comparing open-source tools for adoption
- Assessing competitive landscape for strategic planning
- Benchmarking current tooling against alternatives

## Output Template

```markdown
# Competitive Analysis: [Category]

**Date:** YYYY-MM-DD
**Analyst:** [agent name]
**Decision Context:** [What decision does this analysis support?]

## Executive Summary
[2-3 sentences: how many options evaluated, which stands out, why]

## Options Evaluated
| # | Option | Category | Version/Date | Source |
|---|--------|----------|--------------|--------|
| 1 | [name] | [type] | [version] | [where info came from] |

## Comparison Matrix

| Criterion | [Option A] | [Option B] | [Option C] |
|-----------|-----------|-----------|-----------|
| [criterion 1] | [value] | [value] | [value] |
| [criterion 2] | [value] | [value] | [value] |

## Individual Assessments

### [Option A]
**Strengths:**
- [Strength 1 — with specific evidence]
- [Strength 2]

**Weaknesses:**
- [Weakness 1 — with specific evidence]
- [Weakness 2]

**Best Fit For:** [scenario where this option wins]

### [Option B]
...

## Recommendation
**Recommended option:** [name]
**Rationale:** [3-5 sentences explaining why, referencing specific criteria]
**Caveats:** [conditions under which this recommendation would change]

## Sources
| # | Source | Type | Reliability | Notes |
|---|--------|------|-------------|-------|
| 1 | [name/path] | [doc/spec/article] | [High/Medium/Low] | [brief note] |
```

## Procedure

### 1. Define the Analysis Scope

```bash
# Read the task to extract what needs comparing
TASK_ID="$1"
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'
```

Document these before proceeding:
- **Category:** What type of thing are we comparing? (e.g., "CI/CD platforms", "cloud storage providers")
- **Decision context:** What decision does this support? Who is the decision-maker?
- **Options:** List all options to evaluate (aim for 3-5; fewer is shallow, more is unfocused)
- **Constraints:** Budget limits, must-have requirements, deal-breakers

### 2. Gather Information on Each Option

```bash
TOPIC="$2"  # e.g., "terraform" or "ci-cd-tools"

# Search workspace for any existing research, docs, or references
rg -l -i "$TOPIC" ~/workspace/ /home/shared/ 2>/dev/null | head -30

# Search for comparison docs that may already exist
find ~/workspace/ /home/shared/ -name '*.md' -o -name '*.txt' -o -name '*.csv' \
  | xargs grep -li "compar\|versus\|vs\.\|alternative" 2>/dev/null

# Check for any data files with product/tool information
find /home/shared/ -name '*.json' -o -name '*.csv' -o -name '*.yaml' \
  | xargs grep -li "$TOPIC" 2>/dev/null

# Read any input files specified in the task
INPUT_DIR="/home/shared/inputs"
if [ -d "$INPUT_DIR" ]; then
  find "$INPUT_DIR" -type f | while read f; do
    echo "=== $f ==="
    head -50 "$f"
    echo ""
  done
fi
```

For each option, create a structured fact file:

```bash
OPTION="option-a"
mkdir -p /tmp/competitive-analysis

cat > "/tmp/competitive-analysis/${OPTION}.md" <<'EOF'
# Option: [Name]

## Basic Facts
- **Full name:**
- **Category:**
- **Version/Release date:**
- **Vendor/Maintainer:**
- **Pricing model:**
- **License:**

## Capabilities
- [capability 1]
- [capability 2]

## Limitations
- [limitation 1]
- [limitation 2]

## Evidence
- Source: [path/reference] — [what it says]
EOF
```

### 3. Define Evaluation Criteria

Criteria must be specific and measurable. Avoid vague criteria like "ease of use."

```bash
cat > /tmp/competitive-analysis/criteria.md <<'EOF'
| # | Criterion | Definition | Measurement | Weight |
|---|-----------|-----------|-------------|--------|
| 1 | [name] | [what exactly this means] | [how to measure/assess] | [H/M/L] |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |
EOF
```

Good criteria examples:
- "Supports SSO via SAML 2.0" (specific, verifiable)
- "First-year total cost for 50 users" (quantifiable)
- "Time to complete standard onboarding workflow" (measurable)

Bad criteria examples:
- "User-friendly" (subjective, undefined)
- "Good support" (vague)
- "Modern" (meaningless)

### 4. Build the Comparison Matrix

```bash
# Create a CSV comparison matrix for structured analysis
MATRIX_FILE="/tmp/competitive-analysis/matrix.csv"

# Build header row from options
echo "criterion,weight,option_a,option_b,option_c" > "$MATRIX_FILE"

# Add rows for each criterion
# Use specific values: numbers, yes/no, or short factual descriptions
cat >> "$MATRIX_FILE" <<'EOF'
SSO Support,H,SAML+OIDC,SAML only,No
Annual Cost (50 users),H,$12000,$8500,$15000
API Rate Limit,M,10000/hr,5000/hr,Unlimited
Setup Time (estimated),M,2 weeks,1 week,3 weeks
Active Community Size,L,15000 GitHub stars,2000,45000
EOF
```

Render the matrix as a readable table:

```bash
# Pretty-print the CSV matrix
column -t -s',' "$MATRIX_FILE"
```

### 5. Assess Strengths and Weaknesses

For each option, extract strengths and weaknesses from the gathered facts:

```bash
# Generate structured assessment per option
python3 <<'PYEOF'
import csv

with open("/tmp/competitive-analysis/matrix.csv") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

options = [k for k in rows[0].keys() if k not in ("criterion", "weight")]

for opt in options:
    print(f"\n## {opt}")
    strengths = []
    weaknesses = []
    for row in rows:
        val = row[opt]
        criterion = row["criterion"]
        weight = row["weight"]
        # Collect all values for this criterion to compare
        all_vals = [row[o] for o in options]
        # Flag as strength if this appears to be the best value
        # Flag as weakness if this appears to be the worst value
        print(f"  {criterion} ({weight}): {val}")
PYEOF
```

### 6. Formulate Recommendation

The recommendation must:
1. Name a specific option
2. Reference at least 3 criteria from the matrix that support it
3. Acknowledge what is sacrificed by not choosing alternatives
4. State conditions that would change the recommendation

### 7. Write the Report

```bash
REPORT_FILE="/home/shared/competitive-analysis-$(date +%Y%m%d)-${TOPIC}.md"

cat > "$REPORT_FILE" <<'REPORT'
# Competitive Analysis: [Category]

**Date:** $(date +%Y-%m-%d)
**Analyst:** $(hostname)
**Decision Context:** [What decision this supports]

## Executive Summary

[2-3 sentences summarizing the analysis and top-level finding]

## Options Evaluated

| # | Option | Category | Version/Date | Source |
|---|--------|----------|--------------|--------|
| 1 | [name] | [type] | [version] | [source] |
| 2 | [name] | [type] | [version] | [source] |
| 3 | [name] | [type] | [version] | [source] |

## Evaluation Criteria

| # | Criterion | Definition | Weight |
|---|-----------|-----------|--------|
| 1 | [name] | [what it means] | [H/M/L] |
| 2 | [name] | [what it means] | [H/M/L] |

## Comparison Matrix

| Criterion | Weight | [Option A] | [Option B] | [Option C] |
|-----------|--------|-----------|-----------|-----------|
| [name] | H | [value] | [value] | [value] |
| [name] | M | [value] | [value] | [value] |

## Individual Assessments

### [Option A]
**Strengths:**
- [Strength with evidence from matrix]

**Weaknesses:**
- [Weakness with evidence from matrix]

**Best Fit For:** [specific scenario]

### [Option B]
...

### [Option C]
...

## Recommendation

**Recommended option:** [name]

**Rationale:** [Why this option, citing specific criteria values from the matrix. Reference at least 3 data points.]

**What you give up:** [Specific advantages of non-recommended options that are sacrificed]

**Conditions that would change this recommendation:**
- If [condition], then [alternative option] would be preferred
- If [constraint changes], reconsider [option]

## Sources

| # | Source | Type | Reliability | Notes |
|---|--------|------|-------------|-------|
| 1 | [path/ref] | [type] | [H/M/L] | [note] |
REPORT

echo "Report written to: $REPORT_FILE"
```

### 8. Register as Artifact and Notify

```bash
bash /home/shared/scripts/artifact.sh register \
  --name "competitive-analysis-${TOPIC}" \
  --type "analysis" \
  --path "$REPORT_FILE" \
  --description "Competitive analysis of ${TOPIC} options"

# Notify requesting agent
bash /home/shared/scripts/send-mail.sh \
  --to "$REQUESTING_AGENT" \
  --subject "Competitive analysis complete: ${TOPIC}" \
  --body "Report available at: $REPORT_FILE"
```

## Quality Checklist

- [ ] At least 3 options are evaluated (not just 2)
- [ ] Every criterion is specific and measurable (no vague terms like "good" or "easy")
- [ ] Comparison matrix uses factual values, not opinions
- [ ] Each option has both strengths AND weaknesses identified
- [ ] Recommendation cites at least 3 specific data points from the matrix
- [ ] Trade-offs of the recommendation are explicitly stated
- [ ] Conditions for changing the recommendation are documented
- [ ] All factual claims have a cited source
- [ ] Report is registered as an artifact in the shared workspace
