---
name: status-reporting
description: Generate project status reports from task board data, agent outputs, and system health
---

# Status Reporting

## When to Use

Use this skill when tasked with producing a project status report, sprint summary, daily standup digest, or progress dashboard. This skill pulls real data from the task board, artifact registry, agent health, and event logs to produce an evidence-based status report rather than a subjective narrative.

## Output Template

```markdown
# Project Status Report

**Date:** YYYY-MM-DD
**Reporter:** [agent name]
**Period:** [start] to [end]
**Overall Status:** GREEN / YELLOW / RED

## Dashboard

| Metric | Value |
|--------|-------|
| Tasks Completed | N / N (N%) |
| Tasks In Progress | N |
| Tasks Blocked | N |
| Agents Active | N / N |

## Tasks by Status
[Breakdown table]

## Blockers
[List of blocked tasks with reasons]

## Recent Completions
[Tasks finished this period]

## Upcoming Milestones
[What is next]

## Risks & Concerns
[Flagged issues]
```

## Procedure

### 1. Query the Task Board

```bash
echo "=== Task Board Snapshot ==="
ALL_TASKS=$(bash /home/shared/scripts/task.sh list 2>/dev/null)

if [ -z "$ALL_TASKS" ] || [ "$ALL_TASKS" = "[]" ]; then
  echo "No tasks found on the task board."
  echo "Creating report from available artifacts and logs instead."
else
  echo "$ALL_TASKS" | jq '.' 2>/dev/null
fi

# Save for downstream processing
echo "$ALL_TASKS" > /tmp/all-tasks.json
```

### 2. Compute Status Metrics

```bash
python3 <<'PYEOF'
import json
import sys

try:
    with open("/tmp/all-tasks.json") as f:
        content = f.read().strip()
        tasks = json.loads(content) if content and content != "" else []
except (json.JSONDecodeError, FileNotFoundError):
    tasks = []

if not tasks:
    print("No task data available.")
    # Write empty metrics
    with open("/tmp/status-metrics.json", "w") as f:
        json.dump({"total": 0, "note": "No tasks on board"}, f)
    sys.exit(0)

total = len(tasks)
by_status = {}
for t in tasks:
    s = t.get("status", "unknown")
    by_status.setdefault(s, []).append(t)

completed = len(by_status.get("completed", []))
in_progress = len(by_status.get("in_progress", []))
pending = len(by_status.get("pending", []))
failed = len(by_status.get("failed", []))
pct_complete = round(completed / total * 100, 1) if total > 0 else 0

# Identify blocked tasks (pending with incomplete dependencies)
blocked = []
completed_ids = set(t.get("id", "") for t in by_status.get("completed", []))
for t in by_status.get("pending", []):
    deps = t.get("blocked_by", [])
    if deps:
        unmet = [d for d in deps if d not in completed_ids]
        if unmet:
            blocked.append({"task": t, "blocked_on": unmet})

# Tasks by owner
by_owner = {}
for t in tasks:
    owner = t.get("owner", "unassigned")
    by_owner.setdefault(owner, {"total": 0, "completed": 0, "in_progress": 0})
    by_owner[owner]["total"] += 1
    if t.get("status") == "completed":
        by_owner[owner]["completed"] += 1
    elif t.get("status") == "in_progress":
        by_owner[owner]["in_progress"] += 1

# Determine overall status (RAG)
if failed > 0 or len(blocked) > total * 0.3:
    rag = "RED"
elif len(blocked) > 0 or pct_complete < 25:
    rag = "YELLOW"
else:
    rag = "GREEN"

print("=" * 50)
print("STATUS METRICS")
print("=" * 50)
print(f"  Overall Status: {rag}")
print(f"  Total Tasks:    {total}")
print(f"  Completed:      {completed} ({pct_complete}%)")
print(f"  In Progress:    {in_progress}")
print(f"  Pending:        {pending}")
print(f"  Failed:         {failed}")
print(f"  Blocked:        {len(blocked)}")
print()
print("  By Owner:")
for owner, counts in sorted(by_owner.items()):
    print(f"    {owner}: {counts['completed']}/{counts['total']} done, {counts['in_progress']} active")

metrics = {
    "rag": rag,
    "total": total,
    "completed": completed,
    "in_progress": in_progress,
    "pending": pending,
    "failed": failed,
    "blocked_count": len(blocked),
    "pct_complete": pct_complete,
    "by_owner": by_owner,
    "blocked": [{"id": b["task"].get("id"), "subject": b["task"].get("subject"), "blocked_on": b["blocked_on"]} for b in blocked]
}

with open("/tmp/status-metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

print("\nMetrics written to /tmp/status-metrics.json")
PYEOF
```

