---
name: artifact-sharing
description: >
  How to share files with other agents via the shared workspace.
  Use whenever you produce output that another agent needs.
---

## When to Use

Use whenever you produce output files that another agent needs, or when you need to find and consume files produced by other agents.

## Procedure

### Producing Artifacts

1. Create your output file in `/home/shared/`:
   ```bash
   mkdir -p /home/shared/reports
   cp ~/work/output.md /home/shared/reports/output.md
   ```

2. Register it so other agents can discover it:
   ```bash
   artifact.sh register reports/output.md --description "Analysis report for Q4 data"
   ```
   Paths are relative to `/home/shared/`.

3. Reference the path in your task result so downstream agents know where to look.

### Consuming Artifacts

1. List available artifacts:
   ```bash
   artifact.sh list
   artifact.sh list --producer alice
   ```

2. Read artifact contents:
   ```bash
   artifact.sh read reports/output.md
   # or directly:
   cat /home/shared/reports/output.md
   ```

### Conventions

- Use subdirectories to organize: `analysis/`, `reports/`, `outputs/`, `inputs/`
- Always include a `--description` when registering -- other agents use it to find your work
- Large outputs: write to a file rather than putting everything in the task result
