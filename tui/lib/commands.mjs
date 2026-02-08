import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { getContainerName } from "./container.mjs";
import { getPersonaNames } from "./completions.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..", "..");

// Commands that require a running container
const NEEDS_CONTAINER = new Set([
  "list", "create", "remove", "update", "logs", "shell",
  "set-key", "get-keys", "remove-key", "clear-keys", "providers",
  "mail", "sync-aliases",
  "soft-reset",
]);

const COMMANDS = {
  // --- Container ---
  build: {
    description: "Build the Docker image",
    category: "Container",
    toSpawn: () => ({ cmd: "docker-compose", args: ["build"] }),
  },
  up: {
    description: "Start the container",
    category: "Container",
    toSpawn: () => ({ cmd: "docker-compose", args: ["up", "-d"] }),
  },
  down: {
    description: "Stop and remove the container",
    category: "Container",
    toSpawn: () => ({ cmd: "docker-compose", args: ["down"] }),
  },
  restart: {
    description: "Restart the container",
    category: "Container",
    sequence: ["down", "up"],
  },
  "container-logs": {
    description: "View container logs",
    category: "Container",
    toSpawn: () => ({ cmd: "docker-compose", args: ["logs", "-f", "--timestamps"] }),
  },
  clean: {
    description: "Stop container, remove image",
    category: "Container",
    toSpawn: () => ({ cmd: "make", args: ["clean"] }),
  },
  reset: {
    description: "Full reset: stop container, remove image, wipe all data",
    category: "Container",
    builtin: true,
  },
  status: {
    description: "Show container and agent status",
    category: "Container",
    builtin: true,
  },

  // --- Agents ---
  list: {
    description: "List all agents and their status",
    category: "Agents",
    toSpawn: () => ({ cmd: "./scripts/list-agents.sh", args: [] }),
  },
  create: {
    description: "Create a new agent",
    usage: "create <name> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER=key>]",
    category: "Agents",
    minArgs: 1,
    toSpawn: (args) => ({ cmd: "./scripts/create-agent.sh", args }),
  },
  remove: {
    description: "Remove an agent",
    usage: "remove <name>",
    category: "Agents",
    minArgs: 1,
    toSpawn: (args) => ({ cmd: "./scripts/remove-agent.sh", args }),
  },
  update: {
    description: "Update an agent's persona",
    usage: "update <name> --persona <name>",
    category: "Agents",
    minArgs: 1,
    toSpawn: (args) => ({ cmd: "./scripts/update-agent.sh", args }),
  },
  logs: {
    description: "Stream agent logs (Ctrl+C to stop)",
    usage: "logs <name>",
    category: "Agents",
    minArgs: 1,
    toSpawn: (args) => ({
      cmd: "docker-compose",
      args: ["exec", "-T", getContainerName(), "journalctl", "-u", `agent@${args[0]}.service`, "-f", "--no-pager"],
    }),
  },
  shell: {
    description: "Open a shell as an agent (hint only)",
    usage: "shell <name>",
    category: "Agents",
    minArgs: 1,
    builtin: true,
  },
  personas: {
    description: "List available personas",
    category: "Agents",
    builtin: true,
  },
  "soft-reset": {
    description: "Remove all agents, clear logs and mail",
    category: "Agents",
    toSpawn: () => ({ cmd: "./scripts/soft-reset.sh", args: ["--yes"] }),
  },

  // --- API Keys ---
  "set-key": {
    description: "Set an API key for an agent",
    usage: "set-key <name> <PROVIDER=key>",
    category: "API Keys",
    minArgs: 2,
    toSpawn: (args) => ({
      cmd: "./scripts/manage-api-keys.sh",
      args: ["set", args[0], args.slice(1).join(" ")],
    }),
  },
  "get-keys": {
    description: "Show API keys for an agent (masked)",
    usage: "get-keys <name>",
    category: "API Keys",
    minArgs: 1,
    toSpawn: (args) => ({
      cmd: "./scripts/manage-api-keys.sh",
      args: ["get", args[0]],
    }),
  },
  "remove-key": {
    description: "Remove an API key from an agent",
    usage: "remove-key <name> <PROVIDER>",
    category: "API Keys",
    minArgs: 2,
    toSpawn: (args) => ({
      cmd: "./scripts/manage-api-keys.sh",
      args: ["remove", args[0], args[1]],
    }),
  },
  "clear-keys": {
    description: "Remove all API keys from an agent",
    usage: "clear-keys <name>",
    category: "API Keys",
    minArgs: 1,
    toSpawn: (args) => ({
      cmd: "./scripts/manage-api-keys.sh",
      args: ["clear", args[0]],
    }),
  },
  providers: {
    description: "List known API key provider names",
    category: "API Keys",
    toSpawn: () => ({
      cmd: "./scripts/manage-api-keys.sh",
      args: ["list-providers"],
    }),
  },

  // --- Mail ---
  mail: {
    description: "Send mail to an agent or alias",
    usage: 'mail <to> "<message>" [--from <name>] [--subject "<text>"]',
    category: "Mail",
    minArgs: 2,
    toSpawn: (args) => {
      // Parse: mail <to> <message> [--from X] [--subject X]
      const to = args[0];
      const spawnArgs = [to];
      let message = "";
      let i = 1;
      // Collect non-flag args as message parts until we hit a flag
      const messageParts = [];
      while (i < args.length && !args[i].startsWith("--")) {
        messageParts.push(args[i]);
        i++;
      }
      message = messageParts.join(" ");
      // Collect flags
      while (i < args.length) {
        if (args[i] === "--from" && args[i + 1]) {
          spawnArgs.push("--from", args[i + 1]);
          i += 2;
        } else if (args[i] === "--subject" && args[i + 1]) {
          spawnArgs.push("--subject", args[i + 1]);
          i += 2;
        } else {
          i++;
        }
      }
      spawnArgs.push("--", message);
      return { cmd: "./scripts/send-mail.sh", args: spawnArgs };
    },
  },
  "read-mail": {
    description: "Read an agent's mailbox",
    usage: "read-mail <name>",
    category: "Mail",
    minArgs: 1,
    builtin: true,
  },
  "sync-aliases": {
    description: "Regenerate mail aliases",
    category: "Mail",
    toSpawn: () => ({ cmd: "./scripts/sync-aliases.sh", args: [] }),
  },

  // --- Snapshots ---
  "snapshot-init": {
    description: "Initialize the snapshot repository",
    category: "Snapshots",
    toSpawn: () => ({ cmd: "./scripts/snapshot-agents.sh", args: ["init"] }),
  },
  snapshot: {
    description: "Take a snapshot of agent state",
    usage: 'snapshot ["message"]',
    category: "Snapshots",
    toSpawn: (args) => ({
      cmd: "./scripts/snapshot-agents.sh",
      args: ["create", ...(args.length > 0 ? [args.join(" ")] : [])],
    }),
  },
  "snapshot-log": {
    description: "Show snapshot history",
    category: "Snapshots",
    toSpawn: () => ({ cmd: "./scripts/snapshot-agents.sh", args: ["log"] }),
  },
  "snapshot-diff": {
    description: "Show changes since last snapshot",
    category: "Snapshots",
    toSpawn: () => ({ cmd: "./scripts/snapshot-agents.sh", args: ["diff"] }),
  },
  "snapshot-status": {
    description: "Summarize changes since last snapshot",
    category: "Snapshots",
    toSpawn: () => ({ cmd: "./scripts/snapshot-agents.sh", args: ["status"] }),
  },

  // --- Meta ---
  help: {
    description: "Show available commands",
    category: "Meta",
    builtin: true,
  },
  clear: {
    description: "Clear the screen",
    category: "Meta",
    builtin: true,
  },
  exit: {
    description: "Exit the TUI",
    category: "Meta",
    builtin: true,
  },
  quit: { hidden: true, builtin: true },
};

