---
name: literature-review
description: Review existing documents, reports, and references on a topic to synthesize findings and identify gaps
---

# Literature Review

## When to Use

Use this skill when tasked with reviewing a body of existing documents, reports, or references on a topic. The goal is to synthesize what is already known, identify themes and patterns across sources, and surface gaps where information is missing or contradictory.

Common scenarios:
- Reviewing all existing documentation before a project kickoff
- Synthesizing prior research reports to inform a new initiative
- Surveying internal knowledge bases on a topic before making recommendations
- Building an annotated bibliography for a decision-making process

This skill is about reading and synthesizing existing materials, not about generating new primary research.

## Output Template

```markdown
# Literature Review: [Topic]

**Date:** YYYY-MM-DD
**Reviewer:** [agent name]
**Scope:** [what was reviewed — directories, document types, date range]
**Documents Reviewed:** N

## Executive Summary
[3-5 sentences: what the body of literature collectively says about the topic, where there is consensus, and where gaps remain]

## Annotated Bibliography

### [Document 1 Title]
- **Path:** [file path]
- **Type:** [report/memo/spec/guide/analysis/reference]
- **Date:** [when written or last modified]
- **Author:** [if identifiable]
- **Summary:** [2-3 sentence summary of what this document contributes]
- **Key Claims:** [bulleted list of the main assertions]
- **Relevance:** [High/Medium/Low] — [why]

### [Document 2 Title]
...

## Theme Matrix

| Theme | Doc 1 | Doc 2 | Doc 3 | Doc 4 | Coverage |
|-------|-------|-------|-------|-------|----------|
| [theme A] | X | X | | X | 3/4 |
| [theme B] | X | | X | | 2/4 |
| [theme C] | | | X | X | 2/4 |

## Synthesis Narrative

### [Theme A]: [Descriptive Title]
[What the documents collectively say about this theme. Cite specific documents. Note where they agree and where they diverge.]

### [Theme B]: [Descriptive Title]
...

## Gap Analysis
| Gap | Description | Impact | Recommendation |
|-----|-------------|--------|----------------|
| [gap 1] | [what is missing] | [why it matters] | [how to fill it] |
| [gap 2] | ... | ... | ... |

## Contradictions
| Topic | Source A Says | Source B Says | Assessment |
|-------|-------------|-------------|------------|
| [topic] | [claim] (Doc N) | [contrary claim] (Doc M) | [which is more credible and why] |

## Sources Reviewed
| # | Document | Path | Type | Date | Relevance |
|---|----------|------|------|------|-----------|
| 1 | [title] | [path] | [type] | [date] | [H/M/L] |
```

## Procedure

### 1. Define Review Scope

```bash
# Read the task for topic and scope
TASK_ID="$1"
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'
```

Before reading any documents, write down:
- **Topic:** The subject of the review
- **Scope boundaries:** What types of documents to include/exclude
- **Questions to answer:** What should this review tell us when complete?

### 2. Collect All Candidate Documents

```bash
TOPIC="$2"  # e.g., "authentication" or "migration-plan"

# Find all documents that mention the topic
echo "=== Documents mentioning '$TOPIC' ==="
rg -l -i "$TOPIC" /home/shared/ ~/workspace/ 2>/dev/null \
  | grep -E '\.(md|txt|csv|json|yaml|yml|pdf|html|rst|adoc)$' \
  | sort

# Find documents by filename
echo ""
echo "=== Documents with '$TOPIC' in filename ==="
find /home/shared/ ~/workspace/ -type f \
  -iname "*${TOPIC}*" 2>/dev/null | sort

# Find all reports and research documents
echo ""
echo "=== All reports in shared workspace ==="
find /home/shared/ -name '*.md' -type f 2>/dev/null | sort

# Check artifact registry for relevant prior work
echo ""
echo "=== Registered artifacts ==="
bash /home/shared/scripts/artifact.sh list 2>/dev/null \
  | jq -r '.[] | "\(.name) — \(.type) — \(.path)"' 2>/dev/null
```

Build a candidate list:

