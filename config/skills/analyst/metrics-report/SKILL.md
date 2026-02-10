---
name: metrics-report
description: Produce a formatted metrics report with key indicators, trends, and recommendations
---

# Metrics Report

## When to Use

Use this skill when tasked with producing a metrics report, dashboard summary, or performance assessment with quantitative data.

## Output Template

```markdown
# Metrics Report: [Subject]

**Period:** [start date] to [end date]
**Author:** [agent name]
**Date:** YYYY-MM-DD

## Key Metrics

| Metric | Value | Previous | Change | Status |
|--------|-------|----------|--------|--------|
| [name] | [current] | [prior period] | [+/-N%] | [up/down/stable] |

## Trends
[Analysis of patterns over time]

## Recommendations
1. **[Action]** — because [metric] shows [specific value/trend]
2. **[Action]** — because [metric] shows [specific value/trend]
```

## Procedure

### 1. Collect Raw Data

**From task board:**
```bash
echo "=== Task Metrics ==="
# Total tasks by status
bash /home/shared/scripts/task.sh list 2>/dev/null | jq '
  group_by(.status) | map({status: .[0].status, count: length})
' 2>/dev/null

# Tasks completed per agent
bash /home/shared/scripts/task.sh list --status completed 2>/dev/null | jq '
  group_by(.owner) | map({owner: .[0].owner, completed: length})
' 2>/dev/null

# Average time to completion (if timestamps available)
bash /home/shared/scripts/task.sh list --status completed 2>/dev/null | jq '
  [.[] | select(.created_at and .completed_at) |
    ((.completed_at | split("T")[0] | split("-") | .[2] | tonumber) -
     (.created_at | split("T")[0] | split("-") | .[2] | tonumber))
  ] | if length > 0 then {avg_days: (add/length), count: length} else "no timing data" end
' 2>/dev/null
```

**From log files:**
```bash
echo "=== Log Metrics ==="
LOG_DIR="${1:-/var/log}"

# Error rate
TOTAL=$(wc -l "$LOG_DIR"/*.log 2>/dev/null | tail -1 | awk '{print $1}')
ERRORS=$(grep -ci 'error\|fail\|exception' "$LOG_DIR"/*.log 2>/dev/null | awk -F: '{sum+=$2}END{print sum}')
echo "Total log lines: $TOTAL"
echo "Error lines: $ERRORS"
[ "$TOTAL" -gt 0 ] && echo "Error rate: $(echo "scale=2; $ERRORS * 100 / $TOTAL" | bc)%"
```

**From system metrics:**
```bash
echo "=== System Metrics ==="
# Disk usage
df -h / 2>/dev/null | awk 'NR==2{print "Disk used:", $3, "of", $2, "("$5")"}'

# Process count
ps aux 2>/dev/null | wc -l | xargs -I{} echo "Running processes: {}"

# Memory (Linux)
free -h 2>/dev/null | awk '/^Mem:/{print "Memory used:", $3, "of", $2}'
```

**From git history:**
```bash
cd ~/workspace 2>/dev/null

echo "=== Development Metrics ==="
# Commits per day (last 7 days)
for i in $(seq 0 6); do
  DATE=$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d 2>/dev/null)
  COUNT=$(git log --oneline --after="$DATE 00:00" --before="$DATE 23:59" 2>/dev/null | wc -l | tr -d ' ')
  echo "  $DATE: $COUNT commits"
done

# Lines changed (last 7 days)
git diff --shortstat "HEAD@{7 days ago}" HEAD 2>/dev/null
```

### 2. Compute Metrics

For each metric, compute:
- **Current value** (this period)
- **Previous value** (prior period for comparison)
- **Change** (absolute and percentage)
- **Status** (improving, declining, stable)

```bash
# Example: compute change
CURRENT=42
PREVIOUS=38

if [ "$PREVIOUS" -gt 0 ]; then
  CHANGE=$(echo "scale=1; ($CURRENT - $PREVIOUS) * 100 / $PREVIOUS" | bc)
  echo "Change: ${CHANGE}%"
  if [ "$(echo "$CHANGE > 5" | bc)" -eq 1 ]; then
    STATUS="up"
  elif [ "$(echo "$CHANGE < -5" | bc)" -eq 1 ]; then
    STATUS="down"
  else
    STATUS="stable"
  fi
  echo "Status: $STATUS"
fi
```

### 3. Compare to Baselines

If baselines exist:

```bash
BASELINE_FILE="/home/shared/metrics-baseline.json"

if [ -f "$BASELINE_FILE" ]; then
  echo "=== Baseline Comparison ==="
  jq -r 'to_entries[] | "\(.key): \(.value)"' "$BASELINE_FILE"
else
  echo "No baseline found — current values will become the baseline"
fi
```

### 4. Present Numbers First, Then Interpretation

Rules for metrics presentation:
- Lead with the number, not the interpretation
- Always include units (%, ms, count, MB)
- Show direction of change with +/- prefix
- Use conditional formatting: mark concerning metrics

### 5. Tie Recommendations to Metrics

Every recommendation must reference a specific metric:

| Pattern | Recommendation Template |
|---------|------------------------|
| Error rate increasing | "Reduce error rate (currently N%) by [specific action]" |
| Task throughput decreasing | "Increase task completion rate (N/week, down from M) by [action]" |
| Resource usage high | "Address disk usage (N% full) by [action] before reaching capacity" |
| Metric missing data | "Instrument [component] to collect [metric] for visibility" |

### 6. Write the Report

```bash
REPORT_FILE="/home/shared/metrics-report-$(date +%Y%m%d).md"

cat > "$REPORT_FILE" <<'EOF'
# Metrics Report: [Subject]

**Period:** YYYY-MM-DD to YYYY-MM-DD
**Author:** [agent name]
**Date:** YYYY-MM-DD

## Key Metrics

| Metric | Value | Previous | Change | Status |
|--------|-------|----------|--------|--------|
| Tasks completed | N | N | +N% | up |
| Error rate | N% | N% | -N% | down (good) |
| Avg completion time | Nh | Nh | +Nh | up (bad) |

## Trends
- [Trend 1: what is happening over time and why it matters]
- [Trend 2]

## Detailed Breakdown

### [Metric Category 1]
| Sub-metric | Value | Notes |
|------------|-------|-------|
| ... | ... | ... |

### [Metric Category 2]
...

## Recommendations
1. **[Specific action]** — [metric] is at [value], which indicates [interpretation]. [Action] would improve this to approximately [target].
2. **[Specific action]** — [metric] shows [trend], suggesting [interpretation].

## Data Sources
- [Source 1: path/command used]
- [Source 2: path/command used]
EOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "metrics-report" \
  --type "report" \
  --path "$REPORT_FILE" \
  --description "Metrics report for $(date +%Y-%m-%d)"
```

## Quality Checklist

- [ ] All relevant metrics collected from available data sources
- [ ] Each metric has current value, previous value, change, and status
- [ ] Units are included for every number
- [ ] Trends are identified from multi-period data
- [ ] Every recommendation references a specific metric and value
- [ ] Recommendations include expected outcome if acted upon
- [ ] Data sources are documented for reproducibility
- [ ] Report is written to shared workspace and registered as artifact
