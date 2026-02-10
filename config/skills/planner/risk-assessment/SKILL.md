---
name: risk-assessment
description: Identify, analyze, and prioritize risks in a project or initiative with a scored risk register
---

# Risk Assessment

## When to Use

Use this skill when tasked with identifying potential risks to a project, initiative, or decision. This applies to project kickoffs, milestone reviews, pre-launch assessments, vendor evaluations, or any situation where understanding what could go wrong is critical for planning.

## Output Template

```markdown
# Risk Assessment: [Subject]

**Date:** YYYY-MM-DD
**Assessor:** [agent name]
**Scope:** [what is being assessed]

## Risk Register

| ID | Risk | Category | Prob | Impact | Score | Mitigation | Owner |
|----|------|----------|------|--------|-------|------------|-------|
| R1 | ... | technical | 0.N | N | N.N | ... | ... |

## Risk Heat Map

         Impact ->  1-Low   2-Med   3-High  4-Crit
Prob 4-High         [ ]     [ ]     [R3]    [R1]
Prob 3-Med          [ ]     [R5]    [R2]    [ ]
Prob 2-Low          [R7]    [R4]    [ ]     [ ]
Prob 1-Rare         [ ]     [ ]     [R6]    [ ]

## Top 5 Risks
1. **R1: [description]** — Score: N.N — [mitigation summary]

## Mitigation Plan
[Actions, owners, deadlines]
```

## Procedure

### 1. Gather Project Context

```bash
# Read project documentation
echo "=== Project Docs ==="
find /home/shared -maxdepth 2 -name "*.md" -type f 2>/dev/null | head -20

echo ""
echo "=== Task Board Overview ==="
bash /home/shared/scripts/task.sh list 2>/dev/null | jq '
  {
    total: length,
    by_status: (group_by(.status) | map({status: .[0].status, count: length})),
    owners: ([.[].owner] | unique)
  }
' 2>/dev/null

echo ""
echo "=== Recent Artifacts ==="
bash /home/shared/scripts/artifact.sh list 2>/dev/null | jq -r '.[] | "\(.path) — \(.description)"' 2>/dev/null

echo ""
echo "=== Check for Existing Risk Docs ==="
find /home/shared -name "*risk*" -type f 2>/dev/null
rg -il "risk|threat|vulnerability|concern" /home/shared/*.md 2>/dev/null | head -10
```

### 2. Brainstorm Risks by Category

Systematically walk through each category to avoid blind spots:

```bash
cat > /tmp/risk-categories.txt <<'EOF'
TECHNICAL — Technology does not work as expected
  - Integration failures, performance issues, scalability limits
  - Untested dependencies, API changes, data migration errors
  - Security vulnerabilities, compliance gaps

SCHEDULE — Timelines are not met
  - Underestimated complexity, scope creep, dependency delays
  - Key milestones missed, parallel workstreams blocking each other
  - Approval or review cycles longer than expected

RESOURCE — People, budget, or tools are insufficient
  - Key person dependency, skill gaps, turnover
  - Budget overrun, tool licensing, infrastructure costs
  - Competing priorities, team capacity

EXTERNAL — Factors outside the team's control
  - Vendor reliability, regulatory changes, market shifts
  - Stakeholder priority changes, organizational restructuring
  - Third-party outages, supply chain disruption

QUALITY — Deliverables do not meet standards
  - Insufficient testing, missing acceptance criteria
  - Documentation gaps, knowledge silos
  - Technical debt accumulation
EOF

cat /tmp/risk-categories.txt
```

### 3. Build the Risk Register