### 3. Gather Agent Health

```bash
echo "=== Agent Health ==="

# Check health from check-health.sh if available
bash /home/shared/scripts/check-health.sh 2>/dev/null || true

echo ""
echo "=== Agent Heartbeats ==="
AGENTS_ALIVE=0
AGENTS_TOTAL=0

for agent_home in /home/*/; do
  agent=$(basename "$agent_home")
  [ "$agent" = "shared" ] && continue
  AGENTS_TOTAL=$((AGENTS_TOTAL + 1))

  HB_FILE="$agent_home/.heartbeat"
  if [ -f "$HB_FILE" ]; then
    LAST_BEAT=$(cat "$HB_FILE" 2>/dev/null)
    NOW=$(date +%s)
    BEAT_TS=$(date -d "$LAST_BEAT" +%s 2>/dev/null || echo 0)
    AGE=$((NOW - BEAT_TS))

    if [ "$AGE" -lt 300 ]; then
      STATUS="ALIVE (${AGE}s ago)"
      AGENTS_ALIVE=$((AGENTS_ALIVE + 1))
    else
      STATUS="STALE (${AGE}s ago)"
    fi
    echo "  $agent: $STATUS — last: $LAST_BEAT"
  else
    echo "  $agent: NO HEARTBEAT"
  fi
done

echo ""
echo "  Active: $AGENTS_ALIVE / $AGENTS_TOTAL"

# Save agent health
echo "{\"alive\": $AGENTS_ALIVE, \"total\": $AGENTS_TOTAL}" > /tmp/agent-health.json
```

### 4. Gather Recent Activity

```bash
echo "=== Recent Artifacts ==="
bash /home/shared/scripts/artifact.sh list 2>/dev/null | jq '
  sort_by(.registered_at) | reverse | .[0:10] |
  .[] | {path: .path, producer: .producer, registered: .registered_at, description: .description}
' 2>/dev/null

echo ""
echo "=== Recent Events ==="
EVENTS_FILE="/home/shared/events.jsonl"
if [ -f "$EVENTS_FILE" ]; then
  echo "Last 10 events:"
  tail -10 "$EVENTS_FILE" | jq -c '{ts: .timestamp, type: .type, agent: .agent, msg: .message}' 2>/dev/null
else
  echo "No events log found."
fi

echo ""
echo "=== Recent Mail Activity ==="
# Check for recent mail in agent mailboxes
for agent_home in /home/*/; do
  agent=$(basename "$agent_home")
  [ "$agent" = "shared" ] && continue
  MBOX="/var/mail/$agent"
  if [ -f "$MBOX" ] && [ -s "$MBOX" ]; then
    MSG_COUNT=$(grep -c "^From " "$MBOX" 2>/dev/null || echo 0)
    echo "  $agent: $MSG_COUNT messages"
  fi
done
```

### 5. Identify Blockers and Risks

