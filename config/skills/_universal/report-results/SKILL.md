---
name: report-results
description: >
  How to report results back to the team after completing work.
  Use after finishing any task or request.
---

## When to Use

Use after finishing any task or mail request to report results clearly so downstream agents and the orchestrator can act on your output.

## Procedure

### After Completing a Task Board Task

1. Update the task status with a clear summary:
   ```bash
   task.sh update <task-id> --status completed \
     --result "Produced /home/shared/analysis/report.md covering X, Y, Z. Found 3 critical issues."
   ```

2. If relevant, email the person who will consume your output:
   ```bash
   echo "Completed the analysis. Results at /home/shared/analysis/report.md" | \
     mail -s "Analysis complete" downstream-agent
   ```

### After Completing a Mail Request

Reply directly to the sender:
```bash
mail -s "Re: Original subject" sender-name <<'EOF'
Summary of what was done.

Results are at: /home/shared/path/to/output.md
EOF
```

### Result Summary Format

A good result summary includes:
- What was produced (file paths)
- Key findings or metrics (numbers, not vague statements)
- Any issues or caveats the next agent should know about
