# Scripts

Management scripts for the multi-user agent hosting system. These scripts are copied to `/usr/local/bin/` inside the container during the Docker build.

## Running From the Host

The management scripts (`create-agent.sh`, `remove-agent.sh`, `list-agents.sh`) detect whether they're running inside the container or on the host. When run from the host, they automatically proxy themselves through `docker exec` into the running container — no need to open a shell first.

```bash
# Run directly from the host — no docker exec needed
./scripts/create-agent.sh alice --persona coder
./scripts/list-agents.sh
./scripts/remove-agent.sh alice

# Or add scripts/ to your PATH for convenience
export PATH="$PWD/scripts:$PATH"
create-agent.sh alice
list-agents.sh
```

By default, commands target the container named `agent-host`. Override this with the `AGENT_HOST_CONTAINER` environment variable:

```bash
AGENT_HOST_CONTAINER=my-container ./scripts/create-agent.sh alice
```

You can also still use the Makefile targets or run the scripts inside the container directly.

## Scripts Overview

| Script | Purpose | Usage |
|--------|---------|-------|
| `create-agent.sh` | Create a new agent user | `create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <KEY>=<val>]` |
| `update-agent.sh` | Update an agent's persona | `update-agent.sh <username> --persona <name>` |
| `remove-agent.sh` | Remove an agent user | `remove-agent.sh <username> [--keep-home]` |
| `list-agents.sh` | List agents and their status | `list-agents.sh` |
| `soft-reset.sh` | Remove all agents and clear logs | `soft-reset.sh [--yes]` |
| `mail-watcher.sh` | inotify-based Maildir watcher (per-agent) | Automatic — launched by `create-agent.sh` / `agent-manager.sh` |
| `manage-api-keys.sh` | Manage per-agent API keys | `manage-api-keys.sh <command> <args>` |
| `send-mail.sh` | Send mail to an agent or alias | `send-mail.sh <recipient> [--from <user>] [--subject <text>] -- <message>` |
| `sync-aliases.sh` | Regenerate mail aliases | `sync-aliases.sh` |
| `snapshot-agents.sh` | Snapshot agent state (host-only) | `snapshot-agents.sh <command> [args]` |
| `load-preset.sh` | Compile a preset JSON into agents + tasks | `load-preset.sh <file.json> [--dry-run] [--skip-existing]` |
| `task.sh` | DAG task board management | `task.sh <add\|list\|ready\|update\|get\|graph> [args]` |
| `artifact.sh` | Shared artifact registry | `artifact.sh <register\|list\|get\|read> [args]` |
| `swarm-orchestrator.sh` | Central DAG coordinator | Automatic — runs as systemd service |
| `stop-swarm.sh` | Cascading cancellation | `stop-swarm.sh [--reason <text>]` |
| `check-health.sh` | Heartbeat-based health monitoring | `check-health.sh` |
| `swarm-status.sh` | Result aggregation | `swarm-status.sh` |
| `agent-loop.mjs` | Single agentic work cycle (Agent SDK) | Automatic — called by `run-agent.sh` |
| `run-agent.sh` | Agent entrypoint (run by systemd) | Automatic — not run manually |
| `agent-manager.sh` | Boot-time service reconciliation | Automatic — runs at container start |
| `sync-api-keys.sh` | Sync env vars to global API keys | Automatic — runs at container start |
| `test-systemd-services.sh` | Verify systemd service management | `test-systemd-services.sh [--verbose]` |

---

## sync-aliases.sh

Regenerates `/etc/smtpd/aliases` from the current group membership. Maintains the `all` group alias, per-persona aliases (e.g., `coder-all`, `manager-all`), and merges in custom aliases from `/etc/smtpd/aliases.static`.

**Usage:**
```bash
# Inside the container
sync-aliases.sh

# From the host via Make
make sync-aliases
```

**Arguments:** None.

**What it does:**
1. Reads all members of the `agents` group
2. Generates the `all` group alias (delivers to everyone)
3. Generates per-persona aliases (`<persona>-all`) for each persona that has members
4. Merges in custom aliases from `/etc/smtpd/aliases.static` (if present)
5. Writes the combined result to `/etc/smtpd/aliases`

Called automatically by `create-agent.sh`, `remove-agent.sh`, `agent-manager.sh`, and `soft-reset.sh`. Can also be run manually via `make sync-aliases`.

