---
name: comparative-analysis
description: Compare options against weighted criteria with scored matrix, sensitivity analysis, and quantified recommendation
---

# Comparative Analysis

## When to Use

Use this skill when tasked with systematically comparing options, approaches, or alternatives against defined criteria using weighted scoring. This is the quantitative counterpart to the researcher/competitive-analysis skill: it produces a scored, weighted matrix with numerical results and sensitivity checks.

Common scenarios:
- Choosing between architectural approaches with multiple trade-offs
- Evaluating vendor proposals against procurement criteria
- Comparing process alternatives where stakeholders disagree on priorities
- Any decision where "it depends" needs to be made rigorous

## Output Template

```markdown
# Comparative Analysis: [Decision]

**Date:** YYYY-MM-DD
**Analyst:** [agent name]
**Decision Context:** [What decision this analysis supports]

## Options

| # | Option | Description |
|---|--------|-------------|
| 1 | [name] | [one-line description] |
| 2 | [name] | [one-line description] |
| 3 | [name] | [one-line description] |

## Criteria and Weights

| # | Criterion | Definition | Weight | Justification |
|---|-----------|-----------|--------|---------------|
| 1 | [name] | [measurable definition] | [0.0-1.0] | [why this weight] |
| Totals | | | 1.00 | |

## Raw Scoring Matrix

| Criterion | Weight | [Opt A] | [Opt B] | [Opt C] |
|-----------|--------|---------|---------|---------|
| [name] | [wt] | [1-5] | [1-5] | [1-5] |
| ... | ... | ... | ... | ... |

## Weighted Results

| Option | Weighted Score | Rank |
|--------|---------------|------|
| [name] | [score] | [1/2/3] |

## Sensitivity Analysis

| Scenario | Weight Change | Winner | Score Delta |
|----------|--------------|--------|-------------|
| [scenario] | [what changed] | [option] | [margin] |

## Recommendation

**Recommended option:** [name]
**Score:** [N.NN] out of 5.00
**Margin over second place:** [N.NN] ([N]%)
**Sensitivity:** [Robust/Fragile] — [explanation]
```

## Procedure

### 1. Define the Decision and Gather Inputs

```bash
TASK_ID="$1"
TOPIC="$2"

# Read the task
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'

# Find related materials
rg -l -i "$TOPIC" /home/shared/ ~/workspace/ 2>/dev/null | head -20

# Check for prior research or competitive analysis
find /home/shared/ -name '*analysis*' -o -name '*research*' -o -name '*comparison*' \
  2>/dev/null | head -10

# Read any input specifications (criteria, constraints, preferences)
find /home/shared/inputs/ -type f 2>/dev/null | while read f; do
  echo "=== $f ==="
  cat "$f"
  echo ""
done
```

### 2. Define Options

List all options to evaluate. Include at least 3 for a meaningful comparison.

```bash
WORK_DIR="/tmp/comparative-${TOPIC}"
mkdir -p "$WORK_DIR"

# Create options definition file
cat > "$WORK_DIR/options.json" <<'EOF'
[
  {"id": "option_a", "name": "Option A", "description": "Brief description of option A"},
  {"id": "option_b", "name": "Option B", "description": "Brief description of option B"},
  {"id": "option_c", "name": "Option C", "description": "Brief description of option C"}
]
EOF

jq -r '.[] | "  \(.id): \(.name) — \(.description)"' "$WORK_DIR/options.json"
```

### 3. Define Criteria and Weights

Criteria must be measurable. Weights must sum to 1.0.

