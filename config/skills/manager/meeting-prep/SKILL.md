---
name: meeting-prep
description: Prepare structured meeting agendas and pre-reads from task board, artifacts, and team context
---

# Meeting Prep

## When to Use

Use this skill when tasked with preparing for a meeting, review session, planning workshop, or any structured discussion. This skill gathers context from the task board, artifact registry, and agent mail to produce a ready-to-use agenda with time boxes, decision items, pre-read materials, and an action items template.

## Output Template

```markdown
# Meeting Agenda: [Title]

**Date:** YYYY-MM-DD
**Time:** HH:MM - HH:MM (N minutes)
**Facilitator:** [name]
**Attendees:** [list]

## Agenda

| # | Topic | Owner | Time | Objective |
|---|-------|-------|------|-----------|
| 1 | ... | ... | N min | Inform / Discuss / Decide |

## Decision Items
- [ ] D1: [decision description] — Owner: [name]

## Pre-Read Materials
| Document | Location | Why to Read |
|----------|----------|-------------|
| ... | ... | ... |

## Action Items (to be filled during meeting)
| # | Action | Owner | Due | Status |
|---|--------|-------|-----|--------|
| A1 | | | | |
```

## Procedure

### 1. Gather Context from All Sources

```bash
echo "=== Task Board Summary ==="
ALL_TASKS=$(bash /home/shared/scripts/task.sh list 2>/dev/null)
echo "$ALL_TASKS" > /tmp/meeting-tasks.json

echo "$ALL_TASKS" | jq '
  {
    total: length,
    by_status: (group_by(.status) | map({status: .[0].status, count: length})),
    in_progress: [.[] | select(.status == "in_progress") | {id: .id, subject: .subject, owner: .owner}],
    blocked: [.[] | select(.status == "pending" and (.blocked_by | length) > 0) | {id: .id, subject: .subject, blocked_by: .blocked_by}],
    failed: [.[] | select(.status == "failed") | {id: .id, subject: .subject, owner: .owner}],
    recently_completed: [.[] | select(.status == "completed") | {id: .id, subject: .subject, owner: .owner}]
  }
' 2>/dev/null

echo ""
echo "=== Recent Artifacts ==="
ARTIFACTS=$(bash /home/shared/scripts/artifact.sh list 2>/dev/null)
echo "$ARTIFACTS" > /tmp/meeting-artifacts.json
echo "$ARTIFACTS" | jq '
  sort_by(.registered_at) | reverse | .[0:10] |
  .[] | {path: .path, description: .description, producer: .producer}
' 2>/dev/null

echo ""
echo "=== Unread Mail ==="
mail -f ~/Maildir -H 2>/dev/null | tail -20

echo ""
echo "=== Team Roster ==="
for agent_home in /home/*/; do
  agent=$(basename "$agent_home")
  [ "$agent" = "shared" ] && continue
  ROLE=$(getent passwd "$agent" 2>/dev/null | cut -d: -f5)
  echo "  $agent ($ROLE)"
done

echo ""
echo "=== Events (last 20) ==="
EVENTS_FILE="/home/shared/events.jsonl"
if [ -f "$EVENTS_FILE" ]; then
  tail -20 "$EVENTS_FILE" | jq -c '{ts: .timestamp, type: .type, agent: .agent, msg: .message}' 2>/dev/null
fi
```

### 2. Identify Discussion Topics

