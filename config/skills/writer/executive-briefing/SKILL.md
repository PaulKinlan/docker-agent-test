---
name: executive-briefing
description: Write concise executive summaries and status briefings using BLUF format for leadership audiences
---

# Executive Briefing

## When to Use

Use this skill when tasked with writing executive summaries, status briefings, decision memos, or any document intended for senior leadership or time-constrained decision-makers. The defining characteristic is brevity: 1-2 pages maximum, conclusions first, data over adjectives.

Common scenarios:
- Summarizing a longer report or analysis for leadership consumption
- Writing a weekly/monthly status update for stakeholders
- Preparing a decision memo that presents options and a recommendation
- Briefing a new stakeholder on the current state of an initiative

## Principles

1. **BLUF: Bottom Line Up Front.** The first sentence of the document must contain the conclusion or recommendation. If the reader stops after one sentence, they should still know what matters.
2. **1-2 pages maximum.** If it is longer, it is not an executive briefing. Cut ruthlessly.
3. **Data, not adjectives.** "Revenue increased 12% QoQ" not "Revenue performed strongly." "3 of 5 milestones complete" not "The project is going well."
4. **Three to five key points.** If you cannot distill it to 3-5 points, you do not understand it well enough. Executives scan, not read.
5. **Explicit ask.** End with what you need from the reader: a decision, awareness, or action. Never leave this ambiguous.

## Output Template

```markdown
# [Briefing Title]

**Date:** YYYY-MM-DD
**Author:** [agent name]
**Classification:** [For Decision | For Information | For Action]
**Audience:** [who this is for]

## Bottom Line

[ONE sentence: the most important thing the reader needs to know. This is the conclusion, not the introduction.]

## Situation

[2-4 sentences: factual context the reader needs to understand the bottom line. No opinions, only verifiable facts.]

## Key Findings

1. **[Finding 1]** — [One sentence with a specific number or fact]
2. **[Finding 2]** — [One sentence with a specific number or fact]
3. **[Finding 3]** — [One sentence with a specific number or fact]

## Implications

[2-3 sentences: what the findings mean for the organization, project, or decision at hand. Connect findings to outcomes.]

## Recommendation

[1-2 sentences: what the author recommends, stated directly. "We recommend X because Y."]

## Next Steps

| Action | Owner | Due Date |
|--------|-------|----------|
| [action 1] | [who] | [when] |
| [action 2] | [who] | [when] |

## Supporting Data

[Optional: 1 small table or 3-5 bullet points with the data backing the key findings. Only include if the reader will want to verify.]
```

## Procedure

### 1. Identify the Source Material

```bash
TASK_ID="$1"
TOPIC="$2"

# Read the task
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'

# Find all source materials to summarize
echo "=== Source Materials ==="
rg -l -i "$TOPIC" /home/shared/ ~/workspace/ 2>/dev/null \
  | grep -E '\.(md|txt|csv|json)$' | head -20

# Check for registered artifacts (reports, analyses, research)
bash /home/shared/scripts/artifact.sh list 2>/dev/null \
  | jq -r '.[] | "\(.name) — \(.type) — \(.path)"' 2>/dev/null

# Check for recent status or metrics data
find /home/shared/ -name '*report*' -o -name '*metrics*' -o -name '*status*' -o -name '*analysis*' \
  2>/dev/null | sort -r | head -10
```

### 2. Read and Extract Key Data Points

```bash
# For each source document, extract the key numbers and facts
SOURCE_FILE="/home/shared/source-document.md"

echo "=== Headlines and Structure ==="
grep -E '^#{1,3} ' "$SOURCE_FILE"

echo ""
echo "=== Sentences with Numbers (Key Data) ==="
rg '\b\d+\.?\d*\s*(%|percent|hours|days|weeks|months|\$|dollars|million|thousand|increase|decrease|complete|remaining)' \
  "$SOURCE_FILE" -i | head -15

echo ""
echo "=== Conclusions and Recommendations ==="
rg -i 'recommend|conclude|therefore|result|finding|suggest|should|must' \
  "$SOURCE_FILE" | head -10

echo ""
echo "=== Key Metrics ==="
# Extract table rows that contain numbers
rg '\|.*\d+.*\|' "$SOURCE_FILE" | head -10
```

### 3. Distill to 3-5 Key Points

This is the critical intellectual step. From all gathered data, identify exactly 3-5 points.

Rules for selection:
- Each point must be supported by at least one specific number or fact
- Points must be relevant to the audience (what do they care about?)
- Points must be actionable (the audience can do something with this information)
- If two points overlap, merge them

```bash
# Create a working file to draft key points
WORK_DIR="/tmp/briefing-${TOPIC}"
mkdir -p "$WORK_DIR"

cat > "$WORK_DIR/key-points.md" <<'EOF'
## Candidate Key Points (select 3-5 for final briefing)

| # | Point | Supporting Data | Audience Relevance | Include? |
|---|-------|----------------|--------------------|----------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |
| 6 | | | | |
| 7 | | | | |

## Selection Criteria
- Does the audience need to know this to make a decision or take action?
- Is it backed by a specific number or verifiable fact?
- If I can only say 3 things, is this one of them?
EOF
```

### 4. Draft the BLUF Statement

The BLUF (Bottom Line Up Front) is one sentence. Draft it after you have the key findings, not before.

Test your BLUF against these criteria:

```bash
cat > "$WORK_DIR/bluf-test.md" <<'EOF'
## BLUF Quality Test

Draft BLUF: "[your one sentence here]"

- [ ] Contains the conclusion or recommendation (not just context)
- [ ] A reader who reads ONLY this sentence knows what matters
- [ ] Uses a specific number or fact (not vague language)
- [ ] Is one sentence (not two sentences joined by a semicolon)
- [ ] States what IS, not what "may be" or "could be"

Good example: "We recommend proceeding with Vendor B ($145K/year) because it scores highest on all three priority criteria and can deploy within our Q2 deadline."

Bad example: "This briefing summarizes our evaluation of three vendors for the analytics platform initiative."
(This is an introduction, not a bottom line.)
EOF
```