```bash
# Create criteria with weights
cat > "$WORK_DIR/criteria.json" <<'EOF'
[
  {"id": "c1", "name": "Criterion 1", "definition": "How this is measured", "weight": 0.30, "justification": "Why this weight"},
  {"id": "c2", "name": "Criterion 2", "definition": "How this is measured", "weight": 0.25, "justification": "Why this weight"},
  {"id": "c3", "name": "Criterion 3", "definition": "How this is measured", "weight": 0.20, "justification": "Why this weight"},
  {"id": "c4", "name": "Criterion 4", "definition": "How this is measured", "weight": 0.15, "justification": "Why this weight"},
  {"id": "c5", "name": "Criterion 5", "definition": "How this is measured", "weight": 0.10, "justification": "Why this weight"}
]
EOF

# Validate weights sum to 1.0
WEIGHT_SUM=$(jq '[.[].weight] | add' "$WORK_DIR/criteria.json")
echo "Weight sum: $WEIGHT_SUM"
if [ "$(echo "$WEIGHT_SUM == 1.0" | bc -l)" -ne 1 ]; then
  echo "ERROR: Weights must sum to 1.0 (currently $WEIGHT_SUM)"
fi

# Display criteria table
echo ""
echo "| # | Criterion | Weight | Justification |"
echo "|---|-----------|--------|---------------|"
jq -r 'to_entries[] | "| \(.key + 1) | \(.value.name) | \(.value.weight) | \(.value.justification) |"' "$WORK_DIR/criteria.json"
```

### 4. Score Each Option

Score each option on each criterion using a 1-5 scale:

| Score | Meaning |
|-------|---------|
| 5 | Excellent — fully meets or exceeds the criterion |
| 4 | Good — meets the criterion with minor gaps |
| 3 | Adequate — meets minimum requirements |
| 2 | Below average — significant gaps |
| 1 | Poor — fails to meet the criterion |

```bash
# Create the scoring matrix as CSV
cat > "$WORK_DIR/scores.csv" <<'EOF'
criterion,weight,option_a,option_b,option_c
Criterion 1,0.30,4,3,5
Criterion 2,0.25,5,4,3
Criterion 3,0.20,3,5,4
Criterion 4,0.15,4,4,3
Criterion 5,0.10,3,5,4
EOF

# Display the raw scores
echo "=== Raw Scoring Matrix ==="
column -t -s',' "$WORK_DIR/scores.csv"
```

### 5. Compute Weighted Scores

```bash
# Compute weighted totals using awk
echo "=== Weighted Score Computation ==="

awk -F',' '
NR == 1 {
  # Header row — extract option names
  for (i = 3; i <= NF; i++) options[i] = $i
  next
}
{
  criterion = $1
  weight = $2
  for (i = 3; i <= NF; i++) {
    raw = $i
    weighted = raw * weight
    totals[i] += weighted
    printf "  %s x %s: %s x %.2f = %.2f\n", criterion, options[i], raw, weight, weighted
  }
}
END {
  print ""
  print "=== WEIGHTED TOTALS ==="
  # Sort by score (descending)
  for (i in totals) {
    printf "  %-20s  %.2f / 5.00\n", options[i], totals[i]
  }
}' "$WORK_DIR/scores.csv"
```

For more precise computation with ranking:

```bash
python3 <<'PYEOF'
import csv
import json

# Read scores
with open("/tmp/comparative-${TOPIC}/scores.csv") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

# Identify option columns (everything except criterion and weight)
option_cols = [k for k in rows[0].keys() if k not in ("criterion", "weight")]

# Compute weighted scores
results = {opt: 0.0 for opt in option_cols}
details = []

for row in rows:
    criterion = row["criterion"]
    weight = float(row["weight"])
    for opt in option_cols:
        raw = float(row[opt])
        weighted = raw * weight
        results[opt] += weighted
        details.append({
            "criterion": criterion,
            "option": opt,
            "weight": weight,
            "raw_score": raw,
            "weighted_score": round(weighted, 3)
        })

# Rank by score
ranked = sorted(results.items(), key=lambda x: x[1], reverse=True)

print("=" * 50)
print("WEIGHTED RESULTS")
print("=" * 50)
print(f"{'Option':<20} {'Score':>8} {'Rank':>6}")
print("-" * 36)
for rank, (opt, score) in enumerate(ranked, 1):
    print(f"{opt:<20} {score:>8.2f} {rank:>6}")

# Margin analysis
if len(ranked) >= 2:
    margin = ranked[0][1] - ranked[1][1]
    margin_pct = (margin / ranked[0][1]) * 100
    print(f"\nMargin: {ranked[0][0]} leads {ranked[1][0]} by {margin:.2f} ({margin_pct:.1f}%)")

# Save results for later use
output = {
    "ranked": [{"option": opt, "score": round(score, 3), "rank": rank}
               for rank, (opt, score) in enumerate(ranked, 1)],
    "details": details,
    "margin": round(margin, 3) if len(ranked) >= 2 else None
}
with open("/tmp/comparative-${TOPIC}/results.json", "w") as f:
    json.dump(output, f, indent=2)
print("\nResults saved to results.json")
PYEOF
```

