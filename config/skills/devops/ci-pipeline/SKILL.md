---
name: ci-pipeline
description: Design CI/CD pipeline configurations with fast feedback and minimal permissions
---

# CI Pipeline Design

## When to Use

Use this skill when tasked with creating or improving CI/CD pipeline configurations (GitHub Actions, GitLab CI, or similar).

## Principles

| Principle | Why | How |
|-----------|-----|-----|
| Fast feedback | Developers abandon slow CI | Lint+unit first, integration last |
| Idempotent | Reruns must produce same result | No side effects, deterministic deps |
| Minimal permissions | Limit blast radius of compromise | Least-privilege tokens, read-only where possible |
| Cache dependencies | Faster builds, less bandwidth | Cache npm/pip/cargo directories |
| Fail fast | Don't waste time on doomed builds | Cancel in-progress on new push |

## Procedure

### 1. Assess the Project

```bash
PROJECT_DIR="${1:-~/workspace}"
cd "$PROJECT_DIR"

echo "=== Project Type Detection ==="
[ -f package.json ] && echo "Node.js project detected"
[ -f pyproject.toml ] || [ -f setup.py ] && echo "Python project detected"
[ -f go.mod ] && echo "Go project detected"
[ -f Cargo.toml ] && echo "Rust project detected"
[ -f Dockerfile ] && echo "Docker build needed"

echo ""
echo "=== Available Scripts ==="
jq -r '.scripts | to_entries[] | "  \(.key): \(.value)"' package.json 2>/dev/null
grep -E '^[a-zA-Z_-]+:' Makefile 2>/dev/null | sed 's/:.*/  (make)/'

echo ""
echo "=== Test Framework ==="
jq -r '.devDependencies // {} | keys[]' package.json 2>/dev/null | grep -E 'jest|mocha|vitest|tap'
pip list 2>/dev/null | grep -iE 'pytest|tox|nox'
```

### 2. Design Pipeline Stages

Standard pipeline order (fast to slow):

```
1. Lint        (seconds)  — catch syntax/style errors immediately
2. Unit Test   (seconds)  — catch logic errors fast
3. Build       (minutes)  — verify it compiles/bundles
4. Integration (minutes)  — verify components work together
5. Security    (minutes)  — scan for vulnerabilities
6. Deploy      (minutes)  — only on main branch, after all checks pass
```

### 3. Write GitHub Actions Configuration

**Node.js project:**
```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Cancel in-progress runs on new push
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm run lint

  test:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm test
      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/

  build:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/

  security:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm audit --audit-level=high
```

**Python project:**
```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'
      - run: pip install ruff
      - run: ruff check .
      - run: ruff format --check .

  test:
    runs-on: ubuntu-latest
    needs: lint
    strategy:
      matrix:
        python-version: ['3.10', '3.11', '3.12']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: 'pip'
      - run: pip install -e ".[dev]"
      - run: python -m pytest tests/ -v --tb=short

  security:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'
      - run: pip install pip-audit
      - run: pip install -e .
      - run: pip-audit
```

### 4. Write the Pipeline Config File

```bash
PIPELINE_DIR="$PROJECT_DIR/.github/workflows"
mkdir -p "$PIPELINE_DIR"

PIPELINE_FILE="$PIPELINE_DIR/ci.yml"

# Write the appropriate YAML (Node.js or Python version from above)
cat > "$PIPELINE_FILE" <<'EOF'
# [paste appropriate YAML here]
EOF

echo "Pipeline written to: $PIPELINE_FILE"
```

### 5. Validate the Configuration

```bash
PIPELINE_FILE="$PROJECT_DIR/.github/workflows/ci.yml"

echo "=== Pipeline Validation ==="

# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('$PIPELINE_FILE'))" 2>&1 \
  && echo "OK: Valid YAML" || echo "FAIL: Invalid YAML"

# Check for security issues
echo ""
echo "--- Security checks ---"
grep -n 'permissions:' "$PIPELINE_FILE" \
  && echo "OK: Permissions specified" || echo "WARNING: No permissions block — defaults to read-write"

grep -n 'cancel-in-progress' "$PIPELINE_FILE" \
  && echo "OK: Concurrency control" || echo "WARNING: No concurrency control — parallel runs possible"

grep -n '@v[0-9]' "$PIPELINE_FILE" | grep -v '@v[0-9]$' \
  && echo "INFO: Actions use major version tags" || true

# Check for common mistakes
echo ""
echo "--- Common mistakes ---"
grep -n 'npm install' "$PIPELINE_FILE" | grep -v 'npm ci' \
  && echo "WARNING: Use 'npm ci' instead of 'npm install' in CI" || echo "OK: Using npm ci"

grep -n 'pip install -r' "$PIPELINE_FILE" \
  && echo "INFO: Consider using pip install -e '.[dev]' for editable install" || true

grep -n 'continue-on-error: true' "$PIPELINE_FILE" \
  && echo "WARNING: continue-on-error masks failures" || echo "OK: No error masking"
```

### 6. Document Pipeline Stages

```bash
PIPELINE_DOC="/home/shared/ci-pipeline-design.md"

cat > "$PIPELINE_DOC" <<'EOF'
# CI Pipeline Design

## Stages

| Stage | Trigger | Duration | Purpose |
|-------|---------|----------|---------|
| Lint | push, PR | ~30s | Syntax and style errors |
| Test | after lint | ~2min | Logic correctness |
| Build | after test | ~1min | Compilation/bundling |
| Security | after lint | ~1min | Vulnerability scanning |
| Deploy | main only, after all | ~3min | Production deployment |

## Configuration
- File: `.github/workflows/ci.yml`
- Concurrency: cancels in-progress on new push
- Permissions: read-only by default
- Caching: npm/pip cache enabled

## Adding a New Stage
1. Add a new job in the `jobs:` section
2. Set `needs:` to control ordering
3. Use `actions/cache` for dependencies
4. Test locally with `act` if available
EOF

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  --name "ci-pipeline-design" \
  --type "design" \
  --path "$PIPELINE_DOC" \
  --description "CI/CD pipeline design and configuration"
```

## Quality Checklist

- [ ] Pipeline stages ordered by speed (fast first)
- [ ] Concurrency control enabled (cancel-in-progress)
- [ ] Permissions set to minimal (contents: read)
- [ ] Dependencies cached (npm/pip cache)
- [ ] Actions pinned to version tags (not :latest or SHA)
- [ ] npm ci used instead of npm install
- [ ] Security scanning included (npm audit / pip-audit)
- [ ] YAML validates without syntax errors
- [ ] No continue-on-error masking real failures
- [ ] Pipeline documentation written for the team
