#!/usr/bin/env node
// agent-loop.mjs — Single agentic work cycle using Claude Agent SDK
//
// Performs one cycle of the agent's autonomous loop:
//   1. Check for new mail and pending TODOs
//   2. Process work items following CLAUDE.md instructions
//   3. Exit (caller handles sleep and re-invocation)
//
// Environment:
//   ANTHROPIC_API_KEY       — Required (loaded by run-agent.sh)
//   AGENT_USER              — Set by run-agent.sh
//   HOME                    — Agent home directory (set by systemd)
//   AGENT_MODEL             — Optional model override (default: claude-opus-4-6)
//   AGENT_MAX_TURNS         — Optional max turns per cycle (default: 50)
//   AGENT_CYCLE_TIMEOUT_MS  — Optional cycle timeout in ms (default: 300000 / 5 min)
//
// Exit codes:
//   0 — Cycle completed successfully (or no work to do)
//   1 — Cycle failed: transient error (retry-worthy)
//   2 — Cycle failed: fatal error (bad config, invalid API key — stop retrying)
//   3 — Cycle failed: timeout

import {
  readFileSync,
  writeFileSync,
  appendFileSync,
  mkdirSync,
} from "node:fs";
import { join } from "node:path";
import { query } from "@anthropic-ai/claude-agent-sdk";

const AGENT_USER = process.env.AGENT_USER || process.env.USER || "unknown";
const HOME = process.env.HOME || `/home/${AGENT_USER}`;
const MODEL = process.env.AGENT_MODEL || "claude-opus-4-6";
const MAX_TURNS = parseInt(process.env.AGENT_MAX_TURNS || "50", 10);
const CYCLE_TIMEOUT_MS = parseInt(
  process.env.AGENT_CYCLE_TIMEOUT_MS || "300000",
  10,
);

const RESULTS_DIR = join(HOME, ".agent-results");
const EVENTS_FILE = join(HOME, ".agent-events.jsonl");
const HEARTBEAT_FILE = join(HOME, ".agent-heartbeat");

// Ensure results directory exists
try {
  mkdirSync(RESULTS_DIR, { recursive: true });
} catch {}

// --- Event logging ---
function emitEvent(event, payload = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    agent: AGENT_USER,
    event,
    ...payload,
  };
  try {
    appendFileSync(EVENTS_FILE, JSON.stringify(entry) + "\n");
  } catch {}
}

// --- Heartbeat ---
function writeHeartbeat(phase) {
  try {
    writeFileSync(
      HEARTBEAT_FILE,
      JSON.stringify({
        agent: AGENT_USER,
        phase,
        timestamp: new Date().toISOString(),
        pid: process.pid,
      }),
    );
  } catch {}
}

