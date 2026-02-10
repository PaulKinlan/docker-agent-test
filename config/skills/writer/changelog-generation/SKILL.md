---
name: changelog-generation
description: Generate changelog from git history or task records
---

# Changelog Generation

## When to Use

Use this skill when tasked with producing a changelog, release notes, or summary of changes for a time period or version.

## Output Format (Keep a Changelog)

```markdown
# Changelog

## [Version] - YYYY-MM-DD

### Added
- [New feature described from USER perspective]

### Changed
- [Existing behavior that was modified]

### Fixed
- [Bug that was resolved, describe the symptom that is now fixed]

### Removed
- [Feature or capability that was removed]

### Security
- [Security-related change]
```

## Procedure

### 1. Gather Change Data

**From git history:**
```bash
cd ~/workspace

# Get commits since last tag or date
SINCE="${1:-7 days ago}"

echo "=== Commits since $SINCE ==="
git log --oneline --since="$SINCE" 2>/dev/null

echo ""
echo "=== Detailed log ==="
git log --format='%h %s%n  Author: %an%n  Date: %ai%n' --since="$SINCE" 2>/dev/null

echo ""
echo "=== Files changed ==="
git diff --stat $(git log --format='%H' --since="$SINCE" | tail -1) HEAD 2>/dev/null
```

**From task board:**
```bash
echo "=== Completed tasks ==="
bash /home/shared/scripts/task.sh list --status completed 2>/dev/null

echo ""
echo "=== Task details ==="
bash /home/shared/scripts/task.sh list --status completed 2>/dev/null \
  | jq -r '.[] | "\(.id): \(.subject) — \(.result // "no result recorded")"' 2>/dev/null
```

**From artifacts:**
```bash
echo "=== Recent artifacts ==="
bash /home/shared/scripts/artifact.sh list 2>/dev/null
```

### 2. Categorize Changes

Sort each change into one of these categories:

| Category | Criteria | Examples |
|----------|----------|---------|
| **Added** | New feature, new file, new capability | "Add search filtering by date" |
| **Changed** | Modified existing behavior | "Increase default timeout from 30s to 60s" |
| **Fixed** | Bug fix | "Fix crash when input file is empty" |
| **Removed** | Deleted feature or file | "Remove deprecated v1 API endpoints" |
| **Security** | Security improvement | "Sanitize user input in query parameters" |

Categorize by looking at the commit message and the diff:

```bash
git log --oneline --since="$SINCE" 2>/dev/null | while read hash msg; do
  # Auto-categorize based on commit message patterns
  case "$msg" in
    [Aa]dd*|[Nn]ew*|[Cc]reate*|[Ii]mplement*)  echo "Added: $msg" ;;
    [Ff]ix*|[Rr]epair*|[Rr]esolve*|[Cc]lose*)   echo "Fixed: $msg" ;;
    [Rr]emove*|[Dd]elete*|[Dd]rop*)              echo "Removed: $msg" ;;
    [Ss]ecur*|[Cc]ve*|[Vv]uln*)                  echo "Security: $msg" ;;
    *)                                             echo "Changed: $msg" ;;
  esac
done
```

### 3. Rewrite from User Perspective

Transform developer-facing commit messages into user-facing changelog entries:

| Developer Commit | User-Facing Entry |
|-----------------|-------------------|
| "Refactor auth middleware to use JWT" | "Changed: Authentication now uses JWT tokens for improved security" |
| "Fix bug in parseInput when null" | "Fixed: Application no longer crashes when submitting an empty form" |
| "Add rateLimit to /api/search" | "Added: Rate limiting on search API (100 requests/minute)" |
| "Remove legacy CSV export code" | "Removed: CSV export feature (use JSON export instead)" |

Rules:
- Describe the **effect**, not the implementation
- Start with a verb
- Include specifics (numbers, names) when relevant
- One entry per user-visible change (merge related commits)

### 4. Write the Changelog

```bash
VERSION="${VERSION:-Unreleased}"
DATE=$(date +%Y-%m-%d)
CHANGELOG_FILE="/home/shared/CHANGELOG.md"

cat > "$CHANGELOG_FILE" <<EOF
# Changelog

## [$VERSION] - $DATE

### Added
- [entry 1]
- [entry 2]

### Changed
- [entry 1]

### Fixed
- [entry 1]
- [entry 2]

### Removed
- [entry 1]

### Security
- [entry 1]
EOF

# Remove empty sections
python3 -c "
import re
with open('$CHANGELOG_FILE') as f:
    content = f.read()
# Remove sections with no entries (just header, no list items before next header or EOF)
content = re.sub(r'### \w+\n(?=###|\Z|\n## )', '', content)
with open('$CHANGELOG_FILE', 'w') as f:
    f.write(content.strip() + '\n')
" 2>/dev/null

echo "Changelog written to: $CHANGELOG_FILE"
cat "$CHANGELOG_FILE"
```

### 5. Register as Artifact

```bash
bash /home/shared/scripts/artifact.sh register \
  --name "changelog" \
  --type "documentation" \
  --path "$CHANGELOG_FILE" \
  --description "Changelog for version $VERSION"
```

## Quality Checklist

- [ ] All completed tasks and commits are accounted for
- [ ] Each entry is written from the user's perspective (effect, not implementation)
- [ ] Entries are categorized correctly (Added/Changed/Fixed/Removed/Security)
- [ ] Empty categories are removed
- [ ] Related commits are merged into single entries
- [ ] Each entry starts with a verb and is specific
- [ ] Version and date are accurate
