import { execSync } from "node:child_process";

const CONTAINER_NAME = process.env.AGENT_HOST_CONTAINER || "agent-host";

export function getContainerName() {
  return CONTAINER_NAME;
}

export function getContainerStatus() {
  try {
    const output = execSync(
      `docker inspect -f '{{.State.Status}}' ${CONTAINER_NAME}`,
      { timeout: 3000, encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    ).trim();
    return output === "running" ? "up" : "down";
  } catch {
    return "down";
  }
}
