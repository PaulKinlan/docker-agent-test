# docker-agent-test

A Docker setup using the latest Arch Linux with customizable configuration files.

## Features

- Uses the latest Arch Linux base image
- Home directory mounted from the repository (`./home`)
- System logs mounted to `./log` for external observation (journald, smtpd)
- Mail spool mounted to `./mail` for reading inter-agent messages from the host
- Customizable `/etc/skel` files for new users
- Customizable `/etc/profile.d` scripts for global environment setup
- Systemd support enabled
- Development tools: git, python, node (system + nvm), base-devel (gcc, make), curl, wget, jq, ripgrep, tree, openssh, unzip
- Node Version Manager (nvm) installed system-wide with LTS pre-installed
- Multi-LLM API key management (global and per-agent)
- Support for Anthropic, OpenAI, Google, Mistral, and many other providers
- Local mail system for inter-agent communication (opensmtpd + s-nail)

## Directory Structure

```
.
├── Dockerfile              # Main Dockerfile using archlinux:latest
├── docker-compose.yml      # Docker Compose configuration
├── Makefile                # Convenience targets for container and agent management
├── home/                   # Persistent agent home directories (mounted as /home)
├── log/                    # System logs from container (mounted as /var/log)
│   └── journal/            # Systemd journal (persistent agent service logs)
├── mail/                   # Mail spool from container (mounted as /var/spool/mail)
├── config/
│   ├── api-keys/          # API key configuration (copied to /etc/agent-api-keys)
│   │   ├── global.env.template  # Template for global API keys
│   │   └── .gitignore           # Prevents committing actual keys
│   ├── personas/          # Agent persona definitions (copied to /etc/agent-personas)
│   │   ├── base.md              # Base persona (applied to all agents)
│   │   ├── coder.md             # Software development specialist
│   │   ├── researcher.md        # Research and information gathering
│   │   └── ...                  # 11 more specialist personas
│   ├── skills/            # Skill packs (copied to /etc/agent-skills)
│   │   ├── _universal/          # Skills installed to every agent
│   │   │   ├── task-workflow/   # Check ready tasks, claim, work, complete
│   │   │   ├── artifact-sharing/# Produce/consume shared files
│   │   │   ├── report-results/  # Write good result summaries
│   │   │   └── agent-communication/ # Discover team, send mail, check inbox
│   │   ├── coder/               # Skills for coder persona
│   │   ├── researcher/          # Skills for researcher persona
│   │   └── ...                  # 11 more persona skill packs
│   ├── smtpd/             # OpenSMTPD configuration (copied to /etc/smtpd)
│   │   └── aliases.static       # Custom per-agent mail aliases
│   ├── skel/              # Files copied to /etc/skel (template for new users)
│   │   ├── .bashrc        # Default bash configuration
│   │   ├── .bash_profile  # Default bash login configuration
│   │   ├── CLAUDE.md      # Default operating instructions for agents
│   │   ├── agents.md      # Agent persona configuration template
│   │   ├── TODO.md        # Starter task list for agents
│   │   ├── MEMORY.md      # Starter persistent memory file
│   ├── profile.d/         # Files copied to /etc/profile.d (global environment)
│   │   ├── agent-env.sh   # Global agent environment setup
│   │   └── nvm.sh         # Loads nvm (Node Version Manager) for all users
│   └── systemd/           # Systemd service definitions
│       ├── agent@.service          # Per-agent service template
│       ├── agent-manager.service   # Boot-time reconciliation service
│       └── api-keys-sync.service   # Boot-time API key sync service
├── presets/               # Workflow preset library (declarative swarm configs)
│   ├── codebase-audit.json     # Security + quality audit
│   ├── content-pipeline.json   # Content creation pipeline
│   ├── bug-triage.json         # Bug investigation → fix → verify → postmortem
│   ├── feature-build.json      # Spec → design → implement → review → docs
│   ├── security-hardening.json # Scan → threat model → parallel fixes → report
│   ├── api-design.json         # Requirements → design → implement → test → docs
│   ├── data-pipeline.json      # Ingest → validate → analyze → report
│   ├── project-kickoff.json    # Design → scaffold+CI → tests → readme
│   ├── migration-plan.json     # Assess → research → migrate → test → guide
│   └── incident-response.json  # Triage → diagnose → hotfix → verify → postmortem
├── shared/                # Shared artifacts directory (mounted as /home/shared)
├── tui/                   # Interactive TUI (Node.js + Ink, host-side only)
│   ├── package.json       # Dependencies (ink, react)
│   ├── cli.mjs            # Entry point
│   ├── app.mjs            # Root component
│   ├── components/        # UI components (Prompt, Output, StatusBar, Banner)
│   └── lib/               # Logic (commands, executor, container, completions)
├── cli.mjs                # Root-level TUI wrapper (runs tui/cli.mjs)
└── scripts/               # Management scripts (copied to /usr/local/bin)
    ├── create-agent.sh    # Create a new agent user
    ├── update-agent.sh    # Update an agent's persona
    ├── remove-agent.sh    # Remove an agent user
    ├── list-agents.sh     # List agents and their status
    ├── manage-api-keys.sh # Manage per-agent API keys
    ├── soft-reset.sh      # Remove all agents, clear logs and mail
    ├── send-mail.sh       # Send mail to an agent user or alias
    ├── sync-aliases.sh    # Regenerate mail aliases from agents group
    ├── snapshot-agents.sh # Snapshot agent state (host-only)
    ├── load-preset.sh     # Compile a preset JSON into running agents + tasks
    ├── task.sh            # DAG task board (add/list/ready/update/get/graph)
    ├── artifact.sh        # Shared artifact registry (register/list/get/read)
    ├── swarm-orchestrator.sh  # Central DAG coordinator
    ├── stop-swarm.sh      # Cascading cancellation of all agents
    ├── check-health.sh    # Heartbeat-based health monitoring
    ├── swarm-status.sh    # Result aggregation (tasks + health + costs)
    ├── agent-loop.mjs     # Single agentic work cycle (Claude Agent SDK)
    ├── run-agent.sh       # Agent entrypoint (run by systemd)
    ├── agent-manager.sh   # Boot-time service reconciliation
    └── sync-api-keys.sh   # Boot-time API key environment sync
```

