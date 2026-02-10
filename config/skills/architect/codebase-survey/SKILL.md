---
name: codebase-survey
description: Survey a codebase to produce an inventory of structure, dependencies, and patterns
---

# Codebase Survey

## When to Use

Use this skill when you need to understand an unfamiliar codebase, onboard to a project, or produce an architectural inventory for the team.

## Output Template

```markdown
# Codebase Survey: [Project Name]

**Date:** [YYYY-MM-DD]
**Surveyed Path:** [path]

## Overview
[2-3 sentence summary: what this project is, what it does, primary language]

## Directory Structure
[tree output, annotated]

## Language Breakdown
| Language | Files | Lines |
|----------|-------|-------|
| ... | ... | ... |

## Entry Points
| Entry Point | Type | Command |
|-------------|------|---------|
| ... | ... | ... |

## Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| ... | ... | ... |

## Key Patterns
- [Pattern 1: e.g., "All API handlers follow request/response/error pattern"]
- [Pattern 2: e.g., "Configuration loaded from environment variables"]

## Observations
- [Notable finding 1]
- [Notable finding 2]
- [Potential concern or risk]
```

## Procedure

### 1. Get the Big Picture

```bash
TARGET="${1:-~/workspace}"
cd "$TARGET"

echo "=== Directory Structure ==="
tree -L 3 --dirsfirst -I 'node_modules|.git|__pycache__|.venv|dist|build' 2>/dev/null \
  || find . -maxdepth 3 -type f | grep -v 'node_modules\|\.git/' | head -60

echo ""
echo "=== Total Files ==="
find . -type f | grep -v 'node_modules\|\.git/' | wc -l
```

### 2. Language Breakdown

```bash
echo "=== Language Breakdown ==="
find . -type f \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/.venv/*' \
  | sed 's/.*\.//' \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -15

echo ""
echo "=== Line Counts by Language ==="
for ext in js ts py sh json md yaml yml; do
  COUNT=$(find . -name "*.$ext" \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -exec cat {} + 2>/dev/null | wc -l)
  [ "$COUNT" -gt 0 ] && printf "%-8s %6d lines\n" "$ext" "$COUNT"
done
```

### 3. Find Entry Points

```bash
echo "=== Entry Points ==="

# package.json scripts
if [ -f package.json ]; then
  echo "--- package.json scripts ---"
  jq -r '.scripts // {} | to_entries[] | "  \(.key): \(.value)"' package.json
  echo "--- main/bin ---"
  jq -r '.main // "not set"' package.json
  jq -r '.bin // {} | to_entries[] | "  \(.key): \(.value)"' package.json 2>/dev/null
fi

# Python entry points
if [ -f setup.py ] || [ -f pyproject.toml ]; then
  echo "--- Python entry points ---"
  grep -E 'console_scripts|entry_points|def main' setup.py pyproject.toml 2>/dev/null
  find . -name '__main__.py' -not -path '*/node_modules/*' 2>/dev/null
fi

# Makefiles
if [ -f Makefile ]; then
  echo "--- Makefile targets ---"
  grep -E '^[a-zA-Z_-]+:' Makefile | sed 's/:.*//' | head -20
fi

# Executable scripts
echo "--- Executable scripts ---"
find . -type f -executable -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -20

# Docker
[ -f Dockerfile ] && echo "--- Dockerfile found ---"
[ -f docker-compose.yml ] && echo "--- docker-compose.yml found ---"
```

### 4. Inventory Dependencies

```bash
echo "=== Dependencies ==="

# Node.js
if [ -f package.json ]; then
  echo "--- npm dependencies ---"
  jq -r '.dependencies // {} | to_entries[] | "\(.key)@\(.value)"' package.json
  echo "--- npm devDependencies ---"
  jq -r '.devDependencies // {} | to_entries[] | "\(.key)@\(.value)"' package.json
fi

# Python
if [ -f requirements.txt ]; then
  echo "--- pip requirements ---"
  cat requirements.txt
fi
if [ -f pyproject.toml ]; then
  echo "--- pyproject.toml dependencies ---"
  sed -n '/^\[project\]/,/^\[/p' pyproject.toml | grep -E '^\s+"' 2>/dev/null
fi

# System dependencies
echo "--- System tools used ---"
rg -oh '\b(curl|wget|jq|sed|awk|grep|find|sort|uniq|cut|tr|xargs|tee|wc)\b' \
  --type sh --no-filename 2>/dev/null | sort -u
```

### 5. Identify Key Patterns

```bash
echo "=== Patterns ==="

# Error handling pattern
echo "--- Error handling ---"
rg 'catch|except|\.catch|try\s*\{' --type-add 'code:*.{js,py,ts,sh}' --type code -c 2>/dev/null | head -10

# Logging pattern
echo "--- Logging ---"
rg 'console\.(log|error|warn)|logging\.(info|error|warn|debug)|logger\.' \
  --type-add 'code:*.{js,py,ts}' --type code -c 2>/dev/null | head -10

# Configuration pattern
echo "--- Config loading ---"
rg 'process\.env|os\.environ|getenv|\.env|config\.' \
  --type-add 'code:*.{js,py,ts}' --type code -l 2>/dev/null | head -10

# Test pattern
echo "--- Test files ---"
find . -name '*test*' -o -name '*spec*' | grep -v node_modules | head -10
```

### 6. Write Survey Report

```bash
SURVEY_FILE="/home/shared/survey-$(date +%Y%m%d)-$(basename $TARGET).md"

# Write the report using the template above, populated with collected data

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "survey-$(basename $TARGET)" \
  --type "survey" \
  --path "$SURVEY_FILE" \
  --description "Codebase survey of $(basename $TARGET)"

echo "Survey written to: $SURVEY_FILE"
```

## Quality Checklist

- [ ] Directory structure shown with annotations for non-obvious directories
- [ ] Language breakdown includes file count and line count
- [ ] All entry points identified (scripts, main files, Makefile targets)
- [ ] Dependencies listed with versions
- [ ] Key patterns identified (error handling, config, logging, testing)
- [ ] Observations include both positives and concerns
- [ ] Report is written to shared workspace and registered as artifact
