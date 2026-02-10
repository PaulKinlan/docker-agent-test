---
name: data-analysis
description: Analyze data files and produce summary statistics with real commands
---

# Data Analysis

## When to Use

Use this skill when tasked with analyzing data files (CSV, JSON, JSONL, TSV, logs) to extract insights, compute statistics, or identify patterns.

## Procedure

### 1. Inspect the Data

```bash
DATA_FILE="${1:-/home/shared/data.csv}"

echo "=== File Info ==="
file "$DATA_FILE"
ls -lh "$DATA_FILE"

echo ""
echo "=== First 10 lines ==="
head -10 "$DATA_FILE"

echo ""
echo "=== Line count ==="
wc -l "$DATA_FILE"
```

**For CSV files:**
```bash
echo "=== Column count ==="
head -1 "$DATA_FILE" | awk -F',' '{print NF, "columns"}'

echo ""
echo "=== Headers ==="
head -1 "$DATA_FILE" | tr ',' '\n' | nl

echo ""
echo "=== Sample rows ==="
head -5 "$DATA_FILE" | column -t -s','
```

**For JSON files:**
```bash
echo "=== Structure ==="
jq 'if type == "array" then length, (.[0] | keys) else keys end' "$DATA_FILE"

echo ""
echo "=== Record count ==="
jq 'if type == "array" then length else 1 end' "$DATA_FILE"

echo ""
echo "=== First record ==="
jq 'if type == "array" then .[0] else . end' "$DATA_FILE"
```

**For JSONL files:**
```bash
echo "=== Record count ==="
wc -l "$DATA_FILE"

echo ""
echo "=== Fields ==="
head -1 "$DATA_FILE" | jq 'keys'

echo ""
echo "=== First 3 records ==="
head -3 "$DATA_FILE" | jq .
```

### 2. Validate Data Quality

```bash
echo "=== Data Quality Checks ==="

# Check for empty fields (CSV)
echo "--- Empty fields per column ---"
awk -F',' '
NR==1 { for(i=1;i<=NF;i++) header[i]=$i; next }
{
  for(i=1;i<=NF;i++) {
    if($i == "" || $i == "null" || $i == "NULL") empty[i]++
  }
  total++
}
END {
  for(i=1;i<=length(header);i++)
    if(empty[i]>0) printf "%s: %d empty (%.1f%%)\n", header[i], empty[i], empty[i]*100/total
}' "$DATA_FILE"

echo ""
echo "--- Duplicate rows ---"
sort "$DATA_FILE" | uniq -d | wc -l | xargs -I{} echo "{} duplicate rows"

echo ""
echo "--- Duplicate keys (first column) ---"
awk -F',' 'NR>1{print $1}' "$DATA_FILE" | sort | uniq -d | head -5
```

**For JSON:**
```bash
# Check for null values
echo "--- Null fields ---"
jq '[.[] | to_entries[] | select(.value == null) | .key] | group_by(.) | map({key: .[0], count: length})' "$DATA_FILE" 2>/dev/null

# Check for empty strings
echo "--- Empty strings ---"
jq '[.[] | to_entries[] | select(.value == "") | .key] | group_by(.) | map({key: .[0], count: length})' "$DATA_FILE" 2>/dev/null
```

### 3. Compute Summary Statistics

**Numeric columns (CSV with awk):**
```bash
# Specify the column number to analyze (1-indexed)
COL=3
HEADER=$(head -1 "$DATA_FILE" | cut -d',' -f$COL)

echo "=== Statistics for column $COL ($HEADER) ==="
awk -F',' -v col=$COL '
NR > 1 && $col != "" {
  n++
  sum += $col
  if(n==1 || $col < min) min = $col
  if(n==1 || $col > max) max = $col
  vals[n] = $col
}
END {
  if(n==0) { print "No numeric values"; exit }
  mean = sum/n
  # Sort for median
  for(i=1;i<=n;i++) sorted[i] = vals[i]
  for(i=1;i<=n;i++) for(j=i+1;j<=n;j++) if(sorted[i]>sorted[j]) { t=sorted[i]; sorted[i]=sorted[j]; sorted[j]=t }
  median = (n%2==1) ? sorted[int(n/2)+1] : (sorted[n/2]+sorted[n/2+1])/2
  printf "  Count:  %d\n  Sum:    %.2f\n  Mean:   %.2f\n  Median: %.2f\n  Min:    %.2f\n  Max:    %.2f\n", n, sum, mean, median, min, max
}' "$DATA_FILE"
```

