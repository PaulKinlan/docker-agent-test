---
name: fact-checking
description: Verify factual claims in a document against available evidence, producing an annotated report
---

# Fact-Checking

## When to Use

Use this skill when you need to verify the accuracy of claims and assertions in a document before it is published, shared, or used as a basis for decisions. This applies to research reports, design documents, status updates, incident summaries, analysis findings, or any deliverable that contains factual statements. The goal is to systematically identify every checkable claim, verify it against available evidence, and produce a clear report of what is confirmed, what is unsupported, and what is contradicted.

## Claim Verdicts

| Verdict | Meaning | Action |
|---------|---------|--------|
| **Confirmed** | Claim is supported by at least one reliable source | No change needed |
| **Unconfirmed** | No evidence found to support or refute the claim | Flag for author -- add source or soften language |
| **Contradicted** | Available evidence directly contradicts the claim | Must be corrected before publication |
| **Modified** | Claim is partially correct but needs qualification | Suggest revised wording |
| **Opinion** | Statement is subjective -- not a factual claim | Mark as opinion if presented as fact |
| **Projection** | Forward-looking statement that cannot be verified now | Mark as projection if presented as fact |

## Output: Fact-Check Report

```markdown
# Fact-Check Report

**Document:** [document name and path]
**Checked by:** [agent name]
**Date:** [YYYY-MM-DD]

## Summary Statistics
| Metric | Count |
|--------|-------|
| Total claims extracted | N |
| Verifiable claims | N |
| Confirmed | N |
| Modified | N |
| Unconfirmed | N |
| Contradicted | N |
| Opinions/Projections (not checked) | N |

**Overall Reliability:** [High / Medium / Low / Unreliable]

## Claim Register

| # | Claim | Location | Type | Verdict | Evidence | Notes |
|---|-------|----------|------|---------|----------|-------|
| 1 | [quoted claim] | Line N | Verifiable | Confirmed | [source] | |
| 2 | [quoted claim] | Line N | Verifiable | Contradicted | [source shows X] | Must correct |
| 3 | [quoted claim] | Line N | Opinion | N/A | | Presented as fact |

## Detailed Findings

### Claim 1: [quoted claim]
- **Location:** Line N, Section "[heading]"
- **Type:** Verifiable
- **Verdict:** Confirmed
- **Evidence:** [what was found and where]
- **Action:** None

### Claim 2: [quoted claim]
- **Location:** Line N, Section "[heading]"
- **Type:** Verifiable
- **Verdict:** Contradicted
- **Evidence:** [what was found and where, showing contradiction]
- **Action:** Correct to "[suggested replacement]"

## Annotated Document
[Full document with inline annotations marking each claim's verdict]
```

## Procedure

### 1. Read the Document

```bash
DOC_FILE="${1:-/home/shared/document.md}"

if [ ! -f "$DOC_FILE" ]; then
  echo "ERROR: Document not found at $DOC_FILE"
  exit 1
fi

# Read the full document
cat "$DOC_FILE"

# Get basic stats
echo ""
echo "=== Document Stats ==="
wc -l "$DOC_FILE" | awk '{print "Lines:", $1}'
wc -w "$DOC_FILE" | awk '{print "Words:", $1}'

# Number the lines for reference
nl -ba "$DOC_FILE" > /tmp/doc-numbered.txt
echo "Numbered version saved to /tmp/doc-numbered.txt"
```

### 2. Extract All Factual Claims

Go through the document line by line and extract every statement that makes a factual assertion:

```bash
CLAIMS_FILE="/tmp/claims-register.jsonl"
> "$CLAIMS_FILE"

# Helper: add a claim to the register
add_claim() {
  local num="$1"
  local line="$2"
  local claim="$3"
  local type="$4"  # verifiable, opinion, projection

  jq -n \
    --arg num "$num" \
    --arg line "$line" \
    --arg claim "$claim" \
    --arg type "$type" \
    --arg verdict "pending" \
    --arg evidence "" \
    --arg notes "" \
    '{num: $num, line: $line, claim: $claim, type: $type, verdict: $verdict, evidence: $evidence, notes: $notes}' \
    >> "$CLAIMS_FILE"
}

# Example: extract claims (in practice, read through the document and call add_claim for each)
# add_claim "1" "12" "The system processes 10,000 requests per second" "verifiable"
# add_claim "2" "15" "This approach is better than the alternative" "opinion"
# add_claim "3" "23" "Usage will double by Q3" "projection"

echo "Claims extracted to: $CLAIMS_FILE"
jq -s 'length' "$CLAIMS_FILE"
echo "total claims"
```