**Example:**
```bash
# After creating alice (coder) and bob (manager), /etc/smtpd/aliases contains:
# all: alice, bob
# coder-all: alice
# manager-all: bob
make sync-aliases
```

---

## create-agent.sh

Creates a new agent user with a home directory, `.claude/` configuration, optional persona, optional custom instructions, optional API keys, and a running systemd service.

**Usage:**
```bash
# Inside the container
create-agent.sh <username> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER>=<key>]...

# From the host via Make
make create-agent NAME=<username> [PERSONA=<name>] [INSTRUCTIONS="text"] [API_KEY=<PROVIDER>=<key>]
```

**Arguments:**
- `<username>` (required) — Must start with a lowercase letter or underscore, contain only `[a-z0-9_-]`, and be at most 32 characters.
- `--persona <name>` (optional) — Apply a specialist persona (e.g., `coder`, `researcher`).
- `--instructions <text>` (optional) — Custom instructions appended to the agent's `agents.md` under a "Custom Instructions" section.
- `--api-key <PROVIDER>=<key>` (optional) — Set an API key for this agent. Can be repeated for multiple keys.

**What it does:**
1. Validates the username format
2. Creates a Linux user with home directory populated from `/etc/skel`. The GECOS field is set to the persona's role (e.g., `Software Developer (coder)`) so others can discover it via `getent passwd`
3. Adds the user to the `agents` group and the persona group (e.g., `coder`), creating the persona group if needed
4. Creates the `~/Maildir/{new,cur,tmp}` directory structure for Maildir delivery
5. Regenerates mail aliases (adds the user to the `all` and `<persona>-all` aliases)
6. Builds `agents.md` from base persona + optional specialist persona + optional custom instructions
7. Creates a root-owned `.claude/` directory in the user's home with a default `config.json`
8. Configures git identity (`user.name` from username + persona, `user.email` as `<username>@agent-host`)
9. Sets up `~/.ssh/known_hosts` with host keys for github.com and gitlab.com (best-effort; warns if network is unavailable)
10. Configures per-agent API keys if provided (stored in `.claude/api-keys.env`)
11. Starts the mail watcher process (watches `~/Maildir/new/` for incoming mail via inotify)
12. Waits for systemd to finish booting if needed (ensures `basic.target` is active)
13. Runs `systemctl daemon-reload` to pick up the new service instance
14. Enables and starts `agent@<username>.service` (blocks until active or reports failure with journal entries and service status)

**Examples:**
```bash
# Create agent with default base persona
make create-agent NAME=alice

# Create agent with coder persona
make create-agent NAME=alice PERSONA=coder

# Create agent with API key
make create-agent NAME=bob API_KEY=ANTHROPIC_API_KEY=sk-ant-xxx

# Create agent with custom instructions
make create-agent NAME=carol PERSONA=coder INSTRUCTIONS="Focus on Python backend code"

# Create agent with persona and API key (inside container)
create-agent.sh dave --persona researcher --api-key OPENAI_API_KEY=sk-xxx
```

---

## update-agent.sh

Updates an existing agent's persona. Rebuilds `agents.md`, updates the config, and restarts the agent service so the change takes effect immediately.

**Usage:**
```bash
# Inside the container
update-agent.sh <username> --persona <name>

# From the host via Make
make update-agent NAME=<username> PERSONA=<name>
```

**Arguments:**
- `<username>` (required) — The agent user to update.
- `--persona <name>` (required) — The new persona to apply. Use `base` to reset to the base persona only (removing any specialist persona).

**What it does:**
1. Validates the agent user exists and is in the `agents` group
2. Validates the requested persona exists in `/etc/agent-personas/`
3. Rebuilds `agents.md` from the base persona + the new specialist persona
4. Updates `.claude/config.json` with the new persona name
5. Restarts `agent@<username>.service` to pick up the changes (non-blocking)

**Examples:**
```bash
# Switch an agent to the researcher persona
make update-agent NAME=alice PERSONA=researcher

# Reset an agent to base persona only
make update-agent NAME=alice PERSONA=base
```

---

## remove-agent.sh

Stops the agent's systemd service and removes the user account.

