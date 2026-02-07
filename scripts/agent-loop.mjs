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
//   AGENT_MODEL             — Optional model override (default: claude-sonnet-4-5)
//   AGENT_MAX_TURNS         — Optional max turns per cycle (default: 50)
//   AGENT_CYCLE_TIMEOUT_MS  — Optional cycle timeout in ms (default: 300000 / 5 min)
//
// Exit codes:
//   0 — Cycle completed successfully
//   1 — Cycle failed (error logged to stderr)

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { query } from "@anthropic-ai/claude-agent-sdk";

const AGENT_USER = process.env.AGENT_USER || process.env.USER || "unknown";
const HOME = process.env.HOME || `/home/${AGENT_USER}`;
const MODEL = process.env.AGENT_MODEL || "claude-opus-4-6";
const MAX_TURNS = parseInt(process.env.AGENT_MAX_TURNS || "50", 10);
const CYCLE_TIMEOUT_MS = parseInt(process.env.AGENT_CYCLE_TIMEOUT_MS || "300000", 10);

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

  const timeout = setTimeout(() => {
    console.error(`[agent-loop] Cycle timeout after ${CYCLE_TIMEOUT_MS}ms, aborting`);
    abortController.abort();
  }, CYCLE_TIMEOUT_MS);

  try {
    const result = query({
      prompt: CYCLE_PROMPT,
      options: {
        model: MODEL,
        maxTurns: MAX_TURNS,
        cwd: HOME,
        abortSignal: abortController.signal,
        allowedTools: [
          "Bash", "Read", "Write", "Edit", "Glob", "Grep",
        ],
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
      if (message.type === "assistant" && message.message?.content) {
        for (const block of message.message.content) {
          if ("text" in block && block.text) {
            // Log a truncated snippet for observability
            const snippet = block.text.length > 200
              ? block.text.substring(0, 200) + "..."
              : block.text;
            console.log(`[agent-loop] ${snippet}`);
          }
        }
      }

      if (message.type === "result") {
        if (message.subtype === "success") {
          console.log(
            `[agent-loop] Cycle complete: turns=${message.num_turns}` +
            (message.total_cost_usd != null ? ` cost=$${message.total_cost_usd.toFixed(4)}` : "")
          );
        } else {
          console.error(
            `[agent-loop] Cycle ended with ${message.subtype}` +
            (message.errors ? `: ${JSON.stringify(message.errors)}` : "")
          );
        }
      }
    }
  } finally {
    clearTimeout(timeout);
  }
}

// Main
try {
  console.log(`[agent-loop] Starting cycle for ${AGENT_USER} (model=${MODEL}, maxTurns=${MAX_TURNS}, persona=${agentPersona ? "loaded" : "none"})`);
  await runCycle();
  console.log(`[agent-loop] Cycle finished`);
  process.exit(0);
} catch (err) {
  console.error(`[agent-loop] Cycle error: ${err.message}`);
  process.exit(1);
}