## Usage

### Quick Start

Using Docker Compose:
```bash
# Build the image
docker-compose build

# Start the container
docker-compose up -d

# Access the container
docker-compose exec agent-host /bin/bash

# Stop the container
docker-compose down
```

Using Docker directly:
```bash
# Build the image
docker build -t arch-dev .

# Run the container with home directory mounted
docker run -it -v $(pwd)/home:/home/user arch-dev
```

### Agent Management Scripts

The `scripts/` directory contains management scripts that are installed to `/usr/local/bin/` inside the container. See [`scripts/README.md`](scripts/README.md) for full documentation.

The management scripts can be run **directly from the host** or inside the container — they auto-detect their environment and proxy through `docker exec` when needed.

**From the host (direct):**
```bash
./scripts/create-agent.sh alice --persona coder
./scripts/update-agent.sh alice --persona researcher
./scripts/list-agents.sh
./scripts/remove-agent.sh alice --keep-home
```

**From the host (via Make):**
```bash
make create-agent NAME=alice
make update-agent NAME=alice PERSONA=researcher
make list-agents
make remove-agent NAME=alice
```

**Inside the container:**
```bash
create-agent.sh alice
update-agent.sh alice --persona researcher
list-agents.sh
remove-agent.sh alice
```

To target a different container name, set `AGENT_HOST_CONTAINER`:
```bash
AGENT_HOST_CONTAINER=my-container ./scripts/create-agent.sh alice
```

**View agent logs:**
```bash
make agent-logs NAME=alice
```
Tails the systemd journal for the specified agent.

**Open a shell as an agent:**
```bash
make agent-shell NAME=alice
```

**Send mail to an agent or group:**
```bash
# Send from root (default)
make mail TO=alice MSG="Please check the build logs"

# Send to all agents at once (group alias)
make mail TO=all MSG="Team standup in 5 minutes"

# Send from another agent
make mail TO=alice FROM=bob MSG="Can you review my PR?"

# With a custom subject
make mail TO=alice FROM=bob SUBJECT="Code Review" MSG="PR #42 is ready"
```

### Mail Aliases

The system automatically maintains mail aliases that are updated whenever users are created or removed:

- **`all`** — delivers to every registered user
- **`<persona>-all`** — delivers to everyone with a given persona (e.g., `coder-all`, `manager-all`)

```bash
# Mail everyone
make mail TO=all MSG="Team standup in 5 minutes"

# Mail all coders
make mail TO=coder-all MSG="Please review the new coding standards"
```

Custom aliases (e.g., `devs: alice, bob`) can be defined in `config/smtpd/aliases.static`. After editing, rebuild the image and run `make sync-aliases`.

To manually regenerate aliases:
```bash
make sync-aliases
```

### API Key Management

