---
name: structured-research
description: Conduct structured research producing organized notes with sources
---

# Structured Research

## When to Use

Use this skill when tasked with researching a topic, evaluating options, or gathering information to support a decision.

## Output Template

Every research deliverable must follow this structure:

```markdown
# Research: [Topic]

## Summary
[2-3 sentence executive summary of findings]

## Key Findings
1. [Most important finding — one sentence]
2. [Second most important finding]
3. [Third most important finding]

## Detailed Notes

### [Subtopic A]
- [Fact or observation]. Source: [reference]
- [Fact or observation]. Source: [reference]
- Unverified: [claim that could not be confirmed]

### [Subtopic B]
- [Fact or observation]. Source: [reference]

## Sources
| # | Source | Type | Reliability | Notes |
|---|--------|------|-------------|-------|
| 1 | [name/URL] | [doc/code/article/manpage] | [High/Medium/Low] | [brief note] |
| 2 | ... | ... | ... | ... |

## Open Questions
- [Question that remains unanswered]
- [Area needing further investigation]
```

## Procedure

### 1. Define the Research Question

```bash
# Read the task to extract the research question
TASK_ID="$1"
bash /home/shared/scripts/task.sh get "$TASK_ID" | jq -r '.description'
```

Write down:
- The specific question to answer
- Who will use this research (architect? coder? planner?)
- What decision this research supports

### 2. Gather Information from Available Sources

**Search the codebase:**
```bash
TOPIC="authentication"

# Find relevant files
rg -l "$TOPIC" ~/workspace/ /home/shared/ 2>/dev/null | head -20

# Find relevant documentation
find ~/workspace/ /home/shared/ -name '*.md' -exec grep -l "$TOPIC" {} \; 2>/dev/null

# Check configuration files
find ~/workspace/ /home/shared/ -name '*.json' -o -name '*.yaml' -o -name '*.toml' \
  | xargs grep -l "$TOPIC" 2>/dev/null
```

**Read man pages and help text:**
```bash
# For CLI tools
man $TOOL_NAME 2>/dev/null | head -100
$TOOL_NAME --help 2>&1 | head -50
```

**Read existing documentation:**
```bash
# Check for docs in the workspace
find ~/workspace/ -name 'README*' -o -name 'ARCHITECTURE*' -o -name 'DESIGN*' \
  | while read f; do echo "=== $f ==="; head -30 "$f"; done
```

### 3. For Each Claim, Note the Source

Every factual statement must be attributed:
- File path and line number for code references
- Document name for documentation references
- Tool output for empirical observations
- "Unverified:" prefix for claims that cannot be confirmed from available sources

### 4. Flag Uncertainty

Use these prefixes consistently:
- No prefix: confirmed from authoritative source
- `Unverified:` claim found in one non-authoritative source
- `Conflicting:` sources disagree (cite both)
- `Inferred:` logical deduction not directly stated anywhere

### 5. Write the Research Document

```bash
RESEARCH_FILE="/home/shared/research-$(date +%Y%m%d)-${TOPIC}.md"

cat > "$RESEARCH_FILE" <<'EOF'
# Research: [Topic]

## Summary
...

## Key Findings
...

## Detailed Notes
...

## Sources
...

## Open Questions
...
EOF

echo "Research written to: $RESEARCH_FILE"
```

### 6. Register as Artifact

```bash
bash /home/shared/scripts/artifact.sh register \
  --name "research-${TOPIC}" \
  --type "research" \
  --path "$RESEARCH_FILE" \
  --description "Structured research on $TOPIC"
```

## Quality Checklist

- [ ] Every factual claim has a cited source
- [ ] Uncertain claims are prefixed with "Unverified:" or "Inferred:"
- [ ] Conflicting information is noted with both sources
- [ ] Key Findings are ordered by importance
- [ ] Open Questions identify specific gaps, not vague areas
- [ ] Sources table includes reliability assessment
- [ ] Document is written for the intended audience (technical depth matches reader)