**Usage:**
```bash
# Inside the container
remove-agent.sh <username> [--keep-home]

# From the host via Make
make remove-agent NAME=<username>
```

**Arguments:**
- `<username>` (required) — The agent user to remove.
- `--keep-home` (optional) — Preserve the home directory at `/home/<username>` instead of deleting it.

**What it does:**
1. Stops the mail watcher process (PID-based, via `~/.mail-watcher.pid`)
2. Stops and disables the `agent@<username>.service` systemd service
3. Removes the Linux user account
4. Removes the home directory including Maildir (unless `--keep-home` is specified)
5. Removes empty persona groups (e.g., if the last coder is removed, the `coder` group is deleted)
6. Regenerates mail aliases (removes the user from `all` and `<persona>-all` aliases)

**Example:**
```bash
make remove-agent NAME=alice

# Keep home directory for inspection
docker-compose exec agent-host remove-agent.sh alice --keep-home
```

---

## list-agents.sh

Displays all registered agent users with their service status and home directory status.

**Usage:**
```bash
# Inside the container
list-agents.sh

# From the host via Make
make list-agents
```

**Arguments:** None.

**Output:**
```
USER                 SERVICE      ACTIVE     HOME
----                 -------      ------     ----
alice                agent@alice.service active     /home/alice (yes)
bob                  agent@bob.service   inactive   /home/bob (yes)
```

---

## soft-reset.sh

Removes all agent users and clears systemd journal logs. The container stays running and is ready for new agents immediately afterward. Mail is automatically removed with each agent's home directory (stored as Maildir).

**Usage:**
```bash
# Inside the container
soft-reset.sh [--yes]

# From the host via Make
make soft-reset
```

**Arguments:**
- `--yes` / `-y` (optional) — Skip the confirmation prompt. Used by the Makefile target.

**What it does:**
1. Enumerates all users in the `agents` group
2. Removes each agent (stops agent service + mail watcher, deletes user and home directory including Maildir) via `remove-agent.sh`
3. Regenerates mail aliases (clears the `all` group alias)
4. Rotates and vacuums the systemd journal

**Examples:**
```bash
# From the host (no confirmation prompt)
make soft-reset

# Inside the container (interactive confirmation)
soft-reset.sh

# Inside the container (skip confirmation)
soft-reset.sh --yes
```

---

## send-mail.sh

Sends a local mail message to an agent user or mail alias. By default, mail is sent from root. Use `--from` to send as a specific user — the command runs as that user.

**Usage:**
```bash
# Inside the container
send-mail.sh <recipient> [--from <user>] [--subject <text>] -- <message>

# From the host via Make
make mail TO=<recipient> MSG="<message>" [FROM=<user>] [SUBJECT="<text>"]
```

**Arguments:**
- `<recipient>` (required) — The agent user or mail alias to send to. Must be an existing user or a known alias (e.g., `all`).
- `--from <user>` (optional) — Send mail as this user instead of root. The command logs in as the specified user to send the mail.
- `--subject <text>` (optional) — Set the mail subject line. Defaults to "Message".
- `-- <message>` (required) — The message body. Use `--` to separate the message from options, or pass it as the last argument.

**What it does:**
1. Validates the recipient exists as a user or a known mail alias
2. Validates the sender user exists (if `--from` is specified)
3. Sends the message using the local mail system (s-nail via opensmtpd)
4. If `--from` is specified, runs the mail command as that user via `runuser`
5. If no `--from`, sends as root

**Examples:**
```bash
# Send mail to alice from root
make mail TO=alice MSG="Please check the build logs"

# Send mail to all agents (group alias)
make mail TO=all MSG="Team standup in 5 minutes"

# Send mail to alice from bob
make mail TO=alice FROM=bob MSG="Hey, can you review my PR?"

# Send mail with a custom subject
make mail TO=alice FROM=bob SUBJECT="Code Review" MSG="PR #42 is ready for review"

# Inside the container
send-mail.sh alice -- "Hello from root"
send-mail.sh all -- "Broadcast to everyone"
send-mail.sh alice --from bob --subject "Update" -- "Task complete"
```

---

## snapshot-agents.sh

Snapshots agent runtime state (home directories including Maildir, logs) using a separate git repository. This script runs **on the host only** — it refuses to run inside the container.