```bash
cat > /tmp/risks.csv <<'EOF'
id,risk,category,probability,impact,mitigation,owner,notes
R1,Core integration fails with legacy system,technical,0.7,4,Build integration prototype in week 1; have fallback API adapter,architect,Legacy system has no documentation
R2,Delivery deadline missed by 2+ weeks,schedule,0.5,3,Add 2-week buffer to plan; identify tasks that can be cut,planner,Three hard dependencies on external team
R3,Lead developer leaves mid-project,resource,0.3,4,Cross-train second developer; document all decisions,manager,Single point of expertise on auth module
R4,Vendor API deprecates endpoint we depend on,external,0.2,3,Pin to versioned API; monitor changelog; have migration plan,devops,Vendor has 90-day deprecation policy
R5,Performance does not meet SLA under load,technical,0.4,3,Load test by milestone 2; define performance budget upfront,qa,No load testing infrastructure exists yet
R6,Regulatory requirement changes scope,external,0.1,4,Monitor regulatory calendar; build modular design for swap,planner,Proposed regulation in comment period
R7,Test coverage insufficient for go-live,quality,0.3,2,Define coverage threshold (80%); automate in CI pipeline,qa,Currently at 45% coverage
R8,Budget overrun due to cloud costs,resource,0.4,2,Set billing alerts; right-size from day 1; review weekly,devops,No cost baseline exists
EOF

echo "=== Risk Register ==="
column -t -s',' /tmp/risks.csv
```

### 4. Score and Rank Risks

```bash
python3 <<'PYEOF'
import csv
import json

with open("/tmp/risks.csv") as f:
    risks = list(csv.DictReader(f))

# Score = Probability * Impact
scored = []
for r in risks:
    prob = float(r["probability"])
    impact = int(r["impact"])
    score = round(prob * impact, 2)
    scored.append({**r, "score": score})

# Sort by score descending
scored.sort(key=lambda x: x["score"], reverse=True)

print("=" * 80)
print("RISK REGISTER — RANKED BY SCORE")
print("=" * 80)
print(f"{'ID':<4} {'Score':>5} {'Prob':>5} {'Imp':>4} {'Category':<10} {'Risk'}")
print("-" * 80)
for r in scored:
    severity = "CRITICAL" if r["score"] >= 2.0 else "HIGH" if r["score"] >= 1.2 else "MEDIUM" if r["score"] >= 0.6 else "LOW"
    print(f"{r['id']:<4} {r['score']:>5.2f} {float(r['probability']):>5.1f} {r['impact']:>4} {r['category']:<10} {r['risk']}")

# Write scored register
with open("/tmp/risks-scored.json", "w") as f:
    json.dump(scored, f, indent=2)

print()
print("Scored register written to /tmp/risks-scored.json")
PYEOF
```

### 5. Generate the Heat Map

```bash
python3 <<'PYEOF'
import json

with open("/tmp/risks-scored.json") as f:
    risks = json.load(f)

# Build 4x4 grid: probability (rows) x impact (columns)
# Probability buckets: 1=Rare(0-0.15), 2=Low(0.15-0.35), 3=Med(0.35-0.6), 4=High(0.6+)
# Impact: 1=Low, 2=Med, 3=High, 4=Critical
def prob_bucket(p):
    p = float(p)
    if p >= 0.6: return 4
    if p >= 0.35: return 3
    if p >= 0.15: return 2
    return 1

grid = {}
for r in risks:
    pb = prob_bucket(r["probability"])
    imp = int(r["impact"])
    key = (pb, imp)
    grid.setdefault(key, []).append(r["id"])

prob_labels = {4: "High  ", 3: "Med   ", 2: "Low   ", 1: "Rare  "}
impact_labels = {1: " 1-Low  ", 2: " 2-Med  ", 3: " 3-High ", 4: " 4-Crit "}

# Color zones: score = prob_bucket * impact
# >=8 = CRITICAL, >=4 = HIGH, >=2 = MEDIUM, else LOW
def zone(pb, imp):
    s = pb * imp
    if s >= 8: return "!!!"
    if s >= 4: return "!! "
    if s >= 2: return "!  "
    return "   "

print("=" * 60)
print("RISK HEAT MAP")
print("=" * 60)
print()
print(f"{'':>14}", end="")
for imp in [1, 2, 3, 4]:
    print(f"{impact_labels[imp]:>10}", end="")
print()
print(f"{'':>14}{'Impact -->':^40}")
print()

for pb in [4, 3, 2, 1]:
    label = f"Prob {prob_labels[pb]}"
    print(f"{label:>14}", end="")
    for imp in [1, 2, 3, 4]:
        ids = grid.get((pb, imp), [])
        cell = ",".join(ids) if ids else "."
        z = zone(pb, imp)
        print(f"[{z}{cell:^5}]  ", end="")
    print()

print()
print("Legend: !!! = Critical zone  !! = High zone  ! = Medium zone  (blank) = Low zone")
print()

# Print top 5 with details
print("=" * 60)
print("TOP 5 RISKS")
print("=" * 60)
for i, r in enumerate(risks[:5], 1):
    severity = "CRITICAL" if r["score"] >= 2.0 else "HIGH" if r["score"] >= 1.2 else "MEDIUM"
    print(f"\n{i}. [{severity}] {r['id']}: {r['risk']}")
    print(f"   Score: {r['score']} (Prob: {r['probability']}, Impact: {r['impact']})")
    print(f"   Category: {r['category']}")
    print(f"   Mitigation: {r['mitigation']}")
    print(f"   Owner: {r['owner']}")
PYEOF
```

