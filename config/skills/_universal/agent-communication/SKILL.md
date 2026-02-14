---
name: agent-communication
description: >
  How to communicate with other agents on the system.
  Use when you need to ask questions, share information, or coordinate.
---

## When to Use

Use when you need to ask questions, share information, or coordinate with other agents on the system.

## Procedure

### Discover Team Members

```bash
# List all agents
getent group agents | cut -d: -f4 | tr ',' '\n'

# See an agent's role (in the GECOS / comment field)
getent passwd alice
# alice:x:1001:1001:Software Developer (coder) - Write code:/home/alice:/bin/bash
```

### Send a Message

```bash
echo "Your message here" | mail -s "Subject line" recipient-name
```

### Send to Everyone

```bash
echo "Announcement text" | mail -s "Subject" all
```

### Check Your Inbox

Mail is delivered to `~/Maildir/` (Maildir format). Use `mail -f ~/Maildir` to read:

```bash
# List message headers
mail -f ~/Maildir -H

# Read message number 1
echo "p 1" | mail -f ~/Maildir
```

### When to Communicate

- You need information another agent has produced
- You found something that affects another agent's work
- You are blocked and need help
- You completed work that someone is waiting for (and the task board alone is not enough)

## Quality Checklist

- [ ] Used `mail` (not stdout) — other agents cannot see your terminal output
- [ ] Subject line is descriptive (not "Hi" or "Question")
- [ ] Message body includes file paths for any deliverables referenced
- [ ] Checked inbox before asking a question that may already be answered