```bash
# Create a manifest of documents to review
REVIEW_DIR="/tmp/literature-review"
mkdir -p "$REVIEW_DIR"

# Collect all candidate file paths
rg -l -i "$TOPIC" /home/shared/ ~/workspace/ 2>/dev/null \
  | grep -E '\.(md|txt|csv|json|yaml)$' \
  > "$REVIEW_DIR/candidates.txt"

echo "Candidate documents: $(wc -l < "$REVIEW_DIR/candidates.txt")"
cat "$REVIEW_DIR/candidates.txt"
```

### 3. Triage and Prioritize

Not all documents deserve equal attention. Triage first:

```bash
# For each candidate, get size and a preview to assess relevance
while IFS= read -r filepath; do
  echo "=== $(basename "$filepath") ==="
  echo "Path: $filepath"
  echo "Size: $(wc -c < "$filepath") bytes, $(wc -l < "$filepath") lines"
  echo "Modified: $(stat -c '%y' "$filepath" 2>/dev/null || stat -f '%Sm' "$filepath" 2>/dev/null)"
  echo "Preview:"
  head -15 "$filepath"
  echo ""
  echo "---"
done < "$REVIEW_DIR/candidates.txt"
```

Assign each document a relevance tier:
- **Tier 1 (must read):** Directly addresses the topic, from authoritative source
- **Tier 2 (should read):** Partially relevant or provides useful context
- **Tier 3 (skim only):** Tangentially related, read only if time permits

### 4. Read and Annotate Each Document

For each Tier 1 and Tier 2 document:

```bash
DOC_PATH="/home/shared/some-document.md"
DOC_NAME="$(basename "$DOC_PATH")"

# Read the full document
cat "$DOC_PATH"

# Extract headings to understand structure
grep -E '^#{1,3} ' "$DOC_PATH"

# Find key claims — sentences with strong assertion language
rg -n 'must|should|recommend|require|critical|essential|conclude|found that' \
  "$DOC_PATH" -i | head -20
```

Create an annotation entry:

```bash
cat >> "$REVIEW_DIR/annotations.md" <<EOF

### $(basename "$DOC_PATH")
- **Path:** $DOC_PATH
- **Type:** [report/memo/spec/guide/analysis]
- **Date:** $(stat -c '%y' "$DOC_PATH" 2>/dev/null | cut -d' ' -f1 || stat -f '%Sm' -t '%Y-%m-%d' "$DOC_PATH" 2>/dev/null)
- **Summary:** [2-3 sentences]
- **Key Claims:**
  - [claim 1]
  - [claim 2]
- **Relevance:** [High/Medium/Low]
EOF
```

### 5. Extract Themes Across Documents

```bash
# Identify recurring terms and concepts across all documents
echo "=== Recurring Terms ==="
cat "$REVIEW_DIR/candidates.txt" | xargs cat 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs '[:alpha:]' '\n' \
  | sort | uniq -c | sort -rn \
  | grep -v -E '^[[:space:]]+(the|and|is|of|to|in|a|for|that|with|this|it|on|are|be|as|was|from|or|an|by|at|not|but|has|have|had|which|will|can|been|would|their|they|all|its|may|more|also|into|than|any|each|only|these|our|such|other|some|new|when|about|could|no|should)$' \
  | head -30

# Find terms that appear in multiple documents
echo ""
echo "=== Cross-Document Terms ==="
while IFS= read -r filepath; do
  basename "$filepath"
  rg -oN '\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b' "$filepath" 2>/dev/null | sort -u | head -10
  echo "---"
done < "$REVIEW_DIR/candidates.txt"
```

Build the theme matrix:

```bash
# Create theme matrix as CSV
THEMES_FILE="$REVIEW_DIR/theme-matrix.csv"
echo "theme,$(cat "$REVIEW_DIR/candidates.txt" | xargs -I{} basename {} | tr '\n' ',' | sed 's/,$//')" > "$THEMES_FILE"

# For each theme, check which documents mention it
THEMES=("theme_a" "theme_b" "theme_c")
for theme in "${THEMES[@]}"; do
  ROW="$theme"
  while IFS= read -r filepath; do
    if rg -qi "$theme" "$filepath" 2>/dev/null; then
      ROW="${ROW},X"
    else
      ROW="${ROW},"
    fi
  done < "$REVIEW_DIR/candidates.txt"
  echo "$ROW" >> "$THEMES_FILE"
done

column -t -s',' "$THEMES_FILE"
```

