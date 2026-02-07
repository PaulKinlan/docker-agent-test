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
├── agent                   # CLI entry point (agent up / agent down)
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
│   ├── skel/              # Files copied to /etc/skel (template for new users)
│   │   ├── .bashrc        # Default bash configuration
│   │   ├── .bash_profile  # Default bash login configuration
│   │   ├── CLAUDE.md      # Default operating instructions for agents
│   │   └── agents.md      # Agent persona configuration template
│   ├── profile.d/         # Files copied to /etc/profile.d (global environment)
│   │   ├── agent-env.sh   # Global agent environment setup
│   │   └── nvm.sh         # Loads nvm (Node Version Manager) for all users
│   └── systemd/           # Systemd service definitions
│       ├── agent@.service          # Per-agent service template
│       ├── agent-manager.service   # Boot-time reconciliation service
│       └── api-keys-sync.service   # Boot-time API key sync service
└── scripts/               # Management scripts (copied to /usr/local/bin)
    ├── create-agent.sh    # Create a new agent user
    ├── update-agent.sh    # Update an agent's persona
    ├── remove-agent.sh    # Remove an agent user
    ├── list-agents.sh     # List agents and their status
    ├── manage-api-keys.sh # Manage per-agent API keys
    ├── send-mail.sh       # Send mail to an agent user
    ├── snapshot-agents.sh # Snapshot agent state (host-only)
    ├── run-agent.sh       # Agent entrypoint (run by systemd)
    ├── agent-manager.sh   # Boot-time service reconciliation
    └── sync-api-keys.sh   # Boot-time API key environment sync
```

## Usage

### Quick Start

The `agent` script at the project root is the simplest way to manage the container:

```bash
# Start the agent host (auto-rebuilds if Dockerfile, config/, or scripts/ changed)
./agent up

# Stop the agent host
./agent down
```

`agent up` checks whether the Docker image needs rebuilding by comparing file modification times in `Dockerfile`, `docker-compose.yml`, `config/`, and `scripts/` against the last image build time. If anything changed, it rebuilds automatically before starting.

### Building and Running (manual)

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

**Send mail to an agent:**
```bash
# Send from root (default)
make mail TO=alice MSG="Please check the build logs"

# Send from another agent
make mail TO=alice FROM=bob MSG="Can you review my PR?"

# With a custom subject
make mail TO=alice FROM=bob SUBJECT="Code Review" MSG="PR #42 is ready"
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

Each agent runs as its own systemd service (`agent@<username>.service`) which executes `run-agent.sh` as the agent user. By default, the script logs heartbeats to `/home/<username>/.agent.log`. Replace the heartbeat loop in `run-agent.sh` with your actual agent binary to deploy real workloads.

At container boot, `agent-manager.sh` automatically reconciles all users in the `agents` group, ensuring their services are enabled and started.

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
- The home directory is persisted outside the container in the repository
- Configuration files can be edited in the repository and will be applied when the image is rebuilt
- Systemd is available but requires privileged mode (enabled in docker-compose.yml)
- The Arch Linux base image only provides `linux/amd64` builds. On ARM hosts (e.g., Apple Silicon Macs), Docker uses QEMU emulation automatically via the `platform: linux/amd64` setting in docker-compose.yml.