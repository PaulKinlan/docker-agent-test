---
name: stakeholder-mapping
description: Identify stakeholders and map their influence, interest, and communication needs
---

# Stakeholder Mapping

## When to Use

Use this skill when starting a new project, initiative, or organizational change that affects multiple people or groups. Stakeholder mapping clarifies who needs to be informed, consulted, or involved in decision-making, and prevents communication gaps that derail projects.

## Output Template

```markdown
# Stakeholder Map: [Subject]

**Date:** YYYY-MM-DD
**Author:** [agent name]
**Project:** [project or initiative name]

## Stakeholder Register

| ID | Stakeholder | Role/Title | Interest | Power | Quadrant | Key Concern |
|----|------------|------------|----------|-------|----------|-------------|
| S1 | ... | ... | H/M/L | H/M/L | Manage Closely | ... |

## Power/Interest Grid

            High Power
          +-------------+-------------+
          | Keep        | Manage      |
          | Satisfied   | Closely     |
          | [S3]        | [S1, S2]    |
          +-------------+-------------+
          | Monitor     | Keep        |
          |             | Informed    |
          | [S6]        | [S4, S5]    |
          +-------------+-------------+
            Low Power
          Low Interest   High Interest

## Communication Plan

| Stakeholder | Quadrant | Frequency | Channel | Content | Owner |
|------------|----------|-----------|---------|---------|-------|
| S1 | Manage Closely | Weekly | 1:1 meeting | Progress, decisions | PM |
```

## Procedure

### 1. Gather Project Context

```bash
# Read project documentation for stakeholder references
echo "=== Project Documentation ==="
find /home/shared -maxdepth 2 -name "*.md" -type f 2>/dev/null | head -20

echo ""
echo "=== Searching for Stakeholder References ==="
rg -i "stakeholder|sponsor|owner|team|department|manager|director|VP|executive|customer|user|client" \
  /home/shared/*.md 2>/dev/null | head -30

echo ""
echo "=== Task Board — Unique Owners ==="
bash /home/shared/scripts/task.sh list 2>/dev/null | jq '[.[].owner] | unique | .[]' 2>/dev/null

echo ""
echo "=== Artifact Producers ==="
bash /home/shared/scripts/artifact.sh list 2>/dev/null | jq '[.[].producer] | unique | .[]' 2>/dev/null

echo ""
echo "=== Check for Existing Stakeholder Docs ==="
find /home/shared -name "*stakeholder*" -type f 2>/dev/null
```

### 2. Identify Stakeholders

Work through these prompts to build a comprehensive list:

```bash
cat > /tmp/stakeholder-prompts.txt <<'EOF'
IDENTIFICATION PROMPTS — Answer each to find stakeholders:

1. WHO requested or funded this work?
   (Executive sponsor, budget owner)

2. WHO will use the output directly?
   (End users, customers, internal teams)

3. WHO must approve decisions or deliverables?
   (Gate reviewers, compliance, legal)

4. WHO provides resources (people, budget, tools)?
   (Resource managers, procurement, IT)

5. WHO is affected even if they are not directly involved?
   (Adjacent teams, downstream systems, support staff)

6. WHO has domain expertise the project depends on?
   (Subject matter experts, architects, data owners)

7. WHO can block or delay the project?
   (Regulatory bodies, shared service teams, dependencies)

8. WHO will maintain the output after delivery?
   (Operations, support, on-call teams)

9. WHAT external parties are involved?
   (Vendors, partners, regulators, auditors)

10. WHO cares about the outcome for strategic reasons?
    (Leadership, board, investors, competitors)
EOF

cat /tmp/stakeholder-prompts.txt
```

### 3. Build the Stakeholder Register

