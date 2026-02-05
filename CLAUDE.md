# CLAUDE.md

Guidelines for working on the docker-agent-test codebase.

## Project Overview

This is a Docker-based multi-user agent hosting system built on Arch Linux. It runs multiple autonomous agents (Claude Code instances) in isolated environments under dedicated Linux user accounts with strict security policies and systemd lifecycle management.

**This is an infrastructure/DevOps project, not an application.** Changes should prioritize stability, security, and simplicity.

## Project Structure

```
.
├── Dockerfile                  # Docker image definition (Arch Linux + systemd)
├── docker-compose.yml          # Container orchestration (privileged, systemd init)
├── Makefile                    # Host-side convenience targets
├── README.md                   # Main project documentation
├── USAGE.md                    # Quick start guide
├── home/                       # Persistent agent home directories (mounted as /home)
├── config/
│   ├── README.md               # Configuration documentation
│   ├── skel/                   # Template for new agent homes -> /etc/skel
│   ├── profile.d/              # Global environment scripts -> /etc/profile.d
│   ├── personas/               # Agent persona definitions -> /etc/agent-personas
│   └── systemd/                # Systemd service files
└── scripts/
    ├── README.md               # Scripts documentation
    ├── create-agent.sh         # Create agent user (with optional --persona)
    ├── remove-agent.sh         # Remove agent user
    ├── list-agents.sh          # List agents and status
    ├── run-agent.sh            # Agent entrypoint (called by systemd)
    └── agent-manager.sh        # Boot-time service reconciliation
```

## Documentation Requirements

**Documentation must always be accurate and up to date.** After every change, update all affected documentation before committing.

### What to update and when

| What changed | Update these docs |
|---|---|
| Any script in `scripts/` | `scripts/README.md` — update usage, arguments, behavior, and examples |
| Makefile targets | `scripts/README.md` (Makefile Targets section) and `README.md` (Agent Management Scripts section) |
| Files in `config/` | `config/README.md` and `README.md` (Directory Structure and Customizing Configuration sections) |
| Persona files in `config/personas/` | `config/README.md` and `README.md` |
| Dockerfile or docker-compose.yml | `README.md` and `USAGE.md` |
| New top-level files or directories | `README.md` (Directory Structure section) |
| Changes to the build or run process | `README.md` (Usage section) and `USAGE.md` |
| Security model changes | `README.md` (Notes section) |
| This file (CLAUDE.md) | No additional docs needed |

### Documentation standards

- Keep docs concise and factual. No filler or marketing language.
- Document what the thing does, how to use it, and what arguments it accepts.
- Include examples with realistic values (use agent names like `alice`, `bob`).
- If a script's behavior changes, update both its section in `scripts/README.md` and any references in `README.md`.
- The directory tree in `README.md` must match the actual file structure. Add or remove entries when files are created or deleted.

## Build and Test

```bash
# Build the Docker image
make build

# Start the container
make up

# Open a root shell in the container
make shell

# Create a test agent
make create-agent NAME=testuser

# List agents to verify
make list-agents

# View agent logs
make agent-logs NAME=testuser

# Clean up
make remove-agent NAME=testuser
make down
```

There are no automated tests. Verify changes manually by building the image and running the relevant scripts inside the container.

## Key Constraints

### Security model — do not weaken

- Agents run as unprivileged users in the `agents` group with no sudo access.
- The filesystem is read-only for agents except their own home directory.
- Each agent gets a private `/tmp`, no Linux capabilities, and restricted address families.
- Memory is capped at 512M and CPU at 50% per agent.
- Home directories are mode 700. The `.claude/` directory is root-owned.
- **Do not add sudo access, remove capability restrictions, or weaken the systemd security hardening** without explicit approval.

### Systemd is the process manager

- Every agent runs as a systemd service (`agent@<username>.service`).
- `agent-manager.sh` reconciles services at boot.
- Do not bypass systemd for agent lifecycle management.

### Docker image must be rebuilt for config changes

- Files in `config/` and `scripts/` are baked into the image at build time.
- Remind users to rebuild after changes to these directories.

### Home directories are the only persistent storage

- `/home` is a bind mount from the host. Everything else is ephemeral.
- Do not store important data outside of agent home directories.

## Code Style

### Shell scripts

- Use `#!/bin/bash` and `set -euo pipefail` at the top.
- Validate all user-provided input (usernames, flags).
- Use `readonly` for constants.
- Log to both stdout/stderr (for journald) and file when appropriate.
- Quote all variable expansions: `"$var"`, not `$var`.
- Check for existing scripts in `scripts/` for style reference.

### Makefile

- Each target that wraps a container command uses `docker-compose exec`.
- Agent management targets should require `NAME=<value>` where applicable.
- Keep the help/documentation comments (`## description`) on targets for self-documentation.

### Personas

- `base.md` is applied to all agents. Keep it generic.
- Specialist personas extend, not replace, the base persona.
- Each persona should define: role, core instructions, and output conventions.

## Common Patterns

### Adding a new script

1. Create the script in `scripts/` with proper shebang and `set -euo pipefail`.
2. The Dockerfile copies everything from `scripts/` to `/usr/local/bin/`, so no Dockerfile changes are needed.
3. Add a Makefile target if the script should be callable from the host.
4. Document the script in `scripts/README.md` following the existing format (Usage, Arguments, What it does, Example).
5. Update `README.md` directory tree and any relevant sections.

### Adding a new persona

1. Create a new `.md` file in `config/personas/`.
2. Follow the format of existing personas (role heading, instructions list, output conventions).
3. Update `config/README.md` to list the new persona.
4. No script changes needed — `create-agent.sh` picks up personas by filename.

### Modifying agent service behavior

1. Edit `config/systemd/agent@.service` for service-level changes (resource limits, security, restart policy).
2. Edit `scripts/run-agent.sh` for runtime behavior changes.
3. Update `scripts/README.md` and `README.md` to reflect the changes.
