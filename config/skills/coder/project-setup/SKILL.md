---
name: project-setup
description: Set up a new coding project with proper structure, dependencies, and configuration
---

# Project Setup

## When to Use

Use this skill when you need to create a new project from scratch or scaffold a new module within an existing workspace.

## Procedure

### 1. Determine Project Type and Requirements

Read the task description to identify:
- Language/runtime (Node.js, Python, shell, etc.)
- Project type (library, CLI tool, service, script)
- Any specified dependencies or frameworks

### 2. Create Directory Structure

```bash
PROJECT_NAME="my-project"
PROJECT_DIR=~/workspace/$PROJECT_NAME

mkdir -p "$PROJECT_DIR"/{src,tests,config}
cd "$PROJECT_DIR"
```

For a Node.js project:
```bash
mkdir -p "$PROJECT_DIR"/{src,tests,config,scripts}
```

For a Python project:
```bash
mkdir -p "$PROJECT_DIR"/{src/$PROJECT_NAME,tests,config,scripts}
touch "$PROJECT_DIR/src/$PROJECT_NAME/__init__.py"
```

### 3. Initialize Package Manager

**Node.js:**
```bash
cd "$PROJECT_DIR"
cat > package.json <<'EOF'
{
  "name": "PROJECT_NAME",
  "version": "0.1.0",
  "description": "",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "test": "node --test tests/"
  },
  "keywords": [],
  "license": "UNLICENSED"
}
EOF
sed -i "s/PROJECT_NAME/$PROJECT_NAME/" package.json
npm install
```

**Python:**
```bash
cd "$PROJECT_DIR"
cat > pyproject.toml <<EOF
[project]
name = "$PROJECT_NAME"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = []

[project.optional-dependencies]
dev = ["pytest"]
EOF
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

### 4. Create Initial Files

**README.md:**
```bash
cat > README.md <<EOF
# $PROJECT_NAME

## Overview

Brief description of what this project does.

## Setup

\`\`\`bash
# installation steps
\`\`\`

## Usage

\`\`\`bash
# usage example
\`\`\`
EOF
```

**.gitignore:**
```bash
cat > .gitignore <<'EOF'
node_modules/
.venv/
__pycache__/
*.pyc
.env
dist/
build/
*.egg-info/
.DS_Store
coverage/
*.log
EOF
```

**Entry point (Node.js):**
```bash
cat > src/index.js <<'EOF'
#!/usr/bin/env node
"use strict";

function main() {
  console.log("Hello from PROJECT_NAME");
}

main();
EOF
chmod +x src/index.js
```

**Entry point (Python):**
```bash
cat > src/$PROJECT_NAME/main.py <<'EOF'
#!/usr/bin/env python3
"""Main entry point."""

def main():
    print("Hello from PROJECT_NAME")

if __name__ == "__main__":
    main()
EOF
chmod +x src/$PROJECT_NAME/main.py
```

### 5. Initialize Git

```bash
cd "$PROJECT_DIR"
git init
git add -A
git commit -m "Initial project scaffold for $PROJECT_NAME"
```

### 6. Share to Shared Workspace (if needed by other agents)

```bash
cp -r "$PROJECT_DIR" /home/shared/
# Register as artifact so other agents can find it
bash /home/shared/scripts/artifact.sh register \
  --name "$PROJECT_NAME" \
  --type "project" \
  --path "/home/shared/$PROJECT_NAME" \
  --description "Project scaffold for $PROJECT_NAME"
```

### 7. Validate

```bash
cd "$PROJECT_DIR"
# Verify structure
tree -L 2 --dirsfirst
# Verify it runs
npm start 2>&1 || python3 -m $PROJECT_NAME 2>&1
# Verify tests pass (even if trivial)
npm test 2>&1 || python3 -m pytest tests/ 2>&1
```

## Checklist Before Marking Complete

- [ ] Directory structure created and logical
- [ ] Package manager initialized with valid config
- [ ] Entry point exists and runs without error
- [ ] .gitignore covers common artifacts
- [ ] README.md has at least Overview and Usage sections
- [ ] Git initialized with clean first commit
- [ ] Shared to /home/shared/ if other agents need access
