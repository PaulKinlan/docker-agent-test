import { readFileSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { getContainerName } from "./container.mjs";
import { getPersonaNames, getPresetFiles } from "./completions.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..", "..");

// Commands that require a running container
const NEEDS_CONTAINER = new Set([
  "list",
  "create",
  "remove",
  "update",
  "logs",
  "shell",
  "set-key",
  "get-keys",
  "remove-key",
  "clear-keys",
  "providers",
  "mail",
  "sync-aliases",
  "soft-reset",
  "swarm-status",
  "swarm-stop",
  "health",
  "task-add",
  "task-list",
  "task-ready",
  "task-update",
  "task-graph",
  "artifact-list",
  "artifact-register",
  "artifact-get",
]);

const COMMANDS = {
  // --- Container ---
  build: {
    description: "Build the Docker image",
    category: "Container",
    toSpawn: () => ({ cmd: "docker", args: ["compose", "build"] }),
  },
  up: {
    description: "Start the container",
    category: "Container",
    toSpawn: () => ({ cmd: "docker", args: ["compose", "up", "-d"] }),
  },
  down: {
    description: "Stop and remove the container",
    category: "Container",
    toSpawn: () => ({ cmd: "docker", args: ["compose", "down"] }),
  },
  restart: {
    description: "Restart the container",
    category: "Container",
    sequence: ["down", "up"],
  },
  "container-logs": {
    description: "View container logs",
    category: "Container",
    toSpawn: () => ({
      cmd: "docker",
      args: ["compose", "logs", "-f", "--timestamps"],
    }),
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
    usage:
      "create <name> [--persona <name>] [--instructions <text>] [--api-key <PROVIDER=key>]",
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
      cmd: "docker",
      args: [
        "compose",
        "exec",
        "-T",
        getContainerName(),
        "journalctl",
        "-u",
        `agent@${args[0]}.service`,
        "-f",
        "--no-pager",
      ],
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
    description: "Remove all agents and clear logs",
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

  // --- Swarm ---
  "swarm-status": {
    description: "Show task board, health, costs, and events",
    usage: "swarm-status [--tasks] [--costs] [--events] [--json]",
    category: "Swarm",
    toSpawn: (args) => ({ cmd: "./scripts/swarm-status.sh", args }),
  },
  "swarm-stop": {
    description: "Stop all agents and the orchestrator",
    usage: 'swarm-stop [--reason "<text>"]',
    category: "Swarm",
    toSpawn: (args) => ({ cmd: "./scripts/stop-swarm.sh", args }),
  },
  health: {
    description: "Check agent heartbeat health",
    usage: "health [--stale-after <seconds>] [--json]",
    category: "Swarm",
    toSpawn: (args) => ({ cmd: "./scripts/check-health.sh", args }),
  },
  "task-add": {
    description: "Add a task to the shared board",
    usage:
      'task-add "<subject>" <owner> [--description "<text>"] [--blocked-by <task-id,...>]',
    category: "Swarm",
    minArgs: 2,
    toSpawn: (args) => {
      const subject = args[0];
      const owner = args[1];
      const spawnArgs = ["add", subject, "--owner", owner, ...args.slice(2)];
      return { cmd: "./scripts/task.sh", args: spawnArgs };
    },
  },
  "task-list": {
    description: "List all tasks on the board",
    usage: "task-list [--owner <name>] [--status <status>]",
    category: "Swarm",
    toSpawn: (args) => ({ cmd: "./scripts/task.sh", args: ["list", ...args] }),
  },
  "task-ready": {
    description: "List tasks ready to start (blockers satisfied)",
    usage: "task-ready [--owner <name>]",
    category: "Swarm",
    toSpawn: (args) => ({ cmd: "./scripts/task.sh", args: ["ready", ...args] }),
  },
  "task-update": {
    description: "Update a task's status",
    usage: 'task-update <id> <status> [--result "<text>"]',
    category: "Swarm",
    minArgs: 2,
    toSpawn: (args) => {
      const id = args[0];
      const status = args[1];
      const spawnArgs = ["update", id, "--status", status, ...args.slice(2)];
      return { cmd: "./scripts/task.sh", args: spawnArgs };
    },
  },
  "task-graph": {
    description: "Show task dependency graph",
    category: "Swarm",
    toSpawn: () => ({ cmd: "./scripts/task.sh", args: ["graph"] }),
  },
  "artifact-list": {
    description: "List shared artifacts",
    usage: "artifact-list [--producer <name>]",
    category: "Swarm",
    toSpawn: (args) => ({
      cmd: "./scripts/artifact.sh",
      args: ["list", ...args],
    }),
  },
  "artifact-register": {
    description: "Register a shared artifact",
    usage: 'artifact-register <path> [--description "<text>"]',
    category: "Swarm",
    minArgs: 1,
    toSpawn: (args) => ({
      cmd: "./scripts/artifact.sh",
      args: ["register", ...args],
    }),
  },
  "artifact-get": {
    description: "Get metadata for an artifact",
    usage: "artifact-get <path>",
    category: "Swarm",
    minArgs: 1,
    toSpawn: (args) => ({
      cmd: "./scripts/artifact.sh",
      args: ["get", ...args],
    }),
  },

  // --- Presets ---
  "list-presets": {
    description: "List available workflow presets",
    category: "Presets",
    builtin: true,
  },
  "load-preset": {
    description: "Load a workflow preset",
    usage: "load-preset <file> [--dry-run] [--skip-existing]",
    category: "Presets",
    minArgs: 1,
    toSpawn: (args) => ({ cmd: "./scripts/load-preset.sh", args }),
  },
  "preset-info": {
    description: "Show details of a preset file",
    usage: "preset-info <file>",
    category: "Presets",
    minArgs: 1,
    builtin: true,
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
    return {
      error: `Unknown command: '${name}'. Type 'help' for available commands.`,
    };
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
  const lines = [
    { text: "  Available personas:", type: "info" },
    { text: "", type: "stdout" },
  ];
  for (const name of names) {
    const label =
      name === "base" ? `  ${name} (applied to all agents)` : `  ${name}`;
    lines.push({ text: `    ${label}`, type: "stdout" });
  }
  lines.push({ text: "", type: "stdout" });
  lines.push({
    text: "  Usage: create <name> --persona <name>",
    type: "stdout",
  });
  return lines;
}

export function getReadMailLines(agentName) {
  // Validate agent name to prevent path traversal
  if (!/^[a-z_][a-z0-9_-]*$/.test(agentName)) {
    return [{ text: `  Invalid agent name: ${agentName}`, type: "stderr" }];
  }

  // Mail is stored in Maildir format at ~/Maildir/{new,cur}/
  const maildirBase = resolve(PROJECT_ROOT, "home", agentName, "Maildir");
  const MAX_MESSAGES = 50;
  const lines = [];
  let messageCount = 0;
  let totalFiles = 0;

  for (const subdir of ["new", "cur"]) {
    const dirPath = resolve(maildirBase, subdir);
    let files;
    try {
      files = readdirSync(dirPath)
        .filter((f) => !f.startsWith("."))
        .sort();
    } catch {
      continue;
    }
    totalFiles += files.length;
    for (const file of files) {
      if (messageCount >= MAX_MESSAGES) break;
      try {
        const content = readFileSync(resolve(dirPath, file), "utf-8");
        messageCount++;
        const label = subdir === "new" ? " [NEW]" : "";
        lines.push({
          text: `--- Message ${messageCount}${label} ---`,
          type: "info",
        });
        lines.push(
          ...content
            .split("\n")
            .map((line) => ({ text: line, type: "stdout" })),
        );
        lines.push({ text: "", type: "stdout" });
      } catch {
        continue;
      }
    }
  }

  if (messageCount === 0) {
    return [{ text: `  No mail for ${agentName}.`, type: "info" }];
  }
  if (totalFiles > MAX_MESSAGES) {
    lines.push({
      text: `  (showing ${MAX_MESSAGES} of ${totalFiles} messages)`,
      type: "info",
    });
  }
  return lines;
}

export function getListPresetsLines() {
  const files = getPresetFiles();
  if (files.length === 0) {
    return [
      { text: "  No presets found in presets/", type: "info" },
      { text: "", type: "stdout" },
      {
        text: "  Create a JSON file in presets/ to get started.",
        type: "stdout",
      },
    ];
  }
  const lines = [
    { text: "  Available presets:", type: "info" },
    { text: "", type: "stdout" },
  ];
  for (const file of files) {
    const filePath = resolve(PROJECT_ROOT, file);
    try {
      const data = JSON.parse(readFileSync(filePath, "utf-8"));
      const name = file.replace("presets/", "").replace(".json", "");
      const desc = data.description || "No description";
      lines.push({ text: `    ${name.padEnd(25)} ${desc}`, type: "stdout" });
    } catch {
      const name = file.replace("presets/", "").replace(".json", "");
      lines.push({
        text: `    ${name.padEnd(25)} (error reading file)`,
        type: "stderr",
      });
    }
  }
  lines.push({ text: "", type: "stdout" });
  lines.push({
    text: "  Usage: load-preset <file> [--dry-run] [--skip-existing]",
    type: "stdout",
  });
  return lines;
}

export function getPresetInfoLines(file) {
  const filePath = resolve(PROJECT_ROOT, file);
  let data;
  try {
    data = JSON.parse(readFileSync(filePath, "utf-8"));
  } catch (err) {
    return [
      { text: `  Error reading ${file}: ${err.message}`, type: "stderr" },
    ];
  }

  const lines = [];
  const name = file.replace("presets/", "").replace(".json", "");
  lines.push({ text: `  Preset: ${name}`, type: "info" });
  lines.push({
    text: `  Description: ${data.description || "No description"}`,
    type: "stdout",
  });
  lines.push({ text: "", type: "stdout" });

  // Agents
  if (data.agents && data.agents.length > 0) {
    lines.push({ text: "  Agents:", type: "info" });
    for (const agent of data.agents) {
      const persona = agent.persona ? ` (persona: ${agent.persona})` : "";
      lines.push({ text: `    ${agent.name}${persona}`, type: "stdout" });
    }
    lines.push({ text: "", type: "stdout" });
  }

  // Task DAG
  if (data.tasks && data.tasks.length > 0) {
    lines.push({ text: "  Tasks:", type: "info" });
    for (const task of data.tasks) {
      const owner = task.owner ? ` [${task.owner}]` : "";
      const blocked =
        task.blocked_by && task.blocked_by.length > 0
          ? ` (blocked by: ${task.blocked_by.join(", ")})`
          : "";
      const id = task.id ? `${task.id}: ` : "";
      lines.push({
        text: `    ${id}${task.subject}${owner}${blocked}`,
        type: "stdout",
      });
    }
    lines.push({ text: "", type: "stdout" });
  }

  // Detect ${VAR} placeholders
  const raw = readFileSync(filePath, "utf-8");
  const varPattern = /\$\{([^}]+)\}/g;
  const vars = new Set();
  let match;
  while ((match = varPattern.exec(raw)) !== null) {
    vars.add(match[1]);
  }
  if (vars.size > 0) {
    lines.push({ text: "  Placeholders:", type: "info" });
    for (const v of vars) {
      lines.push({ text: `    \${${v}}`, type: "stdout" });
    }
    lines.push({ text: "", type: "stdout" });
  }

  return lines;
}

export { COMMANDS };
