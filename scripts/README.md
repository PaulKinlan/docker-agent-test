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
| `create-agent.sh` | Create a new agent user | `create-agent.sh <username>` |
| `remove-agent.sh` | Remove an agent user | `remove-agent.sh <username> [--keep-home]` |
| `list-agents.sh` | List agents and their status | `list-agents.sh` |
| `run-agent.sh` | Agent entrypoint (run by systemd) | Automatic — not run manually |
| `agent-manager.sh` | Boot-time service reconciliation | Automatic — runs at container start |

---

## create-agent.sh

Creates a new agent user with a home directory, `.claude/` configuration, and a running systemd service.

**Usage:**
```bash
# Inside the container
create-agent.sh <username>

# From the host via Make
make create-agent NAME=<username>
```

**Arguments:**
- `<username>` (required) — Must start with a lowercase letter or underscore, contain only `[a-z0-9_-]`, and be at most 32 characters.

**What it does:**
1. Validates the username format
2. Creates a Linux user with home directory populated from `/etc/skel`
3. Adds the user to the `agents` group
4. Creates a root-owned `.claude/` directory in the user's home with a default `config.json`
5. Enables and starts the `agent@<username>.service` systemd unit

**Example:**
```bash
make create-agent NAME=alice
# -> Creates user 'alice', starts agent@alice.service
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
1. Stops and disables the `agent@<username>.service`
2. Removes the Linux user account
3. Removes the home directory (unless `--keep-home` is specified)

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

## run-agent.sh

The entrypoint script executed by each agent's systemd service (`agent@<username>.service`). It runs as the agent user with their home directory as the working directory.

This script is **not intended to be run manually** — it is invoked automatically by systemd.

**What it does:**
1. Logs startup information (user, home directory, PID, config file status)
2. Checks for `agents.md` and `.claude/config.json` in the user's home
3. Runs a heartbeat loop, logging "alive" every 60 seconds to `/home/<username>/.agent.log`

**Customization:** The heartbeat loop is a placeholder. Replace it with your actual agent binary:
```bash
# In run-agent.sh, replace the while loop with:
exec claude-code --config "$CLAUDE_CONFIG"
```

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
3. Enables and starts the corresponding `agent@<username>.service`
4. Reports a summary of started vs. failed agents

---

## Makefile Targets

The `Makefile` in the project root provides convenience wrappers (the container must be running):

```bash
make create-agent NAME=foo   # Create a new agent
make remove-agent NAME=foo   # Remove an agent
make list-agents             # List all agents and status
make agent-logs NAME=foo     # Tail systemd journal logs for an agent
make agent-shell NAME=foo    # Open a shell as the agent user
```
