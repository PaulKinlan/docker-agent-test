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
| `create-agent.sh` | Create a new agent user | `create-agent.sh <username> [--persona <name>] [--api-key <KEY>=<val>]` |
| `remove-agent.sh` | Remove an agent user | `remove-agent.sh <username> [--keep-home]` |
| `list-agents.sh` | List agents and their status | `list-agents.sh` |
| `manage-api-keys.sh` | Manage per-agent API keys | `manage-api-keys.sh <command> <args>` |
| `run-agent.sh` | Agent entrypoint (run by systemd) | Automatic — not run manually |
| `agent-manager.sh` | Boot-time service reconciliation | Automatic — runs at container start |
| `sync-api-keys.sh` | Sync env vars to global API keys | Automatic — runs at container start |

---

## create-agent.sh

Creates a new agent user with a home directory, `.claude/` configuration, optional persona, optional API keys, and a running systemd service.

**Usage:**
```bash
# Inside the container
create-agent.sh <username> [--persona <name>] [--api-key <PROVIDER>=<key>]...

# From the host via Make
make create-agent NAME=<username> [PERSONA=<name>] [API_KEY=<PROVIDER>=<key>]
```

**Arguments:**
- `<username>` (required) — Must start with a lowercase letter or underscore, contain only `[a-z0-9_-]`, and be at most 32 characters.
- `--persona <name>` (optional) — Apply a specialist persona (e.g., `coder`, `researcher`).
- `--api-key <PROVIDER>=<key>` (optional) — Set an API key for this agent. Can be repeated for multiple keys.

**What it does:**
1. Validates the username format
2. Creates a Linux user with home directory populated from `/etc/skel`
3. Adds the user to the `agents` group
4. Builds `agents.md` from base persona + optional specialist persona
5. Creates a root-owned `.claude/` directory in the user's home with a default `config.json`
6. Configures per-agent API keys if provided (stored in `.claude/api-keys.env`)
7. Enables and starts the `agent@<username>.service` systemd unit

**Examples:**
```bash
# Create agent with default base persona
make create-agent NAME=alice

# Create agent with coder persona
make create-agent NAME=alice PERSONA=coder

# Create agent with API key
make create-agent NAME=bob API_KEY=ANTHROPIC_API_KEY=sk-ant-xxx

# Create agent with persona and API key (inside container)
create-agent.sh carol --persona researcher --api-key OPENAI_API_KEY=sk-xxx
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
3. Loads API keys from global and per-agent configuration (see API Key Loading below)
4. Runs a heartbeat loop, logging "alive" every 60 seconds to `/home/<username>/.agent.log`

**API Key Loading:**
1. First loads global defaults from `/etc/agent-api-keys/global.env` (if exists)
2. Then loads per-agent overrides from `~/.claude/api-keys.env` (if exists)
3. Per-agent keys take precedence over global keys
4. All loaded keys are exported as environment variables

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

## Makefile Targets

The `Makefile` in the project root provides convenience wrappers (the container must be running):

**Agent Management:**
```bash
make create-agent NAME=foo                        # Create agent with base persona
make create-agent NAME=foo PERSONA=coder          # Create agent with specialist persona
make create-agent NAME=foo API_KEY=ANTHROPIC_API_KEY=sk-xxx  # Create with API key
make remove-agent NAME=foo                        # Remove an agent
make list-agents                                  # List all agents and status
make list-personas                                # List available personas
make agent-logs NAME=foo                          # Tail systemd journal logs
make agent-shell NAME=foo                         # Open a shell as the agent user
```

**API Key Management:**
```bash
make set-api-key NAME=foo KEY=ANTHROPIC_API_KEY=sk-xxx  # Set API key for agent
make get-api-keys NAME=foo                              # Show API keys (masked)
make remove-api-key NAME=foo KEY=OPENAI_API_KEY         # Remove specific key
make clear-api-keys NAME=foo                            # Remove all keys
make list-providers                                     # List known provider names
```