```bash
python3 <<'PYEOF'
import json

# Load context
try:
    with open("/tmp/meeting-tasks.json") as f:
        tasks = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    tasks = []

try:
    with open("/tmp/meeting-artifacts.json") as f:
        artifacts = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    artifacts = []

topics = []

# Topic 1: Status overview (always include)
completed = sum(1 for t in tasks if t.get("status") == "completed")
total = len(tasks)
pct = round(completed / total * 100) if total > 0 else 0
topics.append({
    "topic": "Project Status Overview",
    "type": "inform",
    "time_min": 5,
    "owner": "facilitator",
    "notes": f"{completed}/{total} tasks complete ({pct}%)",
    "priority": 1
})

# Topic 2: Blockers (if any)
blocked = [t for t in tasks if t.get("status") == "pending" and t.get("blocked_by")]
if blocked:
    topics.append({
        "topic": f"Blocked Tasks ({len(blocked)} items)",
        "type": "discuss",
        "time_min": 10,
        "owner": "facilitator",
        "notes": "; ".join(f"{t['id']}: {t.get('subject','')}" for t in blocked[:3]),
        "priority": 2
    })

# Topic 3: Failed tasks (if any)
failed = [t for t in tasks if t.get("status") == "failed"]
if failed:
    topics.append({
        "topic": f"Failed Tasks ({len(failed)} items) — Root Cause & Reassignment",
        "type": "decide",
        "time_min": 10,
        "owner": "facilitator",
        "notes": "; ".join(f"{t['id']}: {t.get('subject','')}" for t in failed[:3]),
        "priority": 2
    })

# Topic 4: In-progress work check-in
in_progress = [t for t in tasks if t.get("status") == "in_progress"]
if in_progress:
    owners = list(set(t.get("owner", "unknown") for t in in_progress))
    topics.append({
        "topic": "Work In Progress — Status & Blockers",
        "type": "discuss",
        "time_min": max(5, len(owners) * 3),
        "owner": ", ".join(owners[:5]),
        "notes": f"{len(in_progress)} tasks active across {len(owners)} agents",
        "priority": 3
    })

# Topic 5: Recent artifacts to review
if artifacts:
    recent = sorted(artifacts, key=lambda a: a.get("registered_at", ""), reverse=True)[:3]
    topics.append({
        "topic": "Artifact Review — Recent Deliverables",
        "type": "discuss",
        "time_min": 10,
        "owner": "facilitator",
        "notes": "; ".join(a.get("description", a.get("path", "")) for a in recent),
        "priority": 4
    })

# Topic 6: Upcoming work / next sprint
pending = [t for t in tasks if t.get("status") == "pending"]
if pending:
    topics.append({
        "topic": f"Upcoming Work — {len(pending)} Pending Tasks",
        "type": "discuss",
        "time_min": 10,
        "owner": "planner",
        "notes": "Review priority and readiness of pending tasks",
        "priority": 5
    })

# Topic 7: Risks (always include)
topics.append({
    "topic": "Risks & Concerns",
    "type": "discuss",
    "time_min": 5,
    "owner": "all",
    "notes": "Open floor for any risks or concerns",
    "priority": 6
})

# Topic 8: Action items (always last)
topics.append({
    "topic": "Action Items & Next Steps",
    "type": "decide",
    "time_min": 5,
    "owner": "facilitator",
    "notes": "Summarize decisions and assign action items",
    "priority": 99
})

# Sort by priority
topics.sort(key=lambda t: t["priority"])

total_time = sum(t["time_min"] for t in topics)

print("=" * 70)
print("IDENTIFIED TOPICS")
print("=" * 70)
print(f"Total estimated time: {total_time} minutes")
print()
for i, t in enumerate(topics, 1):
    print(f"  {i}. [{t['type'].upper():<7}] {t['topic']} ({t['time_min']} min)")
    print(f"     Owner: {t['owner']}")
    if t["notes"]:
        print(f"     Notes: {t['notes']}")
    print()

with open("/tmp/meeting-topics.json", "w") as f:
    json.dump(topics, f, indent=2)

print(f"Topics written to /tmp/meeting-topics.json")
PYEOF
```

### 3. Build Pre-Read List

```bash
python3 <<'PYEOF'
import json

try:
    with open("/tmp/meeting-artifacts.json") as f:
        artifacts = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    artifacts = []

try:
    with open("/tmp/meeting-tasks.json") as f:
        tasks = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    tasks = []

prereads = []

# Recent artifacts are pre-reads
for a in sorted(artifacts, key=lambda x: x.get("registered_at", ""), reverse=True)[:5]:
    prereads.append({
        "document": a.get("description", a.get("path", "Unknown")),
        "location": a.get("path", ""),
        "why": f"Recent deliverable from {a.get('producer', 'unknown')}"
    })

# Risk or status reports
import os
for pattern in ["risk", "status", "plan", "design"]:
    import subprocess
    result = subprocess.run(
        ["find", "/home/shared", "-maxdepth", "2", "-name", f"*{pattern}*", "-type", "f"],
        capture_output=True, text=True
    )
    for path in result.stdout.strip().split("\n"):
        if path and not any(p["location"] == path for p in prereads):
            prereads.append({
                "document": f"{pattern.title()} document",
                "location": path,
                "why": f"Background context ({pattern})"
            })

print("=" * 60)
print("PRE-READ MATERIALS")
print("=" * 60)
print()
if prereads:
    print(f"{'Document':<35} {'Location':<30}")
    print("-" * 65)
    for p in prereads[:8]:
        doc = p["document"][:33]
        loc = p["location"][:28]
        print(f"  {doc:<33} {loc:<30}")
        print(f"  Reason: {p['why']}")
else:
    print("  No pre-read materials identified.")

with open("/tmp/meeting-prereads.json", "w") as f:
    json.dump(prereads, f, indent=2)

print(f"\nPre-reads written to /tmp/meeting-prereads.json")
PYEOF
```

