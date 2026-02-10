# Configuration Files

This directory contains configuration files that are copied into the Docker image.

## Directory Structure

### `api-keys/` - API Key Configuration

Files in this directory are copied to `/etc/agent-api-keys/` in the container. Used for global LLM API key configuration.

**Current files:**
- `global.env.template` - Template showing supported API key providers
- `.gitignore` - Prevents committing actual API keys

**How to configure global API keys:**

Option 1: Bake keys into the image (for private images):
1. Copy `global.env.template` to `global.env`
2. Uncomment and set the API keys you need
3. Rebuild the Docker image: `docker-compose build`

Option 2: Pass keys at runtime via environment variables:
```bash
export ANTHROPIC_API_KEY=sk-ant-xxx
export OPENAI_API_KEY=sk-xxx
docker-compose up -d
```

Environment variables are automatically synced to `/etc/agent-api-keys/global.env` at container startup.

**Supported providers:**
- Anthropic (`ANTHROPIC_API_KEY`)
- OpenAI (`OPENAI_API_KEY`)
- Google/Gemini (`GOOGLE_API_KEY`, `GEMINI_API_KEY`)
- Mistral (`MISTRAL_API_KEY`)
- Cohere (`COHERE_API_KEY`)
- Groq (`GROQ_API_KEY`)
- Together.ai (`TOGETHER_API_KEY`)
- Fireworks.ai (`FIREWORKS_API_KEY`)
- Perplexity (`PERPLEXITY_API_KEY`)
- Replicate (`REPLICATE_API_TOKEN`)
- Hugging Face (`HUGGINGFACE_API_KEY`, `HF_TOKEN`)
- AWS Bedrock (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`)
- Azure OpenAI (`AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT`)

**Per-agent API keys:**
Use `manage-api-keys.sh` or create agents with the `--api-key` flag. Per-agent keys override global keys. See [`scripts/README.md`](../scripts/README.md) for details.

### `personas/` - Agent Persona Definitions

Files in this directory are copied to `/etc/agent-personas/` in the container. Used by `create-agent.sh` to build each agent's `agents.md`.

**Current files:**
- `base.md` — Base persona applied to all agents (autonomy, collaboration, constraints)
- `analyst.md` — Data analysis and reporting
- `architect.md` — System design and technical RFCs
- `coder.md` — Software development
- `devops.md` — Build scripts, CI/CD, and infrastructure automation
- `editor.md` — Content review for clarity, consistency, and tone
- `manager.md` — Team coordination and task delegation
- `ops.md` — Request triage and routing to specialists
- `planner.md` — Goal-to-spec breakdown with acceptance criteria
- `qa.md` — Testing, edge cases, and bug reporting
- `researcher.md` — Research and information gathering
- `reviewer.md` — Code review
- `security.md` — Security audits and vulnerability review
- `writer.md` — Technical documentation and content

The base persona is always included. Specialist personas extend it when specified with `--persona`.

**How to add a new persona:**
1. Create a new `.md` file in this directory
2. Follow the 3-section format: Identity, Instructions, Output Format
3. Rebuild the Docker image: `docker-compose build`
4. Use with: `make create-agent NAME=alice PERSONA=<name>`

### `skills/` - Agent Skill Packs

Files in this directory are copied to `/etc/agent-skills/` in the container. Used by `create-agent.sh` to populate each agent's `~/.claude/skills/` directory at creation time.

**Directory structure:**
```
skills/
├── _universal/                    # Installed to every agent
│   ├── task-workflow/SKILL.md     # Check ready tasks, claim, work, complete
│   ├── artifact-sharing/SKILL.md  # Produce/consume shared files
│   ├── report-results/SKILL.md    # Write good result summaries
│   └── agent-communication/SKILL.md # Discover team, send mail, check inbox
├── coder/                         # Installed when persona = coder
│   ├── project-setup/SKILL.md
│   ├── test-and-validate/SKILL.md
│   ├── focused-pr/SKILL.md
│   └── code-refactor/SKILL.md
├── researcher/                    # Installed when persona = researcher
│   ├── structured-research/SKILL.md
│   └── source-evaluation/SKILL.md
├── architect/
├── security/
├── qa/
├── writer/
├── editor/
├── reviewer/
├── planner/
├── analyst/
├── devops/
├── manager/
└── ops/
```

**Persona-mapping convention:** The directory name under `skills/` must match the persona filename (without `.md`). For example, persona `coder.md` maps to `skills/coder/`. The special `_universal/` directory is always installed regardless of persona.

**Skill format:** Each skill is a directory containing a `SKILL.md` file in Claude Code format:
```markdown
---
name: skill-name
description: What the skill does
---

# Skill Name

Procedural instructions with real, runnable commands...
```

**Installation behavior:**
- Skills are **copied** into the agent's home directory (not symlinked), so agents can extend or modify them at runtime
- **Existing skills are never overwritten** — if an agent already has a skill directory, it is preserved. This protects agent customizations across re-runs
- After installation, the skills directory is `chown`'d to the agent user for writability

**How to add a new skill:**
1. Create a directory: `config/skills/<persona>/<skill-name>/`
2. Write a `SKILL.md` file with YAML frontmatter and procedural markdown content
3. Rebuild the Docker image: `docker-compose build`
4. New agents with that persona will automatically receive the skill

**How to add a universal skill:**
1. Create a directory: `config/skills/_universal/<skill-name>/`
2. Write a `SKILL.md` file
3. Rebuild — all new agents will receive it regardless of persona

### `smtpd/` - OpenSMTPD Configuration

Files in this directory are copied to `/etc/smtpd/` in the container. Used for mail alias configuration.

**Current files:**
- `aliases.static` — Custom per-agent mail aliases (merged into the generated aliases file)

**How mail aliases work:**

The `all` group alias is auto-generated by `sync-aliases.sh` whenever agents are created or removed. It delivers to every registered agent.

Custom aliases can be defined in `aliases.static` using the format `alias: recipient1, recipient2`. These are merged into the generated `/etc/smtpd/aliases` file.

**Examples:**
```
# In aliases.static:
devs: alice, bob         # Mail to 'devs' delivers to alice and bob
lead: alice              # Mail to 'lead' delivers to alice
```

After editing, rebuild the Docker image and run `make sync-aliases` to apply changes.

### `skel/` - User Template Files

Files in this directory are copied to `/etc/skel/` in the container. These files serve as templates for new user home directories.

**Current files:**
- `.bashrc` - Default bash configuration for interactive shells
- `.bash_profile` - Bash login configuration
- `CLAUDE.md` - Default operating instructions for Claude Code agents
- `agents.md` - Agent persona configuration (generated by create-agent.sh)
- `TODO.md` - Starter task list for tracking work assignments
- `MEMORY.md` - Starter persistent memory file for learnings and context
**Note:** Agent skills are stored in `~/.claude/skills/` (created by `create-agent.sh`, not from skel). Skills use the Claude Code format — see `CLAUDE.md` for details.

**How to use:**
1. Edit or add files in this directory
2. Rebuild the Docker image: `docker-compose build`
3. New users will automatically get these files in their home directory

**For systemd user services:**
- Create a `skel/.config/systemd/user/` directory and place service files there
- Enable them in `.bash_profile` or `.bashrc` with commands like:
  ```bash
  systemctl --user enable myservice.service
  systemctl --user start myservice.service
  ```

### `profile.d/` - Global Environment Scripts

Files in this directory are copied to `/etc/profile.d/` in the container. These scripts are executed for all users during login.

**Current files:**
- `agent-env.sh` - Global agent environment setup (platform vars, umask, PATH)
- `nvm.sh` - Loads nvm (Node Version Manager) for all users

**How to use:**
1. Create `.sh` files in this directory
2. Make them executable (or the Dockerfile will do it automatically)
3. Rebuild the Docker image: `docker-compose build`
4. Scripts will run for all users on login

**Best practices:**
- Use descriptive filenames (e.g., `company-env.sh`, `dev-tools.sh`)
- Scripts should be idempotent (safe to run multiple times)
- Keep scripts simple and fast to avoid slowing down login
- Export environment variables that should be available to all processes
- Set up PATH additions here for global tools

## Examples

### Adding a custom command for all users

Create `config/profile.d/custom-commands.sh`:
```bash
#!/bin/bash
# Add a custom greeting command
greet() {
    echo "Hello $(whoami), welcome to the development environment!"
}
export -f greet
```

### Setting up systemd user service at login

Edit `config/skel/.bashrc` to add:
```bash
# Enable and start user services
if systemctl --user is-enabled myservice.service >/dev/null 2>&1; then
    systemctl --user start myservice.service
fi
```

### Adding custom aliases for new users

Edit `config/skel/.bashrc` to add:
```bash
# Docker-specific aliases
alias dps='docker ps'
alias dim='docker images'
```
