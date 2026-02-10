---
name: dependency-audit
description: Audit project dependencies for known vulnerabilities and license issues
---

# Dependency Audit

## When to Use

Use this skill when tasked with auditing dependencies, before adding new dependencies, or as part of a security review.

## Procedure

### 1. Inventory All Dependencies

**Node.js:**
```bash
TARGET="${1:-~/workspace}"
cd "$TARGET"

echo "=== Direct Dependencies ==="
jq -r '.dependencies // {} | to_entries[] | "\(.key) \(.value)"' package.json

echo ""
echo "=== Dev Dependencies ==="
jq -r '.devDependencies // {} | to_entries[] | "\(.key) \(.value)"' package.json

echo ""
echo "=== Total dependency tree ==="
npm ls --all --depth=0 2>/dev/null | tail -n +2 | wc -l
echo "direct + transitive packages"
```

**Python:**
```bash
cd "$TARGET"

echo "=== requirements.txt ==="
cat requirements.txt 2>/dev/null

echo ""
echo "=== pyproject.toml dependencies ==="
python3 -c "
import tomllib, json
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
deps = data.get('project', {}).get('dependencies', [])
for d in deps:
    print(d)
" 2>/dev/null

echo ""
echo "=== Installed packages ==="
pip list --format=columns 2>/dev/null | head -30
```

### 2. Check for Known Vulnerabilities

**npm audit:**
```bash
cd "$TARGET"

# Full JSON audit
npm audit --json 2>/dev/null | tee /tmp/npm-audit.json

# Summary
echo "=== Vulnerability Summary ==="
jq '.metadata.vulnerabilities' /tmp/npm-audit.json 2>/dev/null

# Critical and High details
echo "=== Critical/High Vulnerabilities ==="
jq '
  .vulnerabilities | to_entries[]
  | select(.value.severity == "critical" or .value.severity == "high")
  | {
      name: .key,
      severity: .value.severity,
      range: .value.range,
      fix_available: .value.fixAvailable,
      via: [.value.via[] | if type == "object" then .title else . end]
    }
' /tmp/npm-audit.json 2>/dev/null
```

**pip audit:**
```bash
cd "$TARGET"

pip audit --format=json 2>/dev/null | tee /tmp/pip-audit.json \
  || echo "pip-audit not installed. Install with: pip install pip-audit"

# Parse results
jq '.dependencies[] | select(.vulns | length > 0) | {
  name: .name,
  version: .version,
  vulns: [.vulns[] | {id: .id, fix_versions: .fix_versions}]
}' /tmp/pip-audit.json 2>/dev/null
```

### 3. Check for Outdated Dependencies

**npm:**
```bash
cd "$TARGET"

echo "=== Outdated Packages ==="
npm outdated --json 2>/dev/null | jq '
  to_entries[] | {
    package: .key,
    current: .value.current,
    wanted: .value.wanted,
    latest: .value.latest,
    behind: (if .value.current != .value.latest then "YES" else "no" end)
  }
' 2>/dev/null
```

**pip:**
```bash
cd "$TARGET"

echo "=== Outdated Packages ==="
pip list --outdated --format=columns 2>/dev/null
```

### 4. Evaluate Each Dependency

For each dependency, assess:

```bash
PACKAGE="express"

# npm: check package info
npm info "$PACKAGE" --json 2>/dev/null | jq '{
  name: .name,
  version: .version,
  license: .license,
  homepage: .homepage,
  maintainers: [.maintainers[].name],
  last_publish: .time[.version],
  weekly_downloads: .downloads
}' 2>/dev/null

# Check if it is maintained (last publish date)
LAST_PUBLISH=$(npm info "$PACKAGE" time --json 2>/dev/null | jq -r 'to_entries | sort_by(.value) | last | .value')
echo "Last published: $LAST_PUBLISH"
```

Evaluation criteria:
- **Maintained?** Last publish within 12 months
- **Popular?** Weekly downloads > 1000
- **Secure?** No unpatched CVEs
- **Licensed?** Compatible license (MIT, Apache-2.0, BSD are generally safe)
- **Scoped?** Does it request minimal permissions/capabilities

### 5. Check Licenses

```bash
cd "$TARGET"

# npm: license check
echo "=== License Inventory ==="
npm ls --json 2>/dev/null | jq '
  [.. | .license? // empty] | group_by(.) | map({license: .[0], count: length}) | sort_by(-.count)
' 2>/dev/null

# Flag problematic licenses
echo "=== Potentially Problematic Licenses ==="
npm ls --json 2>/dev/null | jq -r '
  [paths(type == "string" and (test("GPL|AGPL|SSPL|BUSL|Unlicense|UNKNOWN")))] as $paths
  | $paths[] | join("/")
' 2>/dev/null
```

### 6. Produce Audit Report

```bash
REPORT_FILE="/home/shared/dependency-audit-$(date +%Y%m%d).md"

cat > "$REPORT_FILE" <<'EOF'
# Dependency Audit Report

**Date:** YYYY-MM-DD
**Project:** [name]
**Package Manager:** npm / pip

## Summary
| Metric | Value |
|--------|-------|
| Total direct dependencies | N |
| Total transitive dependencies | N |
| Critical vulnerabilities | N |
| High vulnerabilities | N |
| Outdated packages | N |
| License concerns | N |

## Vulnerability Findings

| Package | Version | Latest | Severity | CVE | Fix Available |
|---------|---------|--------|----------|-----|---------------|
| ... | ... | ... | ... | ... | Yes/No |

## Outdated Dependencies

| Package | Current | Wanted | Latest | Risk |
|---------|---------|--------|--------|------|
| ... | ... | ... | ... | ... |

## License Review

| License | Count | Concern |
|---------|-------|---------|
| MIT | N | None |
| GPL-3.0 | N | Copyleft — review compatibility |

## Recommendations
1. [Specific action: "Upgrade express from 4.17.1 to 4.18.2 to fix CVE-XXXX-XXXXX"]
2. [Specific action: "Replace abandoned-pkg with maintained-alternative"]
EOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "dependency-audit" \
  --type "report" \
  --path "$REPORT_FILE" \
  --description "Dependency audit report with vulnerabilities and license review"
```

## Quality Checklist

- [ ] All direct and transitive dependencies inventoried
- [ ] npm audit / pip audit run and results parsed
- [ ] Outdated packages identified with current vs latest version
- [ ] Each critical/high vulnerability has a recommended fix
- [ ] Licenses reviewed for compatibility
- [ ] Report includes specific, actionable recommendations
- [ ] Report written to shared workspace and registered as artifact