```bash
python3 <<'PYEOF'
import json

with open("/tmp/status-metrics.json") as f:
    metrics = json.load(f)

print("=" * 60)
print("BLOCKERS AND RISKS")
print("=" * 60)

# Blocked tasks
blocked = metrics.get("blocked", [])
if blocked:
    print("\nBLOCKED TASKS:")
    for b in blocked:
        print(f"  {b['id']}: {b['subject']}")
        print(f"    Waiting on: {', '.join(b['blocked_on'])}")
else:
    print("\nNo blocked tasks.")

# Failed tasks
try:
    with open("/tmp/all-tasks.json") as f:
        tasks = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    tasks = []

failed = [t for t in tasks if t.get("status") == "failed"]
if failed:
    print("\nFAILED TASKS:")
    for t in failed:
        print(f"  {t.get('id')}: {t.get('subject')}")
        result = t.get("result", "No failure reason recorded")
        print(f"    Reason: {result}")

# Agent health risks
try:
    with open("/tmp/agent-health.json") as f:
        health = json.load(f)
    if health["alive"] < health["total"]:
        print(f"\nAGENT HEALTH WARNING: Only {health['alive']}/{health['total']} agents responding")
except FileNotFoundError:
    pass

# Workload imbalance
by_owner = metrics.get("by_owner", {})
if by_owner:
    loads = [(o, d["in_progress"]) for o, d in by_owner.items()]
    max_load = max(loads, key=lambda x: x[1])
    if max_load[1] >= 3:
        print(f"\nWORKLOAD WARNING: {max_load[0]} has {max_load[1]} tasks in progress")
PYEOF
```

### 6. Compute Swarm Cost Summary (if available)

```bash
echo "=== Cost Summary ==="
bash /home/shared/scripts/swarm-status.sh 2>/dev/null | head -20 || echo "Swarm status not available"

# Check for cost data in events
EVENTS_FILE="/home/shared/events.jsonl"
if [ -f "$EVENTS_FILE" ]; then
  echo ""
  echo "=== Cost Events ==="
  grep '"cost"' "$EVENTS_FILE" 2>/dev/null | jq -c '{agent: .agent, cost: .cost}' 2>/dev/null | tail -5
fi
```

### 7. Write the Status Report