**Categorical columns (CSV):**
```bash
COL=2
HEADER=$(head -1 "$DATA_FILE" | cut -d',' -f$COL)

echo "=== Value counts for column $COL ($HEADER) ==="
awk -F',' -v col=$COL 'NR>1{print $col}' "$DATA_FILE" \
  | sort | uniq -c | sort -rn | head -20
```

**JSON statistics:**
```bash
FIELD="amount"

echo "=== Statistics for field: $FIELD ==="
jq --arg f "$FIELD" '
  [.[] | .[$f] | select(. != null and type == "number")] |
  {
    count: length,
    sum: add,
    mean: (add / length),
    min: min,
    max: max,
    sorted: sort | {
      median: (if length % 2 == 1 then .[length/2 | floor] else (.[length/2 - 1] + .[length/2]) / 2 end)
    }
  } | {count, sum, mean, min, max, median: .sorted.median}
' "$DATA_FILE"
```

### 4. Complex Analysis with Python

For analysis beyond what awk/jq can do:

```bash
python3 <<'PYEOF'
import csv
import json
import sys
from collections import Counter
from statistics import mean, median, stdev

# CSV analysis
with open("/home/shared/data.csv") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

print(f"Records: {len(rows)}")
print(f"Fields: {list(rows[0].keys())}")

# Numeric field analysis
field = "amount"
values = [float(r[field]) for r in rows if r[field]]
print(f"\n{field}:")
print(f"  Count:  {len(values)}")
print(f"  Mean:   {mean(values):.2f}")
print(f"  Median: {median(values):.2f}")
print(f"  Stdev:  {stdev(values):.2f}")
print(f"  Min:    {min(values):.2f}")
print(f"  Max:    {max(values):.2f}")

# Categorical field distribution
field = "status"
counts = Counter(r[field] for r in rows)
print(f"\n{field} distribution:")
for val, count in counts.most_common(10):
    pct = count / len(rows) * 100
    print(f"  {val}: {count} ({pct:.1f}%)")
PYEOF
```

### 5. Write the Report

```bash
REPORT_FILE="/home/shared/analysis-$(date +%Y%m%d)-$(basename "$DATA_FILE" | sed 's/\..*//')\.md"

cat > "$REPORT_FILE" <<'EOF'
# Data Analysis Report

**Date:** YYYY-MM-DD
**Data Source:** [file path]
**Analyst:** [agent name]

## Data Overview
| Metric | Value |
|--------|-------|
| Records | N |
| Fields | N |
| File Size | N KB |
| Empty Values | N (N%) |
| Duplicates | N |

## Key Findings
1. [Most significant finding]
2. [Second finding]
3. [Third finding]

## Summary Statistics
| Field | Count | Mean | Median | Min | Max | Stdev |
|-------|-------|------|--------|-----|-----|-------|
| ... | ... | ... | ... | ... | ... | ... |

## Distributions
[Top values for categorical fields]

## Data Quality Issues
- [Issue 1]
- [Issue 2]

## Methodology
[Commands and tools used for analysis]
EOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "analysis-$(basename "$DATA_FILE" | sed 's/\..*//')" \
  --type "report" \
  --path "$REPORT_FILE" \
  --description "Data analysis of $DATA_FILE"
```

## Quality Checklist

- [ ] Data file inspected (format, size, structure, sample rows)
- [ ] Data quality validated (nulls, empties, duplicates)
- [ ] Summary statistics computed for all relevant numeric fields
- [ ] Distributions shown for categorical fields
- [ ] Methodology documented (exact commands used)
- [ ] Key findings are specific and supported by numbers
- [ ] Report written to shared workspace and registered as artifact