The snapshot repo uses a separate `GIT_DIR` (`.agent-snapshots/`) that is completely independent from the main source repo. It is not mounted into the container, so agents never see it.

**Usage:**
```bash
# From the host
./scripts/snapshot-agents.sh <command> [args]

# Via Make
make snapshot-init
make snapshot
make snapshot MSG="after task 3"
make snapshot-log
make snapshot-diff
make snapshot-status
```

**Commands:**

| Command | Description | Example |
|---------|-------------|---------|
| `init` | Initialize the snapshot repository | `snapshot-agents.sh init` |
| `create` | Take a snapshot (default message: timestamp) | `snapshot-agents.sh create "checkpoint"` |
| `log` | Show snapshot history | `snapshot-agents.sh log -5` |
| `diff` | Show changes since last snapshot | `snapshot-agents.sh diff HEAD~1` |
| `show` | Show a specific snapshot | `snapshot-agents.sh show HEAD` |
| `status` | Summarize what changed since last snapshot | `snapshot-agents.sh status` |
| `help` | Show usage information | `snapshot-agents.sh help` |

**What it tracks:**
- `home/` — Agent home directories (work output, logs, config, Maildir)
- `log/` — System logs (excluding binary journal files)

**What it excludes:**
- All source code and config (managed by the main repo)
- `.gitkeep` files (belong to the main repo)
- `log/journal/` (binary systemd journal — not useful in git)

**How it works:**

The snapshot repo is a bare git repository at `.agent-snapshots/`. All git operations use explicit `--git-dir` and `--work-tree` flags to keep it separate from the main repo's `.git`. The `.agent-snapshots` directory is listed in the main repo's `.gitignore`.

**Examples:**
```bash
# First-time setup
./scripts/snapshot-agents.sh init

# Take snapshots as agents work
make snapshot MSG="alice finished onboarding"
make snapshot MSG="bob completed code review"

# Review what changed
make snapshot-status
make snapshot-diff

# Browse history
make snapshot-log
./scripts/snapshot-agents.sh show HEAD~2 --stat
```

---

## load-preset.sh

Compiles a declarative preset JSON file into a running swarm. Reads the preset and translates it into sequential calls to `create-agent.sh`, `task.sh add`, and `send-mail.sh`. The compiler is a thin translation layer — all intelligence lives in the preset file, not in the script.

**Usage:**
```bash
# Inside the container
load-preset.sh <file.json> [--dry-run] [--skip-existing]

# From the host via Make
make load-preset FILE=presets/bug-triage.json [DRY_RUN=1] [SKIP_EXISTING=1]
```

**Arguments:**
- `<file.json>` (required) — Path to the preset JSON file.
- `--dry-run` (optional) — Show what would happen without executing. Prints the commands that would be run.
- `--skip-existing` (optional) — Skip agent creation if the agent user already exists (useful for re-loading presets).

**Compilation phases:**
1. **Validate** — Parses JSON, checks required fields, validates DAG (no cycles, valid references)
2. **Create agents** — Calls `create-agent.sh` for each agent in the preset
3. **Create tasks** — Calls `task.sh add` for each task, wiring up `blocked_by` dependencies and owners
4. **Send mail** — Calls `send-mail.sh` for each kickoff message
5. **Save state** — Records the loaded preset for reference

**Variable substitution:** Presets use `${VAR}` placeholders in task descriptions and mail bodies. These are replaced with environment variables at load time:
```bash
BUG_TITLE="Login timeout" BUG_DESCRIPTION="Users report 30s hangs" \
  load-preset.sh presets/bug-triage.json
```

**Preset JSON format:**
```json
{
  "name": "preset-name",
  "description": "What this preset does",
  "agents": [
    { "name": "alice", "persona": "coder", "instructions": "optional custom instructions" }
  ],
  "tasks": [
    {
      "id": "task-1",
      "title": "Task title",
      "description": "Detailed description with ${VARIABLES}",
      "owner": "alice",
      "blocked_by": []
    }
  ],
  "mail": [
    { "to": "alice", "subject": "Kickoff", "body": "Your task is ready" }
  ]
}
```

**Examples:**
```bash
# Preview what a preset will do
make load-preset FILE=presets/feature-build.json DRY_RUN=1

# Load a preset with variables
FEATURE_NAME="Dark mode" REPO_PATH="/home/shared/webapp" \
  make load-preset FILE=presets/feature-build.json

# Re-load a preset without recreating existing agents
make load-preset FILE=presets/bug-triage.json SKIP_EXISTING=1
```