### 5. Write the Briefing

```bash
BRIEFING_FILE="/home/shared/briefing-$(date +%Y%m%d)-${TOPIC}.md"

cat > "$BRIEFING_FILE" <<'BRIEFING'
# [Briefing Title]

**Date:** YYYY-MM-DD
**Author:** [agent name]
**Classification:** [For Decision | For Information | For Action]
**Audience:** [who]

## Bottom Line

[ONE sentence with conclusion and key number]

## Situation

[2-4 sentences of factual context]

## Key Findings

1. **[Finding]** — [data point]
2. **[Finding]** — [data point]
3. **[Finding]** — [data point]

## Implications

[2-3 sentences connecting findings to what the audience cares about]

## Recommendation

[1-2 sentences: direct recommendation]

## Next Steps

| Action | Owner | Due Date |
|--------|-------|----------|
| [action] | [who] | [when] |

## Supporting Data

[Small table or 3-5 bullets backing the key findings]
BRIEFING

echo "Briefing written to: $BRIEFING_FILE"
```

### 6. Enforce Length and Quality Constraints

```bash
BRIEFING_FILE="/home/shared/briefing-$(date +%Y%m%d)-${TOPIC}.md"

echo "=== Briefing Quality Checks ==="

# Check: Total length (must be under ~600 words for 1-2 pages)
WC=$(wc -w < "$BRIEFING_FILE")
echo "Word count: $WC"
if [ "$WC" -gt 600 ]; then
  echo "FAIL: Briefing exceeds 600 words ($WC). Cut to fit 1-2 pages."
elif [ "$WC" -lt 100 ]; then
  echo "FAIL: Briefing is too thin ($WC words). Ensure all sections are substantive."
else
  echo "OK: Length is appropriate for an executive briefing."
fi

# Check: BLUF is present and is one sentence
echo ""
echo "--- Bottom Line section ---"
BLUF=$(sed -n '/^## Bottom Line/,/^## /p' "$BRIEFING_FILE" | grep -v '^##' | grep -v '^$')
BLUF_SENTENCES=$(echo "$BLUF" | grep -c '\.')
echo "BLUF text: $BLUF"
echo "Sentence count: $BLUF_SENTENCES"
[ "$BLUF_SENTENCES" -gt 2 ] && echo "WARNING: BLUF should be 1 sentence, not $BLUF_SENTENCES"

# Check: Key findings have numbers
echo ""
echo "--- Data in findings ---"
FINDINGS=$(sed -n '/^## Key Findings/,/^## /p' "$BRIEFING_FILE")
NUM_COUNT=$(echo "$FINDINGS" | rg -c '\d+' 2>/dev/null || echo 0)
echo "Numbers in findings: $NUM_COUNT"
[ "$NUM_COUNT" -lt 3 ] && echo "WARNING: Key findings need more specific data"

# Check: No vague adjectives in key sections
echo ""
echo "--- Vague language check ---"
VAGUE=$(rg -in '\b(significant|substantial|considerable|good|bad|great|nice|improved|strong|robust|solid|various|several|many)\b' \
  "$BRIEFING_FILE" 2>/dev/null)
if [ -n "$VAGUE" ]; then
  echo "WARNING: Vague adjectives found — replace with numbers:"
  echo "$VAGUE"
else
  echo "OK: No vague adjectives detected."
fi

# Check: Next steps have owners and dates
echo ""
echo "--- Next steps completeness ---"
STEPS=$(sed -n '/^## Next Steps/,/^## /p' "$BRIEFING_FILE" | grep '|' | grep -v '^|.*---')
echo "$STEPS"
if echo "$STEPS" | grep -q 'TBD\|TBA\|\[who\]\|\[when\]'; then
  echo "WARNING: Next steps have placeholder values — fill in owners and dates"
fi

# Check: Classification is set
echo ""
echo "--- Classification ---"
CLASS=$(grep 'Classification:' "$BRIEFING_FILE")
echo "$CLASS"
if echo "$CLASS" | grep -q 'For Decision\|For Information\|For Action'; then
  echo "OK: Classification is set."
else
  echo "WARNING: Set classification to one of: For Decision | For Information | For Action"
fi
```

### 7. Register and Notify

```bash
bash /home/shared/scripts/artifact.sh register \
  --name "briefing-${TOPIC}" \
  --type "briefing" \
  --path "$BRIEFING_FILE" \
  --description "Executive briefing on ${TOPIC}"

# Notify the requesting agent
bash /home/shared/scripts/send-mail.sh \
  --to "$REQUESTING_AGENT" \
  --subject "Executive briefing ready: ${TOPIC}" \
  --body "Briefing available at: $BRIEFING_FILE"
```

## Quality Checklist

- [ ] Bottom Line is ONE sentence containing the conclusion and a key number
- [ ] A reader who reads only the Bottom Line knows what matters
- [ ] Situation section is factual (no opinions or adjectives)
- [ ] Exactly 3-5 key findings, each with a specific data point
- [ ] No vague adjectives (significant, substantial, strong, good, etc.)
- [ ] Implications connect findings to what the audience cares about
- [ ] Recommendation is direct and specific ("We recommend X" not "X could be considered")
- [ ] Next steps have actions, owners, and due dates (no TBD placeholders)
- [ ] Total length is under 600 words (fits 1-2 printed pages)
- [ ] Classification is set (For Decision / For Information / For Action)
- [ ] Document is registered as an artifact in the shared workspace