Identify claims by looking for:
- Numbers, statistics, measurements ("10,000 requests", "99.9% uptime", "3x faster")
- Causal statements ("X causes Y", "X leads to Y", "because of X")
- Comparisons ("faster than", "more reliable than", "unlike X")
- Existence claims ("there are N", "X contains Y", "X supports Z")
- Temporal claims ("since 2023", "before the migration", "always")
- Attribution ("according to", "X recommends", "the standard requires")

### 3. Classify Each Claim

```bash
# Read claims and classify
jq -c '.' "$CLAIMS_FILE" | while read claim_json; do
  CLAIM_TEXT=$(echo "$claim_json" | jq -r '.claim')
  CLAIM_LOWER=$(echo "$CLAIM_TEXT" | tr '[:upper:]' '[:lower:]')

  # Classify type
  TYPE="verifiable"  # default

  # Opinion indicators
  if echo "$CLAIM_LOWER" | grep -qE '\b(better|worse|best|worst|should|ideal|prefer|recommend|believe|think|feel|obvious|clearly)\b'; then
    TYPE="opinion"
  fi

  # Projection indicators
  if echo "$CLAIM_LOWER" | grep -qE '\b(will|would|expect|predict|forecast|project|estimate.*future|by (q[1-4]|20[2-9][0-9]|next))\b'; then
    TYPE="projection"
  fi

  echo "Claim: $CLAIM_TEXT"
  echo "  Type: $TYPE"
done
```

### 4. Verify Each Verifiable Claim

For each verifiable claim, search available sources:

```bash
verify_claim() {
  local claim_num="$1"
  local claim_text="$2"

  echo "=== Verifying claim $claim_num: $claim_text ==="

  # Extract key terms for searching
  KEY_TERMS=$(echo "$claim_text" | tr '[:upper:]' '[:lower:]' \
    | grep -oE '[a-z]{4,}' \
    | grep -vE '^(that|this|with|from|have|been|were|will|would|does|than|more|less|also|each|into|only)$' \
    | sort -u | head -5 | tr '\n' '|' | sed 's/|$//')

  echo "  Search terms: $KEY_TERMS"

  # Search shared files for evidence
  echo "  --- Shared files ---"
  rg -l "$KEY_TERMS" /home/shared/ 2>/dev/null | head -10

  # Search with context to see what the sources actually say
  rg -C2 "$KEY_TERMS" /home/shared/ 2>/dev/null | head -30

  # Check data files for numerical claims
  if echo "$claim_text" | grep -qE '[0-9]'; then
    echo "  --- Numerical check ---"
    NUMBERS=$(echo "$claim_text" | grep -oE '[0-9][0-9,.]*')
    for num in $NUMBERS; do
      echo "  Looking for number: $num"
      rg "$num" /home/shared/ 2>/dev/null | head -5
    done
  fi

  # Check task board for process/status claims
  echo "  --- Task board ---"
  bash /home/shared/scripts/task.sh list 2>/dev/null | jq -r '.[].subject' \
    | grep -iE "$KEY_TERMS" 2>/dev/null | head -5

  # Check artifacts for referenced outputs
  echo "  --- Artifacts ---"
  bash /home/shared/scripts/artifact.sh list 2>/dev/null | jq -r '.[].name' \
    | grep -iE "$KEY_TERMS" 2>/dev/null | head -5
}

# Run verification for each verifiable claim
jq -c 'select(.type == "verifiable")' "$CLAIMS_FILE" | while read claim_json; do
  NUM=$(echo "$claim_json" | jq -r '.num')
  TEXT=$(echo "$claim_json" | jq -r '.claim')
  verify_claim "$NUM" "$TEXT"
  echo ""
done
```

### 5. Record Verdicts

Update the claims register with findings:

```bash
# Update a claim's verdict and evidence
update_verdict() {
  local claim_num="$1"
  local verdict="$2"     # confirmed, unconfirmed, contradicted, modified
  local evidence="$3"
  local notes="$4"

  # Read existing claims, update the matching one, write back
  jq -c "if .num == \"$claim_num\" then .verdict = \"$verdict\" | .evidence = \"$evidence\" | .notes = \"$notes\" else . end" \
    "$CLAIMS_FILE" > /tmp/claims-updated.jsonl
  mv /tmp/claims-updated.jsonl "$CLAIMS_FILE"

  echo "Claim $claim_num: $verdict"
}

# Examples:
# update_verdict "1" "confirmed" "Found in /home/shared/metrics.json line 42" ""
# update_verdict "2" "contradicted" "/home/shared/report.md says 5,000 not 10,000" "Must correct"
# update_verdict "3" "unconfirmed" "No supporting evidence found in available files" "Author should cite source"
# update_verdict "4" "modified" "Partially correct but missing qualifier" "Should say 'up to 10,000' not '10,000'"
```