### 6. Sensitivity Analysis

Test whether the recommendation changes if weights shift:

```bash
python3 <<'PYEOF'
import csv
import json

# Read scores
with open("/tmp/comparative-${TOPIC}/scores.csv") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

option_cols = [k for k in rows[0].keys() if k not in ("criterion", "weight")]

def compute_winner(rows, weight_overrides=None):
    """Compute weighted scores with optional weight overrides."""
    results = {opt: 0.0 for opt in option_cols}
    for row in rows:
        weight = float(row["weight"])
        criterion = row["criterion"]
        if weight_overrides and criterion in weight_overrides:
            weight = weight_overrides[criterion]
        for opt in option_cols:
            results[opt] += float(row[opt]) * weight
    ranked = sorted(results.items(), key=lambda x: x[1], reverse=True)
    return ranked

# Baseline
baseline = compute_winner(rows)
baseline_winner = baseline[0][0]
print(f"Baseline winner: {baseline_winner} ({baseline[0][1]:.2f})")
print()

# Scenario: shift each criterion weight by +0.10 and -0.10
criteria = [row["criterion"] for row in rows]
original_weights = {row["criterion"]: float(row["weight"]) for row in rows}

print(f"{'Scenario':<40} {'Winner':<15} {'Score':<8} {'Changed?'}")
print("-" * 70)

scenarios = []
for c in criteria:
    for delta, label in [(0.15, "+0.15"), (-0.15, "-0.15")]:
        new_weight = max(0.0, original_weights[c] + delta)
        # Redistribute remaining weight proportionally among other criteria
        remaining = 1.0 - new_weight
        other_total = sum(original_weights[k] for k in criteria if k != c)
        overrides = {}
        for k in criteria:
            if k == c:
                overrides[k] = new_weight
            else:
                overrides[k] = (original_weights[k] / other_total) * remaining if other_total > 0 else remaining / (len(criteria) - 1)

        result = compute_winner(rows, overrides)
        winner = result[0][0]
        score = result[0][1]
        changed = "YES" if winner != baseline_winner else "no"
        scenario_name = f"{c} {label}"
        print(f"{scenario_name:<40} {winner:<15} {score:<8.2f} {changed}")
        scenarios.append({
            "scenario": scenario_name,
            "weight_change": f"{c} from {original_weights[c]:.2f} to {new_weight:.2f}",
            "winner": winner,
            "score": round(score, 3),
            "changed": winner != baseline_winner
        })

# Summary
changes = sum(1 for s in scenarios if s["changed"])
total = len(scenarios)
print(f"\nSensitivity: winner changed in {changes}/{total} scenarios")
if changes == 0:
    print("Assessment: ROBUST — recommendation holds across all weight variations")
elif changes <= total * 0.25:
    print("Assessment: MODERATELY ROBUST — recommendation holds in most scenarios")
else:
    print("Assessment: FRAGILE — recommendation is sensitive to weight assumptions")

# Save sensitivity results
with open("/tmp/comparative-${TOPIC}/sensitivity.json", "w") as f:
    json.dump(scenarios, f, indent=2)
PYEOF
```

### 7. Write the Report