### 4. Extract Decision Items

```bash
python3 <<'PYEOF'
import json

try:
    with open("/tmp/meeting-tasks.json") as f:
        tasks = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    tasks = []

try:
    with open("/tmp/meeting-topics.json") as f:
        topics = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    topics = []

decisions = []

# Failed tasks need reassignment decisions
failed = [t for t in tasks if t.get("status") == "failed"]
for t in failed:
    decisions.append({
        "id": f"D-{len(decisions)+1}",
        "description": f"Reassign or retry failed task {t.get('id')}: {t.get('subject', '')}",
        "owner": "facilitator",
        "options": "Retry with same owner / Reassign / Descope"
    })

# Blocked tasks may need dependency resolution
blocked = [t for t in tasks if t.get("status") == "pending" and t.get("blocked_by")]
for t in blocked[:3]:  # Top 3 blockers
    decisions.append({
        "id": f"D-{len(decisions)+1}",
        "description": f"Unblock task {t.get('id')}: {t.get('subject', '')}",
        "owner": "facilitator",
        "options": "Resolve dependency / Remove dependency / Replan"
    })

# Topics flagged as "decide" type
for topic in topics:
    if topic["type"] == "decide" and "Action Items" not in topic["topic"]:
        decisions.append({
            "id": f"D-{len(decisions)+1}",
            "description": topic["topic"],
            "owner": topic["owner"],
            "options": "To be discussed"
        })

print("=" * 60)
print("DECISION ITEMS")
print("=" * 60)
print()
if decisions:
    for d in decisions:
        print(f"  {d['id']}: {d['description']}")
        print(f"     Owner: {d['owner']}")
        print(f"     Options: {d['options']}")
        print()
else:
    print("  No pending decisions identified.")

with open("/tmp/meeting-decisions.json", "w") as f:
    json.dump(decisions, f, indent=2)

print(f"Decisions written to /tmp/meeting-decisions.json")
PYEOF
```

### 5. Assemble the Agenda

```bash
python3 <<'PYEOF'
import json

with open("/tmp/meeting-topics.json") as f:
    topics = json.load(f)

total_time = sum(t["time_min"] for t in topics)

# Compute start times (relative offsets)
elapsed = 0
for t in topics:
    t["start_offset"] = elapsed
    elapsed += t["time_min"]

print("=" * 70)
print("MEETING AGENDA")
print("=" * 70)
print(f"Duration: {total_time} minutes")
print()
print(f"{'#':<3} {'Time':>7} {'Topic':<35} {'Owner':<15} {'Objective':<10}")
print("-" * 70)
for i, t in enumerate(topics, 1):
    time_str = f"{t['start_offset']:>3}-{t['start_offset']+t['time_min']:<3}"
    obj = t["type"].title()
    print(f"{i:<3} {time_str:>7} {t['topic']:<35} {t['owner']:<15} {obj:<10}")

print()
PYEOF
```

### 6. Write the Final Agenda Document