### 6. Compute Summary Statistics

```bash
echo "=== Fact-Check Summary ==="

TOTAL=$(jq -s 'length' "$CLAIMS_FILE")
VERIFIABLE=$(jq -s '[.[] | select(.type == "verifiable")] | length' "$CLAIMS_FILE")
CONFIRMED=$(jq -s '[.[] | select(.verdict == "confirmed")] | length' "$CLAIMS_FILE")
MODIFIED=$(jq -s '[.[] | select(.verdict == "modified")] | length' "$CLAIMS_FILE")
UNCONFIRMED=$(jq -s '[.[] | select(.verdict == "unconfirmed")] | length' "$CLAIMS_FILE")
CONTRADICTED=$(jq -s '[.[] | select(.verdict == "contradicted")] | length' "$CLAIMS_FILE")
NOT_CHECKED=$(jq -s '[.[] | select(.type != "verifiable")] | length' "$CLAIMS_FILE")

echo "Total claims:       $TOTAL"
echo "Verifiable:         $VERIFIABLE"
echo "  Confirmed:        $CONFIRMED"
echo "  Modified:         $MODIFIED"
echo "  Unconfirmed:      $UNCONFIRMED"
echo "  Contradicted:     $CONTRADICTED"
echo "Not checked:        $NOT_CHECKED (opinions/projections)"

# Determine overall reliability
if [ "$VERIFIABLE" -eq 0 ]; then
  RELIABILITY="N/A -- no verifiable claims"
elif [ "$CONTRADICTED" -gt 0 ]; then
  RELIABILITY="Unreliable -- $CONTRADICTED claim(s) contradicted by evidence"
elif [ "$UNCONFIRMED" -gt $(( VERIFIABLE / 2 )) ]; then
  RELIABILITY="Low -- majority of claims lack supporting evidence"
elif [ "$UNCONFIRMED" -gt 0 ] || [ "$MODIFIED" -gt 0 ]; then
  RELIABILITY="Medium -- some claims need sources or correction"
else
  RELIABILITY="High -- all verifiable claims confirmed"
fi

echo "Overall reliability: $RELIABILITY"
```

### 7. Produce the Annotated Document

Create a version of the original document with inline annotations:

```bash
ANNOTATED_FILE="/tmp/doc-annotated.md"
cp "$DOC_FILE" "$ANNOTATED_FILE"

# For each claim with a non-confirmed verdict, insert an annotation
jq -c 'select(.verdict != "confirmed" and .verdict != "pending" and .type == "verifiable")' "$CLAIMS_FILE" \
  | sort -t'"' -k4 -rn \
  | while read claim_json; do
    LINE=$(echo "$claim_json" | jq -r '.line')
    VERDICT=$(echo "$claim_json" | jq -r '.verdict')
    NOTES=$(echo "$claim_json" | jq -r '.notes')
    CLAIM=$(echo "$claim_json" | jq -r '.claim' | head -c 80)

    # Create annotation marker
    case "$VERDICT" in
      contradicted) MARKER="[CONTRADICTED: $NOTES]" ;;
      unconfirmed)  MARKER="[UNCONFIRMED: no supporting evidence found]" ;;
      modified)     MARKER="[NEEDS CORRECTION: $NOTES]" ;;
    esac

    # Insert annotation after the relevant line
    sed -i "${LINE}s/$/ <!-- FACT-CHECK: ${VERDICT^^} -->/" "$ANNOTATED_FILE" 2>/dev/null

    echo "Annotated line $LINE: $VERDICT"
done

echo "Annotated document: $ANNOTATED_FILE"
```

### 8. Write the Full Report