---

## task.sh

Manages the shared DAG task board at `/home/shared/tasks.jsonl`. The task board is append-only JSONL — the last entry per task ID represents the current state.

**Usage:**
```bash
task.sh <command> [args]
```

**Commands:**

| Command | Description | Example |
|---------|-------------|---------|
| `add` | Add a new task | `task.sh add "Build engine" --owner alice --blocked-by task-1` |
| `list` | List all tasks | `task.sh list [--owner alice] [--status pending]` |
| `ready` | List tasks ready to start (no unfinished blockers) | `task.sh ready` |
| `update` | Update a task's status | `task.sh update task-abc completed` |
| `get` | Get details for a task | `task.sh get task-abc` |
| `graph` | Show the task dependency graph | `task.sh graph` |

---

## artifact.sh

Manages the shared artifact registry for inter-agent file sharing. Artifacts are files in `/home/shared/` that agents can produce and consume.

**Usage:**
```bash
artifact.sh <command> [args]
```

**Commands:**

| Command | Description | Example |
|---------|-------------|---------|
| `register` | Register a shared artifact | `artifact.sh register reports/output.csv` |
| `list` | List all registered artifacts | `artifact.sh list` |
| `get` | Get metadata for an artifact | `artifact.sh get reports/output.csv` |
| `read` | Read artifact contents | `artifact.sh read reports/output.csv` |

---

## agent-loop.mjs

A Node.js script that performs a single agentic work cycle using the Claude Agent SDK (`@anthropic-ai/claude-agent-sdk`). It is called by `run-agent.sh` on each cycle and is **not intended to be run manually**.

**What it does:**
1. Sends a prompt to Claude instructing it to follow the agent's `CLAUDE.md` operating instructions
2. Claude checks for new mail, reads `TODO.md`, works on tasks, updates `MEMORY.md`, and reports back
3. The SDK handles tool execution automatically (Bash, Read, Write, Edit, Glob, Grep)
4. Logs assistant output snippets and cycle results to stdout (captured by journald)
5. Exits with code 0 on success, 1 on failure

**Environment variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | (required) | API key for Claude |
| `AGENT_USER` | `$USER` | Agent username (set by `run-agent.sh`) |
| `AGENT_MODEL` | `claude-opus-4-6` | Claude model to use |
| `AGENT_MAX_TURNS` | `50` | Maximum conversation turns per cycle |
| `AGENT_CYCLE_TIMEOUT_MS` | `300000` | Cycle timeout in milliseconds (5 min) |

**Security:** Runs with `permissionMode: "bypassPermissions"` since there is no human to approve tool use. Agents are sandboxed by Unix permissions (no sudo, home-directory-only writes).

---

## run-agent.sh

The entrypoint script executed by each agent's systemd service (`agent@<username>.service`). It runs as the agent user with their home directory as the working directory.

This script is **not intended to be run manually** — it is invoked automatically by systemd.

**What it does:**
1. Logs startup information (user, home directory, PID, config file status)
2. Checks for `agents.md` and `.claude/config.json` in the user's home
3. Loads API keys from global and per-agent configuration (see API Key Loading below)
4. Runs an autonomous work cycle loop: invokes `agent-loop.mjs` on each iteration, then waits using `inotifywait` on `~/Maildir/new/` (wakes immediately on new mail, or after the configured interval)

**API Key Loading:**
1. First loads global defaults from `/etc/agent-api-keys/global.env` (if exists)
2. Then loads per-agent overrides from `~/.claude/api-keys.env` (if exists)
3. Per-agent keys take precedence over global keys
4. All loaded keys are exported as environment variables

