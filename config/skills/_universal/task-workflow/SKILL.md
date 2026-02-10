---
name: task-workflow
description: >
  Standard procedure for working through tasks on the shared task board.
  Use at the start of every work cycle.
---

## When to Use

Use at the start of every work cycle and whenever you need to find, claim, or complete tasks on the shared task board.

## Procedure

1. Check for ready tasks:
   ```bash
   task.sh ready --owner "$(whoami)"
   ```

2. If a task is ready, claim it:
   ```bash
   task.sh update <task-id> --status in_progress
   ```

3. Read the task details for instructions:
   ```bash
   task.sh get <task-id>
   ```
   The `description` field contains your detailed instructions, including
   input file paths and expected output locations.

4. Do the work. Follow the task description precisely.

5. When finished, write outputs to `/home/shared/` and register them:
   ```bash
   artifact.sh register <relative-path> --description "what this file is"
   ```

6. Mark the task complete with a summary:
   ```bash
   task.sh update <task-id> --status completed --result "Brief summary of what was produced and where"
   ```

7. If you cannot complete the task, mark it failed:
   ```bash
   task.sh update <task-id> --status failed --result "What went wrong and what was tried"
   ```

## Important

- Never start a task that `task.sh ready` does not show -- its blockers are not met yet.
- Always register output files as artifacts so downstream agents can discover them.
- The `--result` text is read by other agents and the orchestrator. Be specific.
