---
name: dockerfile-authoring
description: Write efficient, secure Dockerfiles following best practices
---

# Dockerfile Authoring

## When to Use

Use this skill when tasked with writing or improving a Dockerfile for any project.

## Best Practices Reference

| Practice | Why | How |
|----------|-----|-----|
| Order layers by change frequency | Faster builds via cache hits | Static deps first, source code last |
| Minimize layers | Smaller image, fewer attack surfaces | Combine RUN with && and \ |
| Use specific base image tags | Reproducible builds | `node:20.11-slim` not `node:latest` |
| Run as non-root user | Limit container compromise impact | Add USER directive |
| Multi-stage builds | Smaller final image | Build in one stage, copy artifacts to slim stage |
| Copy manifests before source | Cache dependency install layer | COPY package*.json first, then npm install |
| Always add HEALTHCHECK | Enable orchestrator monitoring | HEALTHCHECK CMD curl or process check |
| Use .dockerignore | Prevent leaking secrets, speed up context | Ignore .git, node_modules, .env |

## Procedure

### 1. Determine Requirements

```bash
# What language/runtime?
PROJECT_DIR="${1:-~/workspace}"
ls "$PROJECT_DIR/package.json" "$PROJECT_DIR/pyproject.toml" "$PROJECT_DIR/Cargo.toml" \
   "$PROJECT_DIR/go.mod" "$PROJECT_DIR/Makefile" 2>/dev/null

# What does the project need to run?
cat "$PROJECT_DIR/package.json" 2>/dev/null | jq '{main, scripts, engines}'
cat "$PROJECT_DIR/pyproject.toml" 2>/dev/null | head -20

# What system packages are required?
grep -rh 'apt-get\|apk add\|yum install' "$PROJECT_DIR/Dockerfile" 2>/dev/null
```

### 2. Write the Dockerfile

**Node.js Application:**
```dockerfile
# Build stage
FROM node:20.11-slim AS build

WORKDIR /app

# Copy dependency manifests first (cacheable layer)
COPY package.json package-lock.json ./
RUN npm ci --production=false

# Copy source code (changes frequently — last layer)
COPY src/ ./src/
COPY tsconfig.json ./

# Build if needed
RUN npm run build 2>/dev/null || true

# Production stage
FROM node:20.11-slim

# Security: non-root user
RUN groupadd -r appuser && useradd -r -g appuser -d /app appuser

WORKDIR /app

# Copy only production dependencies
COPY package.json package-lock.json ./
RUN npm ci --production && npm cache clean --force

# Copy built application
COPY --from=build /app/dist/ ./dist/
COPY --from=build /app/src/ ./src/

# Set ownership
RUN chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1))" || exit 1

CMD ["node", "src/index.js"]
```

**Python Application:**
```dockerfile
# Build stage
FROM python:3.12-slim AS build

WORKDIR /app

# Install build dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Production stage
FROM python:3.12-slim

# Security: non-root user
RUN groupadd -r appuser && useradd -r -g appuser -d /app appuser

WORKDIR /app

# Copy installed packages from build stage
COPY --from=build /install /usr/local

# Copy application code
COPY src/ ./src/

# Set ownership
RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["python3", "-m", "src.main"]
```

### 3. Write .dockerignore

```bash
cat > "$PROJECT_DIR/.dockerignore" <<'EOF'
.git
.gitignore
node_modules
.venv
__pycache__
*.pyc
.env
.env.*
*.md
.DS_Store
coverage/
.nyc_output/
tests/
test/
docs/
.idea/
.vscode/
*.log
Dockerfile
docker-compose*.yml
EOF
```

### 4. Validate the Dockerfile

```bash
DOCKERFILE="${PROJECT_DIR}/Dockerfile"

echo "=== Dockerfile Lint ==="

# Check for latest tag
grep -n ':latest' "$DOCKERFILE" && echo "WARNING: Using :latest tag — pin to specific version"

# Check for root user
grep -q 'USER' "$DOCKERFILE" && echo "OK: USER directive found" || echo "WARNING: No USER directive — runs as root"

# Check for HEALTHCHECK
grep -q 'HEALTHCHECK' "$DOCKERFILE" && echo "OK: HEALTHCHECK found" || echo "WARNING: No HEALTHCHECK"

# Check for .dockerignore
[ -f "$PROJECT_DIR/.dockerignore" ] && echo "OK: .dockerignore exists" || echo "WARNING: No .dockerignore"

# Check for COPY before RUN npm/pip install (caching)
COPY_LINE=$(grep -n 'COPY.*package\|COPY.*requirements' "$DOCKERFILE" | head -1 | cut -d: -f1)
INSTALL_LINE=$(grep -n 'RUN.*npm\|RUN.*pip' "$DOCKERFILE" | head -1 | cut -d: -f1)
if [ -n "$COPY_LINE" ] && [ -n "$INSTALL_LINE" ]; then
  if [ "$COPY_LINE" -lt "$INSTALL_LINE" ]; then
    echo "OK: Manifests copied before install (good caching)"
  else
    echo "WARNING: Install runs before manifest copy — poor caching"
  fi
fi

# Check for multi-stage
grep -c 'FROM' "$DOCKERFILE" | xargs -I{} echo "Stages: {}"
[ "$(grep -c 'FROM' "$DOCKERFILE")" -gt 1 ] && echo "OK: Multi-stage build" || echo "INFO: Single-stage build"

# Check for secrets
grep -niE '(ENV|ARG).*(PASSWORD|SECRET|KEY|TOKEN)' "$DOCKERFILE" \
  && echo "WARNING: Possible secret in ENV/ARG — use runtime env or secrets mount"

# Try building (if docker available)
if which docker >/dev/null 2>&1; then
  echo ""
  echo "=== Build Test ==="
  cd "$PROJECT_DIR"
  docker build --no-cache -t test-build . 2>&1 | tail -10
  echo "Build exit code: $?"
fi
```

### 5. Optimize Image Size

```bash
if which docker >/dev/null 2>&1; then
  echo "=== Image Size ==="
  docker images test-build --format '{{.Size}}' 2>/dev/null

  echo ""
  echo "=== Layer Analysis ==="
  docker history test-build --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' 2>/dev/null | head -15
fi
```

## Quality Checklist

- [ ] Base image uses specific version tag (not :latest)
- [ ] Multi-stage build used (build deps not in final image)
- [ ] Dependency manifests copied before source code (layer caching)
- [ ] RUN commands combined with && to minimize layers
- [ ] Non-root USER directive present
- [ ] HEALTHCHECK directive present with appropriate interval
- [ ] .dockerignore excludes .git, node_modules, .env, tests
- [ ] No secrets in ENV or ARG directives
- [ ] Image builds successfully
- [ ] Final image size is reasonable for the application type