```bash
REPORT_FILE="/home/shared/status-report-$(date +%Y%m%d).md"

python3 <<PYEOF
import json
from datetime import datetime

with open("/tmp/status-metrics.json") as f:
    m = json.load(f)

try:
    with open("/tmp/all-tasks.json") as f:
        tasks = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    tasks = []

try:
    with open("/tmp/agent-health.json") as f:
        health = json.load(f)
except FileNotFoundError:
    health = {"alive": 0, "total": 0}

today = datetime.now().strftime("%Y-%m-%d")
rag = m.get("rag", "UNKNOWN")
rag_emoji_map = {"GREEN": "On Track", "YELLOW": "At Risk", "RED": "Off Track"}
rag_label = rag_emoji_map.get(rag, rag)

report = f"""# Project Status Report

**Date:** {today}
**Reporter:** $(whoami)
**Overall Status:** {rag} ({rag_label})

## Dashboard

| Metric | Value |
|--------|-------|
| Tasks Completed | {m.get('completed',0)} / {m.get('total',0)} ({m.get('pct_complete',0)}%) |
| Tasks In Progress | {m.get('in_progress',0)} |
| Tasks Pending | {m.get('pending',0)} |
| Tasks Failed | {m.get('failed',0)} |
| Tasks Blocked | {m.get('blocked_count',0)} |
| Agents Active | {health.get('alive',0)} / {health.get('total',0)} |

## Progress by Owner

| Owner | Completed | In Progress | Total | % Done |
|-------|-----------|-------------|-------|--------|
"""

by_owner = m.get("by_owner", {})
for owner in sorted(by_owner.keys()):
    d = by_owner[owner]
    pct = round(d["completed"] / d["total"] * 100) if d["total"] > 0 else 0
    report += f"| {owner} | {d['completed']} | {d['in_progress']} | {d['total']} | {pct}% |\n"

# Tasks by status detail
report += "\n## Tasks by Status\n\n"
for status_name in ["in_progress", "pending", "completed", "failed"]:
    status_tasks = [t for t in tasks if t.get("status") == status_name]
    if status_tasks:
        report += f"\n### {status_name.replace('_', ' ').title()} ({len(status_tasks)})\n\n"
        report += "| ID | Subject | Owner |\n"
        report += "|----|---------|-------|\n"
        for t in status_tasks:
            report += f"| {t.get('id','-')} | {t.get('subject','-')} | {t.get('owner','-')} |\n"

# Blockers
blocked = m.get("blocked", [])
report += "\n## Blockers\n\n"
if blocked:
    report += "| Task ID | Subject | Blocked On |\n"
    report += "|---------|---------|------------|\n"
    for b in blocked:
        report += f"| {b['id']} | {b['subject']} | {', '.join(b['blocked_on'])} |\n"
else:
    report += "No blocked tasks.\n"

# Failed tasks
failed_tasks = [t for t in tasks if t.get("status") == "failed"]
if failed_tasks:
    report += "\n## Failed Tasks\n\n"
    report += "| Task ID | Subject | Owner | Failure Reason |\n"
    report += "|---------|---------|-------|----------------|\n"
    for t in failed_tasks:
        reason = t.get("result", "Not recorded")
        report += f"| {t.get('id','-')} | {t.get('subject','-')} | {t.get('owner','-')} | {reason} |\n"

# Risks
report += "\n## Risks & Concerns\n\n"
risks = []
if m.get("failed", 0) > 0:
    risks.append(f"- **{m['failed']} failed task(s)** require investigation and possible reassignment")
if m.get("blocked_count", 0) > 0:
    risks.append(f"- **{m['blocked_count']} blocked task(s)** — dependency chain needs attention")
if health.get("alive", 0) < health.get("total", 0):
    missing = health["total"] - health["alive"]
    risks.append(f"- **{missing} agent(s) not responding** — may need restart or investigation")
overloaded = [o for o, d in by_owner.items() if d.get("in_progress", 0) >= 3]
if overloaded:
    risks.append(f"- **Workload imbalance**: {', '.join(overloaded)} have 3+ active tasks")
if not risks:
    risks.append("- No significant risks identified at this time")
report += "\n".join(risks) + "\n"

# RAG justification
report += f"""
## Status Justification

**{rag}** — """
if rag == "GREEN":
    report += "No blockers, no failures, progress on track.\n"
elif rag == "YELLOW":
    report += "Blocked or pending tasks detected; progress may be at risk.\n"
else:
    report += "Failed tasks or significant blockers require immediate attention.\n"

report += """
## Methodology

- Task data sourced from task board via `task.sh list`
- Agent health from heartbeat files
- Artifacts from artifact registry via `artifact.sh list`
- RAG status: GREEN (no blockers/failures), YELLOW (blockers present), RED (failures or >30% blocked)
"""

with open("$REPORT_FILE", "w") as f:
    f.write(report)

print(f"Report written to: $REPORT_FILE")
PYEOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  "$REPORT_FILE" \
  --description "Project status report for $(date +%Y-%m-%d)"
```

### 8. Notify Stakeholders (optional)

```bash
# Send summary to manager or lead agent
LEAD="${LEAD_AGENT:-manager}"

bash /home/shared/scripts/send-mail.sh "$LEAD" \
  --from "$(whoami)" \
  --subject "Status Report: $(date +%Y-%m-%d)" \
  -- "Status report generated and registered as artifact. Overall status: $(python3 -c "
import json
with open('/tmp/status-metrics.json') as f: print(json.load(f).get('rag', 'UNKNOWN'))
"). See: $REPORT_FILE"
```

## Quality Checklist

- [ ] Task board queried and all tasks accounted for
- [ ] Completion percentage computed from actual task data
- [ ] Blockers identified with specific dependency information
- [ ] Failed tasks listed with failure reasons
- [ ] Agent health checked (heartbeats, responsiveness)
- [ ] RAG status determined by objective criteria (not subjective)
- [ ] Progress broken down by owner/agent
- [ ] Risks and concerns listed with specific evidence
- [ ] Report written to shared workspace and registered as artifact