**Cycle loop configuration:**
| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_CYCLE_INTERVAL` | `300` | Maximum seconds between work cycles (new mail triggers immediate wakeup) |

**Logs:** Output goes to both the systemd journal and `/home/<username>/.agent.log`. View logs with:
```bash
make agent-logs NAME=alice
# or inside the container:
journalctl -u agent@alice.service -f
```

---

## agent-manager.sh

Boot-time reconciliation script that ensures all registered agents have their services running. Executed once at container startup by the `agent-manager.service` systemd unit.

This script is **not intended to be run manually**.

**What it does:**
1. Enumerates all users in the `agents` group
2. For each user, verifies the account and home directory still exist
3. Creates `~/Maildir/{new,cur,tmp}` if missing (migration support)
4. Enables and queues start for `agent@<username>.service` (non-blocking) and launches the mail watcher via `nohup su`
5. Regenerates mail aliases to match current agent membership
6. Reports a summary of started vs. failed agents

---

## mail-watcher.sh

An inotify-based watcher that monitors each agent's `~/Maildir/new/` directory for incoming mail. When OpenSMTPD delivers a message, this script moves it from `new/` to `cur/` (standard Maildir "seen" transition) and logs the event. This prevents file buildup in `new/` and provides the foundation for Phase 2 work-queue integration.

Launched via `nohup su` by `create-agent.sh` and `agent-manager.sh` — **not intended to be run manually**. PID tracked at `/run/mail-watcher-<username>.pid`.

**What it does:**
1. Writes its own PID to `~/.mail-watcher.pid` (for reliable cleanup)
2. Ensures the `~/Maildir/{new,cur,tmp}` directory structure exists
3. Watches `~/Maildir/new/` using `inotifywait` for `CREATE` and `MOVED_TO` events
4. Logs each delivery event (messages stay in `new/` for the MUA to handle)

**Logs:**
```bash
# View mail watcher log
cat /var/log/mail-watcher-alice.log

# Or tail it live
tail -f /var/log/mail-watcher-alice.log
```

---

## manage-api-keys.sh

Manages per-agent API keys. Keys are stored in `~/.claude/api-keys.env` (root-owned, agent-readable).

**Usage:**
```bash
# Inside the container
manage-api-keys.sh <command> [args...]

# From the host via Make
make set-api-key NAME=alice KEY=ANTHROPIC_API_KEY=sk-xxx
make get-api-keys NAME=alice
make remove-api-key NAME=alice KEY=OPENAI_API_KEY
make clear-api-keys NAME=alice
make list-providers
```

**Commands:**

| Command | Description | Example |
|---------|-------------|---------|
| `set` | Set one or more API keys | `manage-api-keys.sh set alice ANTHROPIC_API_KEY=sk-xxx` |
| `get` | Show API keys (values masked) | `manage-api-keys.sh get alice` |
| `remove` | Remove specific API keys | `manage-api-keys.sh remove alice OPENAI_API_KEY` |
| `clear` | Remove all API keys | `manage-api-keys.sh clear alice` |
| `list-providers` | List known provider names | `manage-api-keys.sh list-providers` |

**Examples:**
```bash
# Set multiple keys at once
manage-api-keys.sh set bob OPENAI_API_KEY=sk-xxx MISTRAL_API_KEY=xxx

# View keys for an agent (masked output)
manage-api-keys.sh get bob
# Output: OPENAI_API_KEY = sk-x...xxxx

# Remove a specific key
manage-api-keys.sh remove bob MISTRAL_API_KEY
```

**Security:**
- API key files are root-owned but readable by the agent user (mode 640)
- Values are masked when displayed (only first/last 4 chars shown)
- Files are stored in the root-owned `.claude/` directory

---

## sync-api-keys.sh

Syncs API key environment variables from the container's environment to the global configuration file. Executed once at container startup by the `api-keys-sync.service` systemd unit.

This script is **not intended to be run manually**.

**What it does:**
1. Reads API key environment variables passed via `docker-compose.yml`
2. Merges them with any static configuration from the Docker image
3. Writes the combined result to `/etc/agent-api-keys/global.env`
4. Sets secure permissions (root-only, mode 600)

This allows you to pass API keys from your host environment without baking them into the Docker image:
```bash
# On the host
export ANTHROPIC_API_KEY=sk-ant-xxx
docker-compose up -d
# Key is now available to all agents
```

---

## test-systemd-services.sh

Verifies that systemd service management is functional inside the container. Tests cgroup v2 infrastructure, systemd health, service lifecycle (create/start/stop/restart), resource limits (MemoryMax, CPUQuota), journal logging, and boot services.

**Usage:**
```bash
# Inside the container
test-systemd-services.sh [--verbose]