### 6. Define Mitigation Plan

```bash
python3 <<'PYEOF'
import json

with open("/tmp/risks-scored.json") as f:
    risks = json.load(f)

print("=" * 70)
print("MITIGATION PLAN")
print("=" * 70)
print()
print(f"{'ID':<4} {'Score':>5} {'Strategy':<12} {'Action':<40} {'Owner':<10}")
print("-" * 70)

for r in risks:
    score = r["score"]
    # Determine strategy based on score
    if score >= 2.0:
        strategy = "AVOID"
    elif score >= 1.2:
        strategy = "MITIGATE"
    elif score >= 0.6:
        strategy = "MITIGATE"
    else:
        strategy = "ACCEPT"

    mitigation = r["mitigation"][:38] + ".." if len(r["mitigation"]) > 40 else r["mitigation"]
    print(f"{r['id']:<4} {score:>5.2f} {strategy:<12} {mitigation:<40} {r['owner']:<10}")

print()
print("Strategies: AVOID=eliminate the risk, MITIGATE=reduce probability/impact, ACCEPT=monitor only")
PYEOF
```

### 7. Write the Final Report

```bash
SUBJECT="${1:-Project Risk Assessment}"
REPORT_FILE="/home/shared/risk-assessment-$(date +%Y%m%d).md"

cat > "$REPORT_FILE" <<REOF
# Risk Assessment: ${SUBJECT}

**Date:** $(date +%Y-%m-%d)
**Assessor:** $(whoami)
**Scope:** ${SUBJECT}
**Risks Identified:** $(wc -l < /tmp/risks.csv | awk '{print $1 - 1}')

## Executive Summary

$(python3 -c "
import json
with open('/tmp/risks-scored.json') as f:
    risks = json.load(f)
critical = sum(1 for r in risks if r['score'] >= 2.0)
high = sum(1 for r in risks if 1.2 <= r['score'] < 2.0)
medium = sum(1 for r in risks if 0.6 <= r['score'] < 1.2)
low = sum(1 for r in risks if r['score'] < 0.6)
print(f'This assessment identified {len(risks)} risks: {critical} Critical, {high} High, {medium} Medium, {low} Low.')
if critical > 0:
    top = risks[0]
    print(f'The highest-scored risk is {top[\"id\"]}: \"{top[\"risk\"]}\" (score {top[\"score\"]}).')
    print('Critical risks require immediate mitigation action before proceeding.')
elif high > 0:
    print('No critical risks were identified, but high-severity risks require active mitigation plans.')
else:
    print('No critical or high risks were identified. Standard monitoring is recommended.')
")

## Risk Register

$(python3 -c "
import json
with open('/tmp/risks-scored.json') as f:
    risks = json.load(f)
print('| ID | Risk | Category | Prob | Impact | Score | Severity | Mitigation | Owner |')
print('|----|------|----------|------|--------|-------|----------|------------|-------|')
for r in risks:
    sev = 'CRITICAL' if r['score'] >= 2.0 else 'HIGH' if r['score'] >= 1.2 else 'MEDIUM' if r['score'] >= 0.6 else 'LOW'
    print(f'| {r[\"id\"]} | {r[\"risk\"]} | {r[\"category\"]} | {r[\"probability\"]} | {r[\"impact\"]} | {r[\"score\"]} | {sev} | {r[\"mitigation\"]} | {r[\"owner\"]} |')
")

## Risk Heat Map

\`\`\`
$(python3 -c "
import json
with open('/tmp/risks-scored.json') as f:
    risks = json.load(f)

def prob_bucket(p):
    p = float(p)
    if p >= 0.6: return 4
    if p >= 0.35: return 3
    if p >= 0.15: return 2
    return 1

grid = {}
for r in risks:
    pb = prob_bucket(r['probability'])
    imp = int(r['impact'])
    grid.setdefault((pb, imp), []).append(r['id'])

print('             Impact -->  1-Low     2-Med     3-High    4-Crit')
prob_labels = {4: 'High  ', 3: 'Med   ', 2: 'Low   ', 1: 'Rare  '}
for pb in [4, 3, 2, 1]:
    row = f'Prob {prob_labels[pb]}  '
    for imp in [1, 2, 3, 4]:
        ids = grid.get((pb, imp), [])
        cell = ','.join(ids) if ids else '  .  '
        row += f'[{cell:^7}]  '
    print(row)
")
\`\`\`

## Top 5 Risks

$(python3 -c "
import json
with open('/tmp/risks-scored.json') as f:
    risks = json.load(f)
for i, r in enumerate(risks[:5], 1):
    sev = 'CRITICAL' if r['score'] >= 2.0 else 'HIGH' if r['score'] >= 1.2 else 'MEDIUM'
    print(f'{i}. **{r[\"id\"]}: {r[\"risk\"]}** (Score: {r[\"score\"]}, {sev})')
    print(f'   - Category: {r[\"category\"]}')
    print(f'   - Mitigation: {r[\"mitigation\"]}')
    print(f'   - Owner: {r[\"owner\"]}')
    print()
")

## Mitigation Plan

$(python3 -c "
import json
with open('/tmp/risks-scored.json') as f:
    risks = json.load(f)
print('| ID | Score | Strategy | Mitigation Action | Owner | Deadline |')
print('|----|-------|----------|-------------------|-------|----------|')
for r in risks:
    s = r['score']
    strategy = 'AVOID' if s >= 2.0 else 'MITIGATE' if s >= 0.6 else 'ACCEPT'
    print(f'| {r[\"id\"]} | {s} | {strategy} | {r[\"mitigation\"]} | {r[\"owner\"]} | TBD |')
")

## Risk Score Distribution

$(python3 -c "
import json
with open('/tmp/risks-scored.json') as f:
    risks = json.load(f)
# Category breakdown
from collections import Counter
cats = Counter(r['category'] for r in risks)
print('| Category | Count | Avg Score |')
print('|----------|-------|-----------|')
for cat in sorted(cats.keys()):
    cat_risks = [r for r in risks if r['category'] == cat]
    avg = sum(r['score'] for r in cat_risks) / len(cat_risks)
    print(f'| {cat} | {len(cat_risks)} | {avg:.2f} |')
")

## Methodology

- Risk identification: systematic review by category (technical, schedule, resource, external, quality)
- Scoring: Probability (0.0-1.0) x Impact (1-4) = Risk Score (0.0-4.0)
- Severity thresholds: Critical (>=2.0), High (>=1.2), Medium (>=0.6), Low (<0.6)
- Mitigation strategies: Avoid (critical), Mitigate (high/medium), Accept (low)
REOF

echo "Report written to: $REPORT_FILE"

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  "$REPORT_FILE" \
  --description "Risk assessment for: ${SUBJECT}"
```

## Quality Checklist

- [ ] All five risk categories considered (technical, schedule, resource, external, quality)
- [ ] Each risk has probability (0-1), impact (1-4), and computed score
- [ ] Risk register is sorted by score (highest first)
- [ ] Heat map generated showing risk distribution
- [ ] Top 5 risks summarized with specific mitigations
- [ ] Every mitigation has an owner assigned
- [ ] Mitigation strategy matches severity level (avoid/mitigate/accept)
- [ ] Report written to shared workspace and registered as artifact