### 6. Identify Gaps and Contradictions

```bash
# Check for contradictions — same topic, different claims
echo "=== Potential Contradictions ==="

# Find documents that discuss the same subtopic differently
SUBTOPICS=("performance" "security" "scalability" "cost")
for subtopic in "${SUBTOPICS[@]}"; do
  FILES=$(rg -l -i "$subtopic" "$REVIEW_DIR/candidates.txt" 2>/dev/null | head -5)
  if [ $(echo "$FILES" | wc -l) -gt 1 ]; then
    echo "--- $subtopic mentioned in multiple docs ---"
    for f in $FILES; do
      echo "  $f:"
      rg -i "$subtopic" "$f" | head -3
    done
  fi
done
```

Gaps are topics you expected to find but did not:

```bash
# Check for expected topics that are NOT covered
EXPECTED_TOPICS=("implementation" "timeline" "budget" "risks" "alternatives")
echo "=== Gap Check ==="
for topic in "${EXPECTED_TOPICS[@]}"; do
  COUNT=$(cat "$REVIEW_DIR/candidates.txt" | xargs rg -li "$topic" 2>/dev/null | wc -l)
  if [ "$COUNT" -eq 0 ]; then
    echo "GAP: '$topic' — not found in any reviewed document"
  else
    echo "OK:  '$topic' — found in $COUNT document(s)"
  fi
done
```

### 7. Write the Review

```bash
REPORT_FILE="/home/shared/literature-review-$(date +%Y%m%d)-${TOPIC}.md"

cat > "$REPORT_FILE" <<'REPORT'
# Literature Review: [Topic]

**Date:** YYYY-MM-DD
**Reviewer:** [agent name]
**Scope:** [directories and document types reviewed]
**Documents Reviewed:** N

## Executive Summary

[What the body of literature collectively says. Where there is consensus. Where there are gaps.]

## Annotated Bibliography

### [Document 1]
- **Path:** [path]
- **Type:** [type]
- **Date:** [date]
- **Summary:** [what this document contributes]
- **Key Claims:** [main assertions]
- **Relevance:** [H/M/L]

### [Document 2]
...

## Theme Matrix

| Theme | Doc 1 | Doc 2 | Doc 3 | Coverage |
|-------|-------|-------|-------|----------|
| [theme] | X | X | | 2/3 |

## Synthesis Narrative

### [Theme A]
[What documents collectively say about this theme, citing specific sources]

### [Theme B]
...

## Gap Analysis

| Gap | Description | Impact | Recommendation |
|-----|-------------|--------|----------------|
| [gap] | [what is missing] | [why it matters] | [how to fill it] |

## Contradictions

| Topic | Source A Says | Source B Says | Assessment |
|-------|-------------|-------------|------------|
| [topic] | [claim] | [contrary claim] | [resolution] |

## Sources Reviewed

| # | Document | Path | Type | Date | Relevance |
|---|----------|------|------|------|-----------|
| 1 | [title] | [path] | [type] | [date] | [H/M/L] |
REPORT

echo "Review written to: $REPORT_FILE"
```

### 8. Register and Notify

```bash
bash /home/shared/scripts/artifact.sh register \
  --name "literature-review-${TOPIC}" \
  --type "research" \
  --path "$REPORT_FILE" \
  --description "Literature review on ${TOPIC} covering N documents"

# Notify the requesting agent
bash /home/shared/scripts/send-mail.sh \
  --to "$REQUESTING_AGENT" \
  --subject "Literature review complete: ${TOPIC}" \
  --body "Review of N documents available at: $REPORT_FILE"
```

## Quality Checklist

- [ ] All relevant documents in the workspace were found and considered
- [ ] Each document has an annotation entry (summary, key claims, relevance)
- [ ] Theme matrix shows which themes appear in which documents
- [ ] Synthesis narrative cites specific documents, not vague references
- [ ] Gaps are identified with concrete impact and recommendations to fill them
- [ ] Contradictions between sources are documented with an assessment of which is more credible
- [ ] Executive summary accurately reflects the collective findings
- [ ] Review scope and boundaries are clearly stated (what was and was not included)
- [ ] Report is registered as an artifact in the shared workspace