```bash
# Create stakeholder data
# Interest: 1=Low, 2=Medium, 3=High
# Power: 1=Low, 2=Medium, 3=High
cat > /tmp/stakeholders.csv <<'EOF'
id,name,role,interest,power,key_concern,attitude,notes
S1,VP Engineering,Executive Sponsor,3,3,On-time delivery and budget adherence,supportive,Final go/no-go authority
S2,Product Manager,Product Owner,3,3,Feature scope and user impact,supportive,Defines requirements and priorities
S3,CTO,Technical Authority,2,3,Architecture alignment with platform strategy,neutral,Needs to approve technical decisions
S4,Development Team,Implementers,3,2,Clear requirements and achievable timeline,supportive,6 developers across 2 squads
S5,QA Lead,Quality Gate,3,2,Test coverage and release criteria,neutral,Owns go-live sign-off
S6,Legal/Compliance,Regulatory Reviewer,1,2,Data privacy and regulatory compliance,neutral,Only engaged for specific reviews
S7,Customer Success,User Advocate,3,1,Customer satisfaction and adoption,supportive,Relays customer feedback
S8,Infrastructure Team,Platform Dependency,2,2,Resource allocation and deployment pipeline,neutral,Shared team with competing priorities
S9,Finance,Budget Controller,1,2,Cost tracking and ROI realization,neutral,Quarterly budget reviews
S10,End Users,Consumers,3,1,Usability and reliability,varies,Diverse group with different needs
EOF

echo "=== Stakeholder Register ==="
column -t -s',' /tmp/stakeholders.csv
```

### 4. Classify by Power/Interest Grid

```bash
python3 <<'PYEOF'
import csv
import json

with open("/tmp/stakeholders.csv") as f:
    stakeholders = list(csv.DictReader(f))

# Classify into quadrants
# High Power + High Interest = Manage Closely
# High Power + Low Interest = Keep Satisfied
# Low Power + High Interest = Keep Informed
# Low Power + Low Interest = Monitor

quadrants = {
    "Manage Closely": [],
    "Keep Satisfied": [],
    "Keep Informed": [],
    "Monitor": []
}

for s in stakeholders:
    power = int(s["power"])
    interest = int(s["interest"])

    # Threshold: >=2 is "high" for classification
    high_power = power >= 2
    high_interest = interest >= 2

    if high_power and high_interest:
        q = "Manage Closely"
    elif high_power and not high_interest:
        q = "Keep Satisfied"
    elif not high_power and high_interest:
        q = "Keep Informed"
    else:
        q = "Monitor"

    s["quadrant"] = q
    quadrants[q].append(s)

print("=" * 60)
print("POWER/INTEREST CLASSIFICATION")
print("=" * 60)
print()

for q_name in ["Manage Closely", "Keep Satisfied", "Keep Informed", "Monitor"]:
    members = quadrants[q_name]
    ids = ", ".join(s["id"] for s in members)
    print(f"  {q_name}: {ids if ids else '(none)'}")
    for s in members:
        print(f"    {s['id']} {s['name']:<25} Power:{s['power']} Interest:{s['interest']} Attitude:{s['attitude']}")
    print()

# Save classified data
with open("/tmp/stakeholders-classified.json", "w") as f:
    json.dump(stakeholders, f, indent=2)

print("Classified data written to /tmp/stakeholders-classified.json")
PYEOF
```

### 5. Generate the Power/Interest Grid (Text Visualization)

```bash
python3 <<'PYEOF'
import json

with open("/tmp/stakeholders-classified.json") as f:
    stakeholders = json.load(f)

# Build text-based grid
grid = {"Manage Closely": [], "Keep Satisfied": [], "Keep Informed": [], "Monitor": []}
for s in stakeholders:
    grid[s["quadrant"]].append(s["id"])

def fmt_cell(ids, width=22):
    content = ", ".join(ids) if ids else "(none)"
    return content.center(width)

print()
print("  POWER/INTEREST GRID")
print()
print("               Low Interest          High Interest")
print("            +------------------------+------------------------+")
print("            |                        |                        |")
print("  High      |    KEEP SATISFIED      |    MANAGE CLOSELY      |")
print(f"  Power     |  {fmt_cell(grid['Keep Satisfied'])}  |  {fmt_cell(grid['Manage Closely'])}  |")
print("            |                        |                        |")
print("            |  Strategy: Engage on   |  Strategy: Close       |")
print("            |  key decisions only    |  partnership; frequent |")
print("            |                        |  updates               |")
print("            +------------------------+------------------------+")
print("            |                        |                        |")
print("  Low       |    MONITOR             |    KEEP INFORMED       |")
print(f"  Power     |  {fmt_cell(grid['Monitor'])}  |  {fmt_cell(grid['Keep Informed'])}  |")
print("            |                        |                        |")
print("            |  Strategy: Minimal     |  Strategy: Regular     |")
print("            |  effort; watch for     |  updates; address      |")
print("            |  changes               |  concerns              |")
print("            +------------------------+------------------------+")
print()
PYEOF
```