The system supports multiple LLM providers with both global (all agents) and per-agent API key configuration.

#### Global API Keys (All Agents)

Option 1: Pass from host environment (recommended):
```bash
# Set on host before starting container
export ANTHROPIC_API_KEY=sk-ant-xxx
export OPENAI_API_KEY=sk-xxx
docker-compose up -d
```

Option 2: Bake into image (for private images):
```bash
cp config/api-keys/global.env.template config/api-keys/global.env
# Edit global.env to set your keys
docker-compose build
```

#### Per-Agent API Keys

Set keys when creating an agent:
```bash
make create-agent NAME=alice API_KEY=ANTHROPIC_API_KEY=sk-ant-xxx
```

Or manage keys for existing agents:
```bash
make set-api-key NAME=alice KEY=ANTHROPIC_API_KEY=sk-ant-xxx
make set-api-key NAME=alice KEY=OPENAI_API_KEY=sk-xxx
make get-api-keys NAME=alice
make remove-api-key NAME=alice KEY=OPENAI_API_KEY
make clear-api-keys NAME=alice
```

Per-agent keys override global keys. See [`scripts/README.md`](scripts/README.md) for full documentation.

#### Supported Providers

Anthropic, OpenAI, Google/Gemini, Mistral, Cohere, Groq, Together.ai, Fireworks.ai, Perplexity, Replicate, Hugging Face, AWS Bedrock, Azure OpenAI.

Run `make list-providers` to see all supported provider names.

#### How Agents Run

Each agent runs as its own systemd service (`agent@<username>.service`) which executes `run-agent.sh` as the agent user. On each cycle, the agent invokes `agent-loop.mjs` (powered by the Claude Agent SDK) which checks for new mail, processes pending tasks from `TODO.md`, reports results, and updates `MEMORY.md`. Cycles run every 5 minutes by default (configurable via `AGENT_CYCLE_INTERVAL`). All output is logged to both the systemd journal and `/home/<username>/.agent.log`.

At container boot, `agent-manager.sh` automatically reconciles all users in the `agents` group, ensuring their services are enabled and started.

### Workflow Presets

Presets are declarative JSON files that describe a complete swarm configuration: agents, a task DAG, and optional kickoff messages. The `load-preset.sh` compiler reads a preset and translates it into calls to the existing shell primitives (`create-agent.sh`, `task.sh add`, `send-mail.sh`). The compiler is a thin translation layer with zero business logic.

**List available presets:**
```bash
make list-presets
```

**Load a preset:**
```bash
# Dry run (shows what would happen without executing)
make load-preset FILE=presets/bug-triage.json DRY_RUN=1

# Load for real (creates agents, tasks, sends kickoff mail)
make load-preset FILE=presets/bug-triage.json

# Skip agents that already exist
make load-preset FILE=presets/feature-build.json SKIP_EXISTING=1
```

**Variable substitution:** Presets use `${VAR}` placeholders in task descriptions and mail bodies. Set them as environment variables before loading:
```bash
BUG_TITLE="Login timeout" BUG_DESCRIPTION="Users report 30s hangs" \
  make load-preset FILE=presets/bug-triage.json
```

**Shipped presets (10):**

| Preset | Agents | DAG Shape | Problem Solved |
|--------|--------|-----------|----------------|
| `codebase-audit` | 5 | fan-out | Security + quality audit |
| `content-pipeline` | 4 | linear | Content creation pipeline |
| `bug-triage` | 4 | linear | Bug investigation → fix → verify → postmortem |
| `feature-build` | 5 | linear + revision | Spec → design → implement → review → docs |
| `security-hardening` | 4 | fan-out merge | Scan → threat model → parallel fixes → report |
| `api-design` | 5 | linear | Requirements → design → implement → test → docs |
| `data-pipeline` | 4 | fan-out merge | Ingest → validate → analyze → report |
| `project-kickoff` | 4 | fan-out merge | Design → scaffold+CI → tests → readme |
| `migration-plan` | 5 | fan-out merge | Assess → research → migrate → test → guide |
| `incident-response` | 4 | diamond | Triage → diagnose → hotfix → verify → postmortem |

**TUI commands:**
```
list-presets                          # List all presets with descriptions
load-preset presets/bug-triage.json   # Load a preset
preset-info presets/bug-triage.json   # Show agents, tasks, and variables
```

### Skill Packs

Skill packs give agents procedural knowledge from day one. Each skill is a `SKILL.md` file in the Claude Code format (YAML frontmatter + markdown instructions) containing real, runnable commands and specific procedures.

