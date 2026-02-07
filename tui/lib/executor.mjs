import { spawn } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..", "..");

export function getProjectRoot() {
  return PROJECT_ROOT;
}

export function execute(cmd, args, { onStdout, onStderr, onExit }) {
  const child = spawn(cmd, args, {
    cwd: PROJECT_ROOT,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env },
  });

  child.stdout.on("data", (data) => {
    for (const line of data.toString().split("\n")) {
      if (line) onStdout(line);
    }
  });

  child.stderr.on("data", (data) => {
    for (const line of data.toString().split("\n")) {
      if (line) onStderr(line);
    }
  });

  child.on("close", (code) => onExit(code));
  child.on("error", (err) => {
    onStderr(err.message);
    onExit(1);
  });

  return { kill: () => child.kill("SIGTERM") };
}