// --- Result tracking ---
function writeResult(result) {
  const filename = `cycle-${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
  try {
    writeFileSync(join(RESULTS_DIR, filename), JSON.stringify(result, null, 2));
  } catch {}
}

// Classify errors into exit codes
function classifyError(err) {
  const msg = (err.message || "").toLowerCase();
  // Fatal: bad API key, invalid model, auth errors
  if (
    msg.includes("invalid api key") ||
    msg.includes("authentication") ||
    msg.includes("invalid_api_key") ||
    msg.includes("permission denied") ||
    msg.includes("model not found") ||
    msg.includes("invalid model")
  ) {
    return 2; // fatal
  }
  // Timeout
  if (
    msg.includes("abort") ||
    msg.includes("timeout") ||
    msg.includes("timed out")
  ) {
    return 3; // timeout
  }
  // Everything else is transient
  return 1;
}

// Load the agent's persona from agents.md (built from base + specialist persona)
let agentPersona = "";
try {
  agentPersona = readFileSync(join(HOME, "agents.md"), "utf-8").trim();
} catch {
  console.log("[agent-loop] No agents.md found, running without persona");
}

const CYCLE_PROMPT = `You are agent "${AGENT_USER}" waking up for a work cycle.

Read your CLAUDE.md and follow the workflow described there. It covers how to check for work, process tasks, and report results.

If there is no new mail and no pending tasks in TODO.md, you are done — exit cleanly.

Be efficient. Complete what you can in this cycle. You will wake up again soon.`;

async function runCycle() {
  const abortController = new AbortController();
  const cycleStart = Date.now();

  writeHeartbeat("starting");
  emitEvent("cycle_start", { model: MODEL, maxTurns: MAX_TURNS });

  const timeout = setTimeout(() => {
    console.error(
      `[agent-loop] Cycle timeout after ${CYCLE_TIMEOUT_MS}ms, aborting`,
    );
    emitEvent("cycle_timeout", { timeout_ms: CYCLE_TIMEOUT_MS });
    abortController.abort();
  }, CYCLE_TIMEOUT_MS);

  let numTurns = 0;
  let totalCost = null;
  let cycleSubtype = "unknown";

  try {
    const result = query({
      prompt: CYCLE_PROMPT,
      options: {
        model: MODEL,
        maxTurns: MAX_TURNS,
        cwd: HOME,
        abortSignal: abortController.signal,
        allowedTools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"],
        permissionMode: "bypassPermissions",
        systemPrompt: {
          type: "preset",
          preset: "claude_code",
          append: [
            `You are an autonomous agent named "${AGENT_USER}". You run on a shared Unix system. Follow your CLAUDE.md instructions precisely. Be concise. Work independently. Do not ask for user input — make decisions on your own.`,
            agentPersona ? `\n\n## Your Persona\n\n${agentPersona}` : "",
          ].join(""),
        },
        settingSources: ["project"],
      },
    });

    for await (const message of result) {
      writeHeartbeat("running");

      if (message.type === "assistant" && message.message?.content) {
        for (const block of message.message.content) {
          if ("text" in block && block.text) {
            const snippet =
              block.text.length > 200
                ? block.text.substring(0, 200) + "..."
                : block.text;
            console.log(`[agent-loop] ${snippet}`);
          }
        }
      }

      if (message.type === "result") {
        cycleSubtype = message.subtype || "unknown";
        numTurns = message.num_turns || 0;
        totalCost = message.total_cost_usd ?? null;

        if (message.subtype === "success") {
          console.log(
            `[agent-loop] Cycle complete: turns=${numTurns}` +
              (totalCost != null ? ` cost=$${totalCost.toFixed(4)}` : ""),
          );
        } else {
          console.error(
            `[agent-loop] Cycle ended with ${message.subtype}` +
              (message.errors ? `: ${JSON.stringify(message.errors)}` : ""),
          );
        }
      }
    }

    const elapsed = Date.now() - cycleStart;

    // Write structured result
    writeResult({
      agent: AGENT_USER,
      model: MODEL,
      status: cycleSubtype === "success" ? "success" : "failure",
      subtype: cycleSubtype,
      turns: numTurns,
      cost_usd: totalCost,
      elapsed_ms: elapsed,
      timestamp: new Date().toISOString(),
    });

    emitEvent("cycle_end", {
      status: cycleSubtype === "success" ? "success" : "failure",
      turns: numTurns,
      cost_usd: totalCost,
      elapsed_ms: elapsed,
    });

    writeHeartbeat("idle");
    return cycleSubtype === "success" ? 0 : 1;
  } finally {
    clearTimeout(timeout);
  }
}

// --- Main ---
try {
  // Validate API key is present before wasting a cycle
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error("[agent-loop] FATAL: ANTHROPIC_API_KEY is not set");
    emitEvent("fatal_error", { error: "ANTHROPIC_API_KEY not set" });
    writeHeartbeat("error");
    process.exit(2);
  }

  console.log(
    `[agent-loop] Starting cycle for ${AGENT_USER} (model=${MODEL}, maxTurns=${MAX_TURNS}, persona=${agentPersona ? "loaded" : "none"})`,
  );
  const exitCode = await runCycle();
  console.log(`[agent-loop] Cycle finished (exit=${exitCode})`);
  process.exit(exitCode);
} catch (err) {
  const exitCode = classifyError(err);
  console.error(`[agent-loop] Cycle error (exit=${exitCode}): ${err.message}`);
  emitEvent("cycle_error", { error: err.message, exit_code: exitCode });
  writeHeartbeat("error");

  writeResult({
    agent: AGENT_USER,
    model: MODEL,
    status: "error",
    error: err.message,
    exit_code: exitCode,
    timestamp: new Date().toISOString(),
  });

  process.exit(exitCode);
}