**How it works:**
- `config/skills/_universal/` — installed to every agent's `~/.claude/skills/`
- `config/skills/<persona>/` — installed only when the agent's persona matches (e.g., coder agents get `config/skills/coder/`)
- Skills are **copied, not symlinked** — agents can extend or modify skills at runtime
- Existing skills are **never overwritten** — preserves agent customizations on re-runs

**Universal skills (4)** — every agent gets these:
- `task-workflow` — Check ready tasks, claim, work, complete cycle
- `artifact-sharing` — Produce and consume shared files via `artifact.sh`
- `report-results` — Write structured result summaries
- `agent-communication` — Discover teammates, send/check mail

**Persona skills (23)** — installed based on persona:
- **coder**: project-setup, test-and-validate, focused-pr, code-refactor
- **researcher**: structured-research, source-evaluation
- **architect**: system-design, codebase-survey
- **security**: vulnerability-scan, dependency-audit
- **qa**: test-plan, regression-check
- **writer**: technical-writing, changelog-generation
- **editor**: editorial-review
- **reviewer**: code-review
- **planner**: task-decomposition
- **analyst**: data-analysis, metrics-report
- **devops**: dockerfile-authoring, ci-pipeline
- **manager**: delegation-workflow
- **ops**: triage-routing

**Verification:**
```bash
# After creating a coder agent:
make agent-shell NAME=alice
ls ~/.claude/skills/
# → task-workflow/ artifact-sharing/ report-results/ agent-communication/
#   project-setup/ test-and-validate/ focused-pr/ code-refactor/
```

### Interactive TUI

An interactive command prompt (like Claude Code) for managing the system. Built with Node.js and Ink.

**Setup:**
```bash
make install-tui   # Install dependencies (first time only)
```

**Run:**
```bash
make tui           # or: node cli.mjs
```

**Available commands inside the TUI:**

| Command | Description |
|---------|-------------|
| `build` | Build the Docker image |
| `up` / `down` / `restart` | Container lifecycle |
| `container-logs` | View container logs |
| `clean` | Stop container, remove image |
| `reset` | Full reset (hint — requires `make reset`) |
| `status` | Show container status |
| `list` | List agents and their status |
| `create alice --persona coder` | Create a new agent |
| `create alice --instructions "Focus on tests"` | Create with custom instructions |
| `remove alice` | Remove an agent |
| `logs alice` | Stream agent logs (Ctrl+C to stop) |
| `soft-reset` | Remove all agents, clear logs and mail |
| `personas` | List available personas |
| `set-key alice ANTHROPIC_API_KEY=sk-xxx` | Set API key |
| `clear-keys alice` | Remove all API keys from an agent |
| `providers` | List known API key provider names |
| `mail alice "Hello"` | Send mail to an agent or alias |
| `read-mail alice` | Read an agent's mailbox |
| `sync-aliases` | Regenerate mail aliases |
| `snapshot-init` | Initialize the snapshot repository |
| `snapshot "my note"` | Take a state snapshot |
| `snapshot-log` / `snapshot-diff` / `snapshot-status` | Snapshot history and changes |
| `swarm-status` | Show task board, health, costs, and events |
| `swarm-stop` / `swarm-stop --reason "bug"` | Stop all agents and orchestrator |
| `health` | Check agent heartbeat health |
| `task-add "Build engine" alice` | Add a task to the shared board |
| `task-list` / `task-list --owner alice` | List tasks (optionally filtered) |
| `task-ready` | List tasks ready to start |
| `task-update task-abc completed` | Update a task's status |
| `task-graph` | Show task dependency graph |
| `artifact-list` | List shared artifacts |
| `artifact-register reports/out.csv` | Register a shared artifact |
| `artifact-get reports/out.csv` | Get metadata for an artifact |
| `list-presets` | List available workflow presets |
| `load-preset presets/bug-triage.json` | Load a workflow preset |
| `preset-info presets/bug-triage.json` | Show preset details (agents, tasks, variables) |
| `help` | Show all commands |

Tab completion is available for commands, agent names, and persona names. Use up/down arrows to navigate command history.

### Customizing Configuration

#### Editing /etc/skel Files

Edit files in `config/skel/` to customize the default environment for new users:
- `config/skel/.bashrc` - Default bash configuration
- `config/skel/.bash_profile` - Default bash login script
- Add any other files you want in new user home directories

After editing, rebuild the Docker image:
```bash
docker-compose build
```

#### Editing /etc/profile.d Scripts