# From the host via Make
make test-systemd
make test-systemd VERBOSE=1
```

**Arguments:**
- `--verbose` / `-v` (optional) — Show additional diagnostic output for each test.

**What it tests:**

| Phase | Tests |
|-------|-------|
| 1. cgroup v2 infrastructure | Filesystem type, writable hierarchy, child cgroup creation, memory/cpu controllers |
| 2. systemd health | PID 1 is systemd, basic.target/multi-user.target active, system state, journald |
| 3. Agent service template | `agent@.service` exists, `run-agent.sh` is executable |
| 4. Service lifecycle | daemon-reload, enable, start, list, stop, restart, disable |
| 5. Resource limits | MemoryMax=512M, CPUQuota=50%, NoNewPrivileges, RestrictSUIDSGID |
| 6. Journal logging | Journal entries recorded for agent service |
| 7. Boot services | agent-manager.service, api-keys-sync.service |

**Exit codes:**
- `0` — All tests passed
- `1` — One or more tests failed

The test creates a temporary user (`__test_systemd__`) and cleans it up automatically when done.

**Example output:**
```
systemd Service Management Test Harness
Platform: Linux 6.10.14-linuxkit x86_64
systemd:  systemd 256 (256.10-1-arch)

Phase 1: cgroup v2 infrastructure
  ✓ cgroup v2 filesystem detected (cgroup2fs)
  ✓ cgroup hierarchy is writable
  ✓ Can create child cgroups
  ✓ Memory controller available
  ✓ CPU controller available

Phase 2: systemd health
  ✓ systemd is PID 1
  ...

Summary
  Total: 24 tests
  Passed: 24

PASS — All tests passed. systemd service management is functional.
```

---

## Makefile Targets

The `Makefile` in the project root provides convenience wrappers (the container must be running):

**Agent Management:**
```bash
make create-agent NAME=foo                        # Create agent with base persona
make create-agent NAME=foo PERSONA=coder          # Create agent with specialist persona
make create-agent NAME=foo INSTRUCTIONS="Focus on tests"     # Create with custom instructions
make create-agent NAME=foo API_KEY=ANTHROPIC_API_KEY=sk-xxx  # Create with API key
make update-agent NAME=foo PERSONA=coder          # Update an agent's persona
make remove-agent NAME=foo                        # Remove an agent
make list-agents                                  # List all agents and status
make list-personas                                # List available personas
make agent-logs NAME=foo                          # Tail systemd journal logs
make agent-shell NAME=foo                         # Open a shell as the agent user
make mail TO=alice MSG="Hello"                    # Send mail to agent (from root)
make mail TO=all MSG="Hi everyone"                # Send mail to all agents (group alias)
make mail TO=alice FROM=bob MSG="Hi"              # Send mail as a specific user
make mail TO=alice FROM=bob SUBJECT="Re: Task" MSG="Done"  # With subject
make sync-aliases                                 # Regenerate mail aliases
make soft-reset                                  # Remove all agents and clear logs
```

**API Key Management:**
```bash
make set-api-key NAME=foo KEY=ANTHROPIC_API_KEY=sk-xxx  # Set API key for agent
make get-api-keys NAME=foo                              # Show API keys (masked)
make remove-api-key NAME=foo KEY=OPENAI_API_KEY         # Remove specific key
make clear-api-keys NAME=foo                            # Remove all keys
make list-providers                                     # List known provider names
```

**Presets:**
```bash
make list-presets                                       # List available workflow presets
make load-preset FILE=presets/bug-triage.json           # Load a preset (create agents + tasks + mail)
make load-preset FILE=presets/bug-triage.json DRY_RUN=1 # Preview without executing
make load-preset FILE=presets/feature-build.json SKIP_EXISTING=1  # Skip existing agents
```

**Testing:**
```bash
make test-systemd                      # Verify systemd service management works
make test-systemd VERBOSE=1            # Verbose output with diagnostics
```

**Snapshots (host-side, container not required):**
```bash
make snapshot-init                      # Initialize the snapshot repo
make snapshot                           # Take a snapshot of agent state
make snapshot MSG="after task 3"        # Take a snapshot with a custom message
make snapshot-log                       # Show snapshot history
make snapshot-diff                      # Show changes since last snapshot
make snapshot-status                    # Summarize changes since last snapshot
```
