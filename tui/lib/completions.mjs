import { readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..", "..");

const COMMAND_NAMES = [
  "build", "up", "down", "restart", "status",
  "list", "create", "remove", "update", "logs", "shell", "personas",
  "set-key", "get-keys", "remove-key",
  "mail", "read-mail",
  "snapshot", "snapshot-log", "snapshot-diff",
  "help", "clear", "exit", "quit",
];

const AGENT_NAME_COMMANDS = new Set([
  "remove", "update", "logs", "shell",
  "set-key", "get-keys", "remove-key",
  "mail", "read-mail",
]);

export function getAgentNames() {
  try {
    return readdirSync(resolve(PROJECT_ROOT, "home"))
      .filter((f) => f !== ".gitkeep" && !f.startsWith("."));
  } catch {
    return [];
  }
}

export function getPersonaNames() {
  try {
    return readdirSync(resolve(PROJECT_ROOT, "config", "personas"))
      .filter((f) => f.endsWith(".md"))
      .map((f) => f.replace(".md", ""));
  } catch {
    return [];
  }
}

export function complete(input) {
  const parts = input.trimStart().split(/\s+/);

  // Complete command name
  if (parts.length <= 1) {
    const prefix = parts[0] || "";
    return COMMAND_NAMES.filter((c) => c.startsWith(prefix));
  }

  const cmd = parts[0];
  const lastPart = parts[parts.length - 1];
  const prevPart = parts.length > 2 ? parts[parts.length - 2] : "";

  // Complete --persona value
  if (prevPart === "--persona") {
    return getPersonaNames().filter((n) => n.startsWith(lastPart));
  }

  // Complete agent name (second argument for most commands)
  if (parts.length === 2 && AGENT_NAME_COMMANDS.has(cmd)) {
    return getAgentNames().filter((n) => n.startsWith(lastPart));
  }

  return [];
}