export function parse(input) {
  const raw = input.trim();
  if (!raw) return null;

  // Tokenize respecting quoted strings
  const tokens = [];
  let current = "";
  let inQuote = null;
  for (const ch of raw) {
    if (inQuote) {
      if (ch === inQuote) {
        inQuote = null;
      } else {
        current += ch;
      }
    } else if (ch === '"' || ch === "'") {
      inQuote = ch;
    } else if (ch === " ") {
      if (current) {
        tokens.push(current);
        current = "";
      }
    } else {
      current += ch;
    }
  }
  if (current) tokens.push(current);

  const name = tokens[0];
  const args = tokens.slice(1);
  const def = COMMANDS[name];

  if (!def) {
    return { error: `Unknown command: '${name}'. Type 'help' for available commands.` };
  }

  if (def.minArgs && args.length < def.minArgs) {
    return { error: `Usage: ${def.usage || name}` };
  }

  return { name, args, def, raw };
}

export function needsContainer(name) {
  return NEEDS_CONTAINER.has(name);
}

export function getHelpLines() {
  const lines = [];
  const categories = {};

  for (const [name, def] of Object.entries(COMMANDS)) {
    if (def.hidden) continue;
    const cat = def.category || "Other";
    if (!categories[cat]) categories[cat] = [];
    const usage = def.usage || name;
    categories[cat].push({ usage, description: def.description });
  }

  for (const [cat, cmds] of Object.entries(categories)) {
    lines.push({ text: `  ${cat}:`, type: "info" });
    for (const { usage, description } of cmds) {
      const padded = usage.padEnd(46);
      lines.push({ text: `    ${padded} ${description}`, type: "stdout" });
    }
    lines.push({ text: "", type: "stdout" });
  }

  return lines;
}

export function getPersonaLines() {
  const names = getPersonaNames();
  const lines = [{ text: "  Available personas:", type: "info" }, { text: "", type: "stdout" }];
  for (const name of names) {
    const label = name === "base" ? `  ${name} (applied to all agents)` : `  ${name}`;
    lines.push({ text: `    ${label}`, type: "stdout" });
  }
  lines.push({ text: "", type: "stdout" });
  lines.push({ text: '  Usage: create <name> --persona <name>', type: "stdout" });
  return lines;
}

export function getReadMailLines(agentName) {
  const mailPath = resolve(PROJECT_ROOT, "mail", agentName);
  try {
    const content = readFileSync(mailPath, "utf-8");
    if (!content.trim()) {
      return [{ text: `  No mail for ${agentName}.`, type: "info" }];
    }
    return content.split("\n").map((line) => ({ text: line, type: "stdout" }));
  } catch {
    return [{ text: `  No mailbox found for ${agentName}.`, type: "info" }];
  }
}

export { COMMANDS };