```bash
MEETING_TITLE="${1:-Project Sync Meeting}"
REPORT_FILE="/home/shared/meeting-agenda-$(date +%Y%m%d).md"

python3 <<PYEOF
import json
from datetime import datetime

with open("/tmp/meeting-topics.json") as f:
    topics = json.load(f)
with open("/tmp/meeting-prereads.json") as f:
    prereads = json.load(f)
with open("/tmp/meeting-decisions.json") as f:
    decisions = json.load(f)

today = datetime.now().strftime("%Y-%m-%d")
total_time = sum(t["time_min"] for t in topics)

# Build time offsets
elapsed = 0
for t in topics:
    t["start_offset"] = elapsed
    elapsed += t["time_min"]

# Attendee list from task owners
try:
    with open("/tmp/meeting-tasks.json") as f:
        tasks = json.load(f)
    owners = sorted(set(t.get("owner", "") for t in tasks if t.get("owner")))
except:
    owners = []

agenda = f"""# Meeting Agenda: $MEETING_TITLE

**Date:** {today}
**Duration:** {total_time} minutes
**Facilitator:** $(whoami)
**Attendees:** {', '.join(owners) if owners else 'TBD'}

## Agenda

| # | Time (min) | Topic | Owner | Objective |
|---|------------|-------|-------|-----------|
"""

for i, t in enumerate(topics, 1):
    time_range = f"{t['start_offset']}-{t['start_offset']+t['time_min']}"
    agenda += f"| {i} | {time_range} | {t['topic']} | {t['owner']} | {t['type'].title()} |\n"

agenda += f"""
**Total Time:** {total_time} minutes

## Topic Details

"""

for i, t in enumerate(topics, 1):
    agenda += f"### {i}. {t['topic']} ({t['time_min']} min)\n\n"
    agenda += f"- **Owner:** {t['owner']}\n"
    agenda += f"- **Objective:** {t['type'].title()}\n"
    if t.get("notes"):
        agenda += f"- **Context:** {t['notes']}\n"
    agenda += "\n"

# Decision items
agenda += "## Decision Items\n\n"
if decisions:
    for d in decisions:
        agenda += f"- [ ] **{d['id']}:** {d['description']}\n"
        agenda += f"  - Owner: {d['owner']}\n"
        if d.get("options") and d["options"] != "To be discussed":
            agenda += f"  - Options: {d['options']}\n"
        agenda += f"  - Decision: ________________\n\n"
else:
    agenda += "No pending decisions identified.\n\n"

# Pre-read materials
agenda += "## Pre-Read Materials\n\n"
if prereads:
    agenda += "| Document | Location | Why to Read |\n"
    agenda += "|----------|----------|-------------|\n"
    for p in prereads[:8]:
        agenda += f"| {p['document']} | {p['location']} | {p['why']} |\n"
else:
    agenda += "No pre-read materials identified.\n"

# Action items template
agenda += """
## Action Items (fill during meeting)

| # | Action | Owner | Due Date | Status |
|---|--------|-------|----------|--------|
| A1 | | | | |
| A2 | | | | |
| A3 | | | | |
| A4 | | | | |
| A5 | | | | |

## Meeting Notes

_Space for notes during the meeting:_

---

"""

# Preparation checklist
agenda += """## Preparation Checklist (for facilitator)

- [ ] Agenda shared with attendees 24 hours in advance
- [ ] Pre-read materials linked and accessible
- [ ] Decision items owners notified to prepare options
- [ ] Previous meeting action items reviewed for follow-up
- [ ] Time-keeper identified
- [ ] Note-taker identified
"""

with open("$REPORT_FILE", "w") as f:
    f.write(agenda)

print(f"Agenda written to: $REPORT_FILE")
PYEOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  "$REPORT_FILE" \
  --description "Meeting agenda for: $MEETING_TITLE ($(date +%Y-%m-%d))"
```

### 7. Distribute the Agenda

```bash
MEETING_TITLE="${1:-Project Sync Meeting}"
REPORT_FILE="/home/shared/meeting-agenda-$(date +%Y%m%d).md"

# Send agenda to all team members
for agent_home in /home/*/; do
  agent=$(basename "$agent_home")
  [ "$agent" = "shared" ] && continue
  [ "$agent" = "$(whoami)" ] && continue

  bash /home/shared/scripts/send-mail.sh "$agent" \
    --from "$(whoami)" \
    --subject "Meeting Agenda: $MEETING_TITLE" \
    -- "Meeting agenda for $MEETING_TITLE has been prepared.

Please review the agenda and pre-read materials before the meeting.

Agenda location: $REPORT_FILE

If you own any decision items, please come prepared with your recommendation."
done

echo "Agenda distributed to all team members."
```

## Quality Checklist

- [ ] Task board queried for current status, blockers, and failed tasks
- [ ] Artifact registry checked for recent deliverables (potential pre-reads)
- [ ] Mail and events reviewed for context
- [ ] Every agenda item has an owner, time box, and clear objective (inform/discuss/decide)
- [ ] Decision items are explicit with options (not just "discuss X")
- [ ] Pre-read materials are listed with location and reason to read
- [ ] Action items template is included for capturing outcomes
- [ ] Total time computed and realistic for the meeting duration
- [ ] Agenda registered as artifact and distributed to attendees
