# Quick Start Guide

This guide covers day-to-day usage of the agent hosting system. All operations are driven through `make` targets.

## Prerequisites

- Docker and Docker Compose installed
- Network access to download Arch Linux packages (for builds)
- An Anthropic API key (or other supported provider key) for agents to use

## Getting Started

### 1. Build and start

```bash
make build
make up
```

This builds the Arch Linux-based image and boots the container with systemd as init.

### 2. Create an agent

```bash
make create-agent NAME=alice
```

This creates a Linux user `alice`, sets up their home directory from the skeleton template, and starts their systemd service.

To assign a specialist persona:

```bash
make create-agent NAME=bob PERSONA=coder
```

Available personas: `base` (default, applied to all agents), `coder`, `researcher`, `reviewer`. List them with:

```bash
make list-personas
```

### 3. Provide an API key

Agents need API keys to function. You can set them globally via host environment variables before starting the container:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
make restart
```

Or set a key for a specific agent:

```bash
make set-api-key NAME=alice KEY=ANTHROPIC_API_KEY=sk-ant-...
```

You can also pass an API key at agent creation time:

```bash
make create-agent NAME=alice API_KEY=ANTHROPIC_API_KEY=sk-ant-...
```

### 4. Check agent status

```bash
make list-agents
```

### 5. View agent logs

```bash
make agent-logs NAME=alice
```

This tails the systemd journal for the agent's service. Press Ctrl+C to stop.

## Daily Operations

### Container management

| Command | Description |
|---|---|
| `make build` | Build the Docker image |
| `make up` | Start the container |
| `make down` | Stop and remove the container |
| `make restart` | Restart the container |
| `make shell` | Open a root shell inside the container |
| `make logs` | Tail container logs |
| `make clean` | Remove image (home directories are preserved) |

### Agent management

All agent commands require the container to be running (`make up`).

| Command | Description |
|---|---|
| `make create-agent NAME=alice` | Create an agent with the base persona |
| `make create-agent NAME=alice PERSONA=coder` | Create an agent with a specialist persona |
| `make remove-agent NAME=alice` | Remove an agent and its service |
| `make update-agent NAME=alice PERSONA=reviewer` | Change an agent's persona |
| `make list-agents` | List all agents and their service status |
| `make list-personas` | List available personas |
| `make agent-logs NAME=alice` | Tail an agent's service logs |
| `make agent-shell NAME=alice` | Open a shell as the agent user |

### Inter-agent mail

```bash
make mail TO=alice MSG="Check the auth module"
make mail TO=alice FROM=bob MSG="Review my changes" SUBJECT="Code review"
```

### API key management

| Command | Description |
|---|---|
| `make set-api-key NAME=alice KEY=ANTHROPIC_API_KEY=sk-...` | Set an API key for an agent |
| `make get-api-keys NAME=alice` | Show an agent's API keys (masked) |
| `make remove-api-key NAME=alice KEY=OPENAI_API_KEY` | Remove a specific API key |
| `make clear-api-keys NAME=alice` | Remove all API keys from an agent |
| `make list-providers` | List known API key provider names |

### Snapshots

Snapshots track agent home directory state over time. These run on the host (container not required).

```bash
make snapshot-init            # Initialize the snapshot repository (run once)
make snapshot                 # Take a snapshot
make snapshot MSG="milestone" # Take a snapshot with a message
make snapshot-log             # Show snapshot history
make snapshot-diff            # Show changes since last snapshot
make snapshot-status          # Summarize changes since last snapshot
```

## Customizing Configuration

Configuration files live in `config/` and are baked into the image at build time. After editing any config, rebuild and restart:

```bash
make build && make restart
```

- **`config/skel/`** — Template for new agent home directories. Changes apply to agents created after rebuilding.
- **`config/profile.d/`** — Global shell environment scripts loaded by all agents.
- **`config/personas/`** — Agent persona definitions. Add a new `.md` file to create a new persona.
- **`config/api-keys/`** — API key configuration templates.
- **`config/systemd/`** — Systemd service template for agent services.

## Troubleshooting

### Build fails with network errors

The build needs access to Arch Linux package repositories. Build on a machine with internet access.

### Config changes don't take effect

Files in `config/` and `scripts/` are copied into the image at build time. Rebuild and restart:

```bash
make build && make restart
```

### Build fails on Apple Silicon / ARM hosts

The Arch Linux base image is `amd64` only. Docker uses QEMU emulation automatically on ARM hosts via the `platform: linux/amd64` setting in `docker-compose.yml`. Ensure Docker Desktop's QEMU/Rosetta emulation is enabled.

### Agent won't start

Check the agent's service logs:

```bash
make agent-logs NAME=alice
```

Open a root shell to inspect further:

```bash
make shell
systemctl status agent@alice.service
```

### All available commands

Run `make help` (or just `make`) to see every available target with usage examples.

## Further Reading

- `README.md` — Project overview, architecture, and security model
- `config/README.md` — Detailed configuration reference
- `scripts/README.md` — Script documentation