```bash
REPORT_FILE="/home/shared/fact-check-$(date +%Y%m%d)-$(basename "$DOC_FILE" .md).md"
TIMESTAMP=$(date +%Y-%m-%d)
AGENT_NAME=$(whoami)

cat > "$REPORT_FILE" <<EOF
# Fact-Check Report

**Document:** $(basename "$DOC_FILE") ($DOC_FILE)
**Checked by:** ${AGENT_NAME}
**Date:** ${TIMESTAMP}

## Summary Statistics
| Metric | Count |
|--------|-------|
| Total claims extracted | ${TOTAL} |
| Verifiable claims | ${VERIFIABLE} |
| Confirmed | ${CONFIRMED} |
| Modified | ${MODIFIED} |
| Unconfirmed | ${UNCONFIRMED} |
| Contradicted | ${CONTRADICTED} |
| Opinions/Projections (not checked) | ${NOT_CHECKED} |

**Overall Reliability:** ${RELIABILITY}

## Claim Register

| # | Claim | Line | Type | Verdict | Evidence | Notes |
|---|-------|------|------|---------|----------|-------|
EOF

# Append each claim as a table row
jq -r '[.num, .claim[0:60], .line, .type, .verdict, .evidence[0:40], .notes[0:30]] | join(" | ")' \
  "$CLAIMS_FILE" | while read row; do
  echo "| $row |" >> "$REPORT_FILE"
done

cat >> "$REPORT_FILE" <<'EOF'

## Detailed Findings

EOF

# Append detailed findings for non-confirmed claims
jq -c 'select(.verdict != "confirmed" and .type == "verifiable")' "$CLAIMS_FILE" | while read claim_json; do
  NUM=$(echo "$claim_json" | jq -r '.num')
  CLAIM=$(echo "$claim_json" | jq -r '.claim')
  LINE=$(echo "$claim_json" | jq -r '.line')
  VERDICT=$(echo "$claim_json" | jq -r '.verdict')
  EVIDENCE=$(echo "$claim_json" | jq -r '.evidence')
  NOTES=$(echo "$claim_json" | jq -r '.notes')

  cat >> "$REPORT_FILE" <<EOF
### Claim ${NUM}: "${CLAIM}"
- **Location:** Line ${LINE}
- **Verdict:** ${VERDICT^}
- **Evidence:** ${EVIDENCE}
- **Action:** ${NOTES:-Review and update}

EOF
done

# Append the annotated document
cat >> "$REPORT_FILE" <<EOF
## Annotated Document

Below is the original document with fact-check annotations inline.
Claims marked with \`<!-- FACT-CHECK: VERDICT -->\` require attention.

\`\`\`
$(cat "$ANNOTATED_FILE")
\`\`\`
EOF

echo "Report written to: $REPORT_FILE"
```

### 9. Register and Notify

```bash
# Register the report as an artifact
bash /home/shared/scripts/artifact.sh register \
  --name "fact-check-$(basename "$DOC_FILE" .md)" \
  --type "fact-check" \
  --path "$REPORT_FILE" \
  --description "Fact-check report for $(basename "$DOC_FILE"): $CONFIRMED confirmed, $CONTRADICTED contradicted, $UNCONFIRMED unconfirmed"

# Notify the document author or requester
TASK_ID="${2:-}"
if [ -n "$TASK_ID" ]; then
  OWNER=$(bash /home/shared/scripts/task.sh get "$TASK_ID" 2>/dev/null | jq -r '.owner // "manager"')
  bash /home/shared/scripts/send-mail.sh "$OWNER" <<EOF
Fact-check complete for: $(basename "$DOC_FILE")

Results: $CONFIRMED confirmed, $MODIFIED need correction, $UNCONFIRMED lack evidence, $CONTRADICTED contradicted
Overall reliability: $RELIABILITY

Full report: $REPORT_FILE

$(if [ "$CONTRADICTED" -gt 0 ]; then
  echo "ACTION REQUIRED: $CONTRADICTED claim(s) are contradicted by available evidence and must be corrected."
fi)
$(if [ "$UNCONFIRMED" -gt 0 ]; then
  echo "RECOMMENDATION: $UNCONFIRMED claim(s) have no supporting evidence. Consider adding sources or softening language."
fi)
EOF
fi

echo "Notifications sent."
```

### 10. Update Task

```bash
if [ -n "$TASK_ID" ]; then
  bash /home/shared/scripts/task.sh update "$TASK_ID" \
    --status completed \
    --result "Fact-check complete: $TOTAL claims, $CONFIRMED confirmed, $CONTRADICTED contradicted. Report: $REPORT_FILE"
fi
```

## Quality Checklist

- [ ] Every factual statement in the document was extracted (not just obvious numbers)
- [ ] Each claim is classified as verifiable, opinion, or projection
- [ ] Opinions and projections presented as facts are flagged
- [ ] Every verifiable claim was checked against available sources
- [ ] Evidence is cited with specific file paths, line numbers, or data points
- [ ] Verdicts use the standard vocabulary: confirmed, unconfirmed, contradicted, modified
- [ ] Contradicted claims include the correct information from the source
- [ ] Summary statistics are accurate and match the detailed register
- [ ] Overall reliability rating is justified by the numbers
- [ ] Annotated document clearly marks claims that need attention
- [ ] The report is actionable: the author knows exactly what to fix
- [ ] Report is registered as an artifact and requester is notified