### 6. Build Communication Plan

```bash
python3 <<'PYEOF'
import json

with open("/tmp/stakeholders-classified.json") as f:
    stakeholders = json.load(f)

# Define communication strategy per quadrant
strategies = {
    "Manage Closely": {
        "frequency": "Weekly",
        "channel": "1:1 meeting + written update",
        "content": "Progress, decisions needed, risks, blockers",
        "approach": "Proactive; seek input before decisions"
    },
    "Keep Satisfied": {
        "frequency": "Bi-weekly",
        "channel": "Email summary + on-request meetings",
        "content": "Milestone updates, budget status, escalations",
        "approach": "Respectful of time; concise updates"
    },
    "Keep Informed": {
        "frequency": "Weekly",
        "channel": "Team channel + newsletter",
        "content": "Progress updates, upcoming changes, feedback requests",
        "approach": "Transparent; open feedback channels"
    },
    "Monitor": {
        "frequency": "Monthly or as needed",
        "channel": "Email or shared dashboard",
        "content": "Major milestones, changes that affect them",
        "approach": "Light touch; engage only when relevant"
    }
}

print("=" * 80)
print("COMMUNICATION PLAN")
print("=" * 80)
print()
print(f"{'ID':<4} {'Stakeholder':<22} {'Quadrant':<18} {'Frequency':<12} {'Channel':<30}")
print("-" * 80)

for s in stakeholders:
    q = s["quadrant"]
    strat = strategies[q]
    print(f"{s['id']:<4} {s['name']:<22} {q:<18} {strat['frequency']:<12} {strat['channel']:<30}")

print()
print("=" * 80)
print("STRATEGY DETAILS BY QUADRANT")
print("=" * 80)
for q_name, strat in strategies.items():
    members = [s for s in stakeholders if s["quadrant"] == q_name]
    if not members:
        continue
    ids = ", ".join(s["id"] for s in members)
    print(f"\n  {q_name} ({ids}):")
    print(f"    Frequency: {strat['frequency']}")
    print(f"    Channel:   {strat['channel']}")
    print(f"    Content:   {strat['content']}")
    print(f"    Approach:  {strat['approach']}")

# Save communication plan
comm_plan = []
for s in stakeholders:
    strat = strategies[s["quadrant"]]
    comm_plan.append({
        "id": s["id"],
        "name": s["name"],
        "quadrant": s["quadrant"],
        "frequency": strat["frequency"],
        "channel": strat["channel"],
        "content": strat["content"]
    })

with open("/tmp/comm-plan.json", "w") as f:
    json.dump(comm_plan, f, indent=2)

print("\n\nCommunication plan written to /tmp/comm-plan.json")
PYEOF
```

### 7. Identify Engagement Risks

```bash
python3 <<'PYEOF'
import json

with open("/tmp/stakeholders-classified.json") as f:
    stakeholders = json.load(f)

print("=" * 60)
print("STAKEHOLDER ENGAGEMENT RISKS")
print("=" * 60)
print()

# Flag risks
risks = []
for s in stakeholders:
    flags = []
    if s["attitude"] in ("resistant", "hostile"):
        flags.append(f"Negative attitude ({s['attitude']}): needs active engagement to address concerns")
    if s["attitude"] == "neutral" and int(s["power"]) >= 2:
        flags.append("Neutral high-power stakeholder: risk of becoming blocker if not engaged")
    if s["quadrant"] == "Manage Closely" and s["attitude"] != "supportive":
        flags.append("Key stakeholder not yet supportive: prioritize relationship building")
    if int(s["power"]) >= 3 and int(s["interest"]) <= 1:
        flags.append("Very high power, low interest: could disengage then block late")

    if flags:
        risks.append({"stakeholder": s, "flags": flags})

if risks:
    for r in risks:
        s = r["stakeholder"]
        print(f"  {s['id']} {s['name']} ({s['role']}):")
        for flag in r["flags"]:
            print(f"    - {flag}")
        print()
else:
    print("  No significant engagement risks identified.")
PYEOF
```

### 8. Write the Final Report