```bash
REPORT_FILE="/home/shared/comparative-analysis-$(date +%Y%m%d)-${TOPIC}.md"

cat > "$REPORT_FILE" <<'REPORT'
# Comparative Analysis: [Decision]

**Date:** YYYY-MM-DD
**Analyst:** [agent name]
**Decision Context:** [What decision this supports]

## Options

| # | Option | Description |
|---|--------|-------------|
| 1 | [name] | [description] |
| 2 | [name] | [description] |
| 3 | [name] | [description] |

## Criteria and Weights

| # | Criterion | Definition | Weight | Justification |
|---|-----------|-----------|--------|---------------|
| 1 | [name] | [how measured] | [0.XX] | [why] |
| | **Total** | | **1.00** | |

Scoring scale: 1 (poor) to 5 (excellent)

## Raw Scoring Matrix

| Criterion | Weight | [Option A] | [Option B] | [Option C] |
|-----------|--------|-----------|-----------|-----------|
| [name] | [wt] | [1-5] | [1-5] | [1-5] |

**Scoring justifications:**
- [Option A] scored [N] on [Criterion] because [specific reason]
- [Option B] scored [N] on [Criterion] because [specific reason]

## Weighted Results

| Rank | Option | Weighted Score | % of Maximum |
|------|--------|---------------|--------------|
| 1 | [name] | [N.NN] | [NN%] |
| 2 | [name] | [N.NN] | [NN%] |
| 3 | [name] | [N.NN] | [NN%] |

**Margin:** [winner] leads [second place] by [N.NN] points ([N]%)

## Sensitivity Analysis

| Scenario | Weight Change | Winner | Changed? |
|----------|--------------|--------|----------|
| [criterion] +0.15 | [old] -> [new] | [option] | [yes/no] |

**Assessment:** [Robust/Moderately Robust/Fragile] — [explanation]

## Recommendation

**Recommended option:** [name]
**Score:** [N.NN] / 5.00 ([NN]% of maximum)
**Margin:** [N.NN] over second place ([N]%)
**Sensitivity:** [Robust/Fragile]

**Rationale:** [2-3 sentences explaining why this option wins, citing specific criteria where it excels and acknowledging criteria where alternatives score higher]

**Key trade-off:** By choosing [winner], we accept [specific weakness] in exchange for [specific strength]. If [condition changes], reconsider [alternative].

## Methodology

- Options: [how identified]
- Criteria: [how selected and weighted]
- Scoring: [who scored, what information was used]
- Sensitivity: [weight shifts of +/-0.15 with proportional redistribution]

## Data Files

- Scores: [path to scores.csv]
- Results: [path to results.json]
- Sensitivity: [path to sensitivity.json]
REPORT

echo "Report written to: $REPORT_FILE"
```

### 8. Register and Notify

```bash
# Copy working data files to shared workspace
cp "$WORK_DIR/scores.csv" "/home/shared/comparative-${TOPIC}-scores.csv" 2>/dev/null
cp "$WORK_DIR/results.json" "/home/shared/comparative-${TOPIC}-results.json" 2>/dev/null

bash /home/shared/scripts/artifact.sh register \
  --name "comparative-analysis-${TOPIC}" \
  --type "analysis" \
  --path "$REPORT_FILE" \
  --description "Weighted comparative analysis of ${TOPIC} options"

bash /home/shared/scripts/artifact.sh register \
  --name "comparative-analysis-${TOPIC}-data" \
  --type "data" \
  --path "/home/shared/comparative-${TOPIC}-scores.csv" \
  --description "Raw scoring data for ${TOPIC} comparative analysis"

# Notify requesting agent
bash /home/shared/scripts/send-mail.sh \
  --to "$REQUESTING_AGENT" \
  --subject "Comparative analysis complete: ${TOPIC}" \
  --body "Report: $REPORT_FILE | Data: /home/shared/comparative-${TOPIC}-scores.csv"
```

## Quality Checklist

- [ ] At least 3 options are compared
- [ ] At least 4 criteria are defined with measurable definitions
- [ ] Weights sum to exactly 1.00
- [ ] Every weight has a justification (not arbitrary)
- [ ] Raw scores use the 1-5 scale consistently
- [ ] Every score has a documented justification (not just a number)
- [ ] Weighted totals are computed correctly (spot-check at least one row)
- [ ] Sensitivity analysis tests weight shifts of at least +/-0.15 on each criterion
- [ ] Recommendation states the margin and sensitivity assessment
- [ ] Trade-offs of the recommendation are explicitly acknowledged
- [ ] Methodology section documents how options, criteria, and scores were determined
- [ ] Raw data files (CSV/JSON) are saved alongside the report
- [ ] Report is registered as an artifact in the shared workspace
