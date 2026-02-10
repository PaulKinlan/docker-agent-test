---
name: editorial-review
description: Review a document for clarity, consistency, correctness, and tone
---

# Editorial Review

## When to Use

Use this skill when tasked with reviewing documentation, reports, or any written deliverable for quality before it is shared or published.

## Procedure

### 1. First Pass -- Read Without Changes

Read the entire document without making any changes. Note your overall impression:

```bash
DOC_FILE="${1:-/home/shared/document.md}"

# Read the full document
cat "$DOC_FILE"

# Get basic stats
echo ""
echo "=== Document Stats ==="
wc -l "$DOC_FILE" | awk '{print "Lines:", $1}'
wc -w "$DOC_FILE" | awk '{print "Words:", $1}'
grep -c '^#' "$DOC_FILE" | xargs -I{} echo "Headings: {}"
grep -c '```' "$DOC_FILE" | awk '{print "Code blocks:", $1/2}'
grep -cE '^\|' "$DOC_FILE" | xargs -I{} echo "Table rows: {}"
```

After reading, answer these questions before proceeding:
- What is the document's purpose?
- Who is the intended audience?
- Does the structure make sense for that purpose?

### 2. Second Pass -- Detailed Review

Check each of these dimensions:

#### Clarity
- Can each sentence be understood on first reading?
- Are technical terms defined on first use?
- Are there ambiguous pronouns ("it", "this", "that") without clear antecedents?
- Are instructions specific enough to follow without guessing?

```bash
# Find potentially ambiguous sentences (very long sentences)
awk 'length > 120 && !/^[|#`]/' "$DOC_FILE" | head -10
echo "(Sentences over 120 chars may need splitting)"

# Find undefined acronyms
grep -oE '\b[A-Z]{2,6}\b' "$DOC_FILE" | sort -u | while read acr; do
  FIRST=$(grep -n "\b$acr\b" "$DOC_FILE" | head -1 | cut -d: -f1)
  DEFINED=$(grep -n "$acr (" "$DOC_FILE" | head -1 | cut -d: -f1)
  if [ -z "$DEFINED" ] && [ "$(echo "$acr" | wc -c)" -gt 3 ]; then
    echo "Acronym $acr first used on line $FIRST — not defined"
  fi
done
```

#### Consistency
- Are terms used consistently (not "config" in one place and "configuration" in another)?
- Are formatting conventions consistent (heading levels, code block style, list style)?
- Are command examples consistent with the project's actual commands?

```bash
# Check for inconsistent terminology
for pair in "config:configuration" "dir:directory" "repo:repository" "env:environment" "arg:argument"; do
  SHORT=$(echo "$pair" | cut -d: -f1)
  LONG=$(echo "$pair" | cut -d: -f2)
  S_COUNT=$(grep -ci "\b${SHORT}\b" "$DOC_FILE" 2>/dev/null)
  L_COUNT=$(grep -ci "\b${LONG}\b" "$DOC_FILE" 2>/dev/null)
  if [ "$S_COUNT" -gt 0 ] && [ "$L_COUNT" -gt 0 ]; then
    echo "Inconsistent: '$SHORT' ($S_COUNT) vs '$LONG' ($L_COUNT) — pick one"
  fi
done

# Check heading level consistency
grep '^#' "$DOC_FILE" | awk '{print length($1), $0}' | head -20
echo "(Verify heading levels are sequential — no jumps from ## to ####)"
```

#### Correctness
- Are facts accurate?
- Do code examples work?
- Are file paths, command names, and flag names correct?
- Do cross-references point to things that exist?

```bash
# Verify referenced file paths exist
grep -oE '`[~/][a-zA-Z0-9_./-]+`' "$DOC_FILE" | tr -d '`' | while read path; do
  expanded=$(eval echo "$path" 2>/dev/null)
  [ -e "$expanded" ] && echo "OK: $path" || echo "MISSING: $path"
done

# Verify referenced commands exist
grep -oE '`(bash|node|python3|npm|jq|curl) [^`]+`' "$DOC_FILE" | tr -d '`' | while read cmd; do
  BINARY=$(echo "$cmd" | awk '{print $1}')
  which "$BINARY" >/dev/null 2>&1 && echo "OK: $BINARY" || echo "MISSING: $BINARY"
done
```

#### Completeness
- Are there gaps where a reader would be stuck?
- Does every "how" have a "why"?
- Are error cases and edge cases documented?
- Is there a troubleshooting section for likely problems?

#### Tone
- Is the tone appropriate for the audience?
- Is it consistent throughout (not formal in intro and casual in body)?
- Does it avoid condescension ("simply", "just", "obviously")?

```bash
# Check for condescending language
grep -niE '\b(simply|just|obviously|clearly|trivially|of course|easy|easily)\b' "$DOC_FILE" \
  | head -10
echo "(Consider removing these — they imply the reader should find it obvious)"
```

### 3. Produce Review Notes

For each issue found, format as:

```markdown
### Issue [N]: [Category]
- **Location:** Line [N] / Section "[heading]"
- **Current:** "[quoted text as it appears]"
- **Suggested:** "[replacement text]"
- **Reason:** [why this change improves the document]
```

### 4. Write the Review

```bash
REVIEW_FILE="/home/shared/review-$(date +%Y%m%d)-$(basename "$DOC_FILE" .md).md"

cat > "$REVIEW_FILE" <<'EOF'
# Editorial Review

**Document:** [document name]
**Reviewer:** [agent name]
**Date:** YYYY-MM-DD

## Overall Assessment
[2-3 sentences: is this document ready to publish? What is its biggest strength? What needs the most work?]

## Summary
| Category | Issues Found |
|----------|-------------|
| Clarity | N |
| Consistency | N |
| Correctness | N |
| Completeness | N |
| Tone | N |

## Issues

### Issue 1: [Category]
- **Location:** ...
- **Current:** "..."
- **Suggested:** "..."
- **Reason:** ...

## Positive Notes
- [Something the document does well — preserve the author's voice]
- [Another strength]
EOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "review-$(basename "$DOC_FILE" .md)" \
  --type "review" \
  --path "$REVIEW_FILE" \
  --description "Editorial review of $(basename "$DOC_FILE")"
```

## Quality Checklist

- [ ] Full document read before any edits were made
- [ ] All five dimensions checked (clarity, consistency, correctness, completeness, tone)
- [ ] Every issue has location, current text, suggested text, and reason
- [ ] Code examples verified to be runnable
- [ ] File paths and command references verified to exist
- [ ] Positive aspects acknowledged (not just criticism)
- [ ] Author's voice and style preserved in suggestions
- [ ] Review is actionable (author can apply each suggestion without guessing)
