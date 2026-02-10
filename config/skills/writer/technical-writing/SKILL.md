---
name: technical-writing
description: Write clear technical documentation for a specific audience
---

# Technical Writing

## When to Use

Use this skill when tasked with writing documentation, guides, API references, or any technical prose.

## Principles

1. **Know your audience.** A getting-started guide for new users is different from an API reference for experienced developers. Decide first, then write accordingly.
2. **Structure for scanning.** Readers scan before they read. Use headings, bullet points, tables, and code blocks. Never bury important information in long paragraphs.
3. **Show, don't tell.** A code example is worth a paragraph of explanation. Every feature description should have a runnable example.
4. **Be precise.** Use numbers, not adjectives. "Responds in under 200ms" not "responds quickly." "Accepts up to 1MB" not "accepts large files."
5. **One idea per sentence.** If a sentence has "and" or "but" connecting two distinct ideas, split it.

## Output Template

```markdown
# [Title]

## Overview
[1-2 sentences: what this is, who it is for, what problem it solves]

## Getting Started

### Prerequisites
- [requirement 1 with version]
- [requirement 2]

### Installation
```bash
[exact commands to install]
```

### Quick Start
```bash
[minimal example that works immediately]
```

## Usage

### [Feature/Command 1]
[1 sentence description]

```bash
[runnable example]
```

**Parameters:**
| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| ... | ... | ... | ... | ... |

**Returns:** [what the output looks like]

### [Feature/Command 2]
...

## Configuration
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| ... | ... | ... | ... |

## Troubleshooting

### [Common problem 1]
**Symptom:** [what the user sees]
**Cause:** [why it happens]
**Fix:** [exact steps to resolve]

### [Common problem 2]
...

## Reference
[Complete API/CLI reference if applicable]
```

## Procedure

### 1. Read Source Material

```bash
TARGET="${1:-~/workspace}"

# Read the code to understand what it does
find "$TARGET" -name '*.js' -o -name '*.py' -o -name '*.sh' \
  | grep -v node_modules | grep -v .git | while read f; do
  echo "=== $f ==="
  head -30 "$f"
  echo ""
done

# Read existing documentation
find "$TARGET" -name '*.md' | while read f; do
  echo "=== $f ==="
  cat "$f"
  echo ""
done

# Read help output
find "$TARGET" -name '*.sh' -executable | while read f; do
  echo "=== $f --help ==="
  bash "$f" --help 2>&1 | head -20
  echo ""
done
```

### 2. Identify the Audience

Determine who will read this document:

| Audience | Assumed Knowledge | Focus On |
|----------|-------------------|----------|
| New user | Minimal, may not know the domain | Getting started, examples, troubleshooting |
| Developer | Knows the language, needs API details | Parameters, return values, error codes |
| Operator | Knows systems, needs deployment info | Configuration, monitoring, troubleshooting |
| Contributor | Knows the project, wants to extend it | Architecture, patterns, conventions |

### 3. Draft the Document

Write following the template. For every claim or instruction:
- Verify it works by running the command
- Include the exact output the reader will see
- Note any platform-specific differences

### 4. Verify Code Examples Work

Every code block must be tested:

```bash
# Extract code blocks and test them
DOC_FILE="/tmp/draft-doc.md"

# Test shell examples
grep -A 20 '```bash' "$DOC_FILE" | grep -v '```' | while read line; do
  echo "Testing: $line"
  eval "$line" 2>&1 | head -5
  echo "Exit: $?"
  echo ""
done
```

### 5. Write to Shared Workspace

```bash
DOC_FILE="/home/shared/docs/$(echo $DOC_NAME | tr ' ' '-' | tr '[:upper:]' '[:lower:]').md"
mkdir -p "$(dirname "$DOC_FILE")"

# Write the document
cat > "$DOC_FILE" <<'EOF'
[document content]
EOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "doc-$(basename "$DOC_FILE" .md)" \
  --type "documentation" \
  --path "$DOC_FILE" \
  --description "Technical documentation: $DOC_NAME"
```

## Quality Checklist

- [ ] Audience is identified and content matches their knowledge level
- [ ] Document has Overview, Getting Started, Usage, and Troubleshooting sections
- [ ] Every feature has at least one runnable code example
- [ ] All code examples have been tested and work
- [ ] Parameters are documented in tables (name, type, required, default, description)
- [ ] Numbers are used instead of vague adjectives
- [ ] Each sentence contains one idea
- [ ] Headings allow a reader to find what they need by scanning