Edit files in `config/profile.d/` to set global environment variables and commands:
- `config/profile.d/custom-env.sh` - Custom global environment settings
- Add additional `.sh` files for more global configurations

After editing, rebuild the Docker image:
```bash
docker-compose build
```

#### Systemd Commands

To run systemd commands for each user, you can:
1. Add systemd service files to `config/skel/.config/systemd/user/`
2. Add startup commands to `config/skel/.bash_profile` or `config/skel/.bashrc`
3. Create custom scripts in `config/profile.d/` that set up systemd user services

### Home Directory Persistence

The `./home` directory in the repository is mounted as `/home/user` in the container. Any files you create or modify in `/home/user` inside the container will persist in the `./home` directory on your host machine.

### Observing Agents From the Host

Several container directories are mounted to the host so you can observe agent activity without logging into the container.

| Host path | Container path | Contents |
|-----------|---------------|----------|
| `./home` | `/home` | Agent home directories, including `.agent.log` per agent |
| `./log` | `/var/log` | System logs — journald, smtpd, and other service logs |
| `./log/journal` | `/var/log/journal` | Systemd journal (binary) — all agent service stdout/stderr |
| `./mail` | `/var/spool/mail` | Mail spool — one mbox file per agent for inter-agent messages |
| `./shared` | `/home/shared` | Shared artifacts — files registered via `artifact.sh` for inter-agent sharing |

**Reading agent service logs from the host:**
```bash
# Read journal logs for a specific agent (requires systemd on the host)
journalctl --directory=./log/journal -u agent@alice.service

# Follow all agent logs in real time
journalctl --directory=./log/journal -u 'agent@*' -f

# Or read per-agent log files directly
cat ./home/alice/.agent.log
```

**Reading agent mail from the host:**
```bash
# View mail for a specific agent (plain text mbox format)
cat ./mail/alice

# List agents with mail
ls -la ./mail/
```

**Reading system logs:**
```bash
# View all journal entries
journalctl --directory=./log/journal

# View smtpd (mail) activity
journalctl --directory=./log/journal -u smtpd.service
```

### Snapshotting Agent State

You can version-control agent output (home directories, logs, mail) independently from the project source code. The snapshot system uses a separate git repository (`.agent-snapshots/`) with its own `GIT_DIR`, so it never conflicts with the main repo. The snapshot directory is not mounted into the container, so agents cannot see or tamper with it.

**Setup:**
```bash
make snapshot-init
```

**Taking snapshots:**
```bash
make snapshot                           # Snapshot with timestamp message
make snapshot MSG="alice finished task"  # Snapshot with custom message
```

**Reviewing history:**
```bash
make snapshot-status    # What changed since last snapshot
make snapshot-diff      # Full diff since last snapshot
make snapshot-log       # Snapshot history
```

**What gets tracked:**
- `home/` — Agent home directories (work output, per-agent logs, config)
- `log/` — System logs (text logs only; binary journal files are excluded)
- `mail/` — Inter-agent mail spool

See [`scripts/README.md`](scripts/README.md) for full documentation of `snapshot-agents.sh`.

## Notes

- Agent users run as unprivileged users in the `agents` group with no sudo access. Unix permissions prevent agents from writing outside their own home directory (mode 700). Only root can install packages or modify the system. Systemd security hardening directives (NoNewPrivileges, ProtectSystem, PrivateTmp, CapabilityBoundingSet, RestrictAddressFamilies, resource limits, etc.) are commented out by default because they cause silent service failures inside Docker containers (cgroup delegation, overlay2 mount conflicts, seccomp layering). The Docker container boundary provides equivalent isolation. To re-enable for non-Docker deployments, uncomment them in `config/systemd/agent@.service`.
- `systemd-networkd-wait-online.service` is masked in the Docker image because Docker manages networking externally. Without masking, this service blocks the boot for ~2 minutes waiting for network connectivity, which delays `multi-user.target` and prevents agent services from starting.
- `systemd-firstboot.service` is masked because it runs `Before=basic.target` on every container start (`ConditionFirstBoot=yes`, since the root filesystem is ephemeral) and hangs waiting for interactive input when a TTY is attached. This blocks `basic.target` and prevents all agent services from starting.
- The home directory is persisted outside the container in the repository
- Configuration files can be edited in the repository and will be applied when the image is rebuilt
- Systemd is available but requires privileged mode (enabled in docker-compose.yml)
- The Arch Linux base image only provides `linux/amd64` builds. On ARM hosts (e.g., Apple Silicon Macs), Docker uses QEMU emulation automatically via the `platform: linux/amd64` setting in docker-compose.yml.