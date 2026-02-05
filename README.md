# docker-agent-test

A Docker setup using the latest Arch Linux with customizable configuration files.

## Features

- Uses the latest Arch Linux base image
- Home directory mounted from the repository (`./home`)
- Customizable `/etc/skel` files for new users
- Customizable `/etc/profile.d` scripts for global environment setup
- Systemd support enabled

## Directory Structure

```
.
├── Dockerfile              # Main Dockerfile using archlinux:latest
├── docker-compose.yml      # Docker Compose configuration
├── Makefile                # Convenience targets for container and agent management
├── home/                   # Persistent agent home directories (mounted as /home)
├── config/
│   ├── skel/              # Files copied to /etc/skel (template for new users)
│   │   ├── .bashrc        # Default bash configuration
│   │   ├── .bash_profile  # Default bash login configuration
│   │   └── agents.md      # Agent configuration template
│   ├── profile.d/         # Files copied to /etc/profile.d (global environment)
│   │   └── agent-env.sh   # Global agent environment setup
│   └── systemd/           # Systemd service definitions
│       ├── agent@.service          # Per-agent service template
│       └── agent-manager.service   # Boot-time reconciliation service
└── scripts/               # Management scripts (copied to /usr/local/bin)
    ├── create-agent.sh    # Create a new agent user
    ├── remove-agent.sh    # Remove an agent user
    ├── list-agents.sh     # List agents and their status
    ├── run-agent.sh       # Agent entrypoint (run by systemd)
    └── agent-manager.sh   # Boot-time service reconciliation
```

## Usage

### Building and Running

Using Docker Compose (recommended):
```bash
# Build the image
docker-compose build

# Start the container
docker-compose up -d

# Access the container
docker-compose exec arch-dev /bin/bash

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
./scripts/list-agents.sh
./scripts/remove-agent.sh alice --keep-home
```

**From the host (via Make):**
```bash
make create-agent NAME=alice
make list-agents
make remove-agent NAME=alice
```

**Inside the container:**
```bash
create-agent.sh alice
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

## Notes

- Agent users run with restricted permissions: no sudo, read-only filesystem (except own home), private /tmp, and no capability to escalate privileges. Only root can install packages or modify the system.
- The home directory is persisted outside the container in the repository
- Configuration files can be edited in the repository and will be applied when the image is rebuilt
- Systemd is available but requires privileged mode (enabled in docker-compose.yml)