```bash
SUBJECT="${1:-Project Stakeholder Map}"
REPORT_FILE="/home/shared/stakeholder-map-$(date +%Y%m%d).md"

cat > "$REPORT_FILE" <<REOF
# Stakeholder Map: ${SUBJECT}

**Date:** $(date +%Y-%m-%d)
**Author:** $(whoami)
**Project:** ${SUBJECT}
**Stakeholders Identified:** $(awk -F',' 'NR>1' /tmp/stakeholders.csv | wc -l | tr -d ' ')

## Stakeholder Register

$(python3 -c "
import json
with open('/tmp/stakeholders-classified.json') as f:
    ss = json.load(f)
print('| ID | Stakeholder | Role | Interest | Power | Quadrant | Attitude | Key Concern |')
print('|----|------------|------|----------|-------|----------|----------|-------------|')
for s in ss:
    il = {1:'Low',2:'Med',3:'High'}[int(s['interest'])]
    pl = {1:'Low',2:'Med',3:'High'}[int(s['power'])]
    print(f'| {s[\"id\"]} | {s[\"name\"]} | {s[\"role\"]} | {il} | {pl} | {s[\"quadrant\"]} | {s[\"attitude\"]} | {s[\"key_concern\"]} |')
")

## Power/Interest Grid

\`\`\`
$(python3 -c "
import json
with open('/tmp/stakeholders-classified.json') as f:
    stakeholders = json.load(f)
grid = {}
for s in stakeholders:
    grid.setdefault(s['quadrant'], []).append(s['id'])

def fmt(ids, w=20):
    return (', '.join(ids) if ids else '(none)').center(w)

print('               Low Interest          High Interest')
print('            +------------------------+------------------------+')
print('  High      |    KEEP SATISFIED      |    MANAGE CLOSELY      |')
print(f'  Power     |  {fmt(grid.get(\"Keep Satisfied\",[]))}    |  {fmt(grid.get(\"Manage Closely\",[]))}    |')
print('            +------------------------+------------------------+')
print('  Low       |    MONITOR             |    KEEP INFORMED       |')
print(f'  Power     |  {fmt(grid.get(\"Monitor\",[]))}    |  {fmt(grid.get(\"Keep Informed\",[]))}    |')
print('            +------------------------+------------------------+')
")
\`\`\`

## Communication Plan

$(python3 -c "
import json
with open('/tmp/comm-plan.json') as f:
    plan = json.load(f)
print('| ID | Stakeholder | Quadrant | Frequency | Channel | Content Focus |')
print('|----|------------|----------|-----------|---------|---------------|')
for p in plan:
    print(f'| {p[\"id\"]} | {p[\"name\"]} | {p[\"quadrant\"]} | {p[\"frequency\"]} | {p[\"channel\"]} | {p[\"content\"]} |')
")

## Engagement Risks

$(python3 -c "
import json
with open('/tmp/stakeholders-classified.json') as f:
    stakeholders = json.load(f)
found = False
for s in stakeholders:
    flags = []
    if s['attitude'] in ('resistant', 'hostile'):
        flags.append(f'Negative attitude ({s[\"attitude\"]})')
    if s['attitude'] == 'neutral' and int(s['power']) >= 2:
        flags.append('Neutral high-power stakeholder: engagement risk')
    if s['quadrant'] == 'Manage Closely' and s['attitude'] != 'supportive':
        flags.append('Key stakeholder not yet supportive')
    if flags:
        found = True
        print(f'- **{s[\"id\"]} {s[\"name\"]}**: {\" | \".join(flags)}')
if not found:
    print('No significant engagement risks identified.')
")

## Methodology

- Stakeholder identification via systematic prompt-based review (10 identification questions)
- Classification using Power/Interest grid (2x2 matrix)
- Communication strategy mapped to quadrant membership
- Engagement risks flagged for non-supportive high-power stakeholders
REOF

echo "Report written to: $REPORT_FILE"

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  "$REPORT_FILE" \
  --description "Stakeholder map for: ${SUBJECT}"
```

## Quality Checklist

- [ ] All 10 identification prompts considered (no stakeholder group overlooked)
- [ ] Each stakeholder has power, interest, and attitude assessed
- [ ] Power/Interest grid correctly classifies all stakeholders into quadrants
- [ ] Communication plan specifies frequency, channel, and content per stakeholder
- [ ] Engagement risks identified for non-supportive high-power stakeholders
- [ ] Quadrant strategies are actionable (not generic platitudes)
- [ ] Report written to shared workspace and registered as artifact
