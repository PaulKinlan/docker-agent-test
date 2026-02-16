import React, { useState, useCallback, useEffect, useRef } from "react";
import { Box, useApp, useInput } from "ink";
import StatusBar from "./components/StatusBar.mjs";
import Output from "./components/Output.mjs";
import Prompt from "./components/Prompt.mjs";
import VarPrompt from "./components/VarPrompt.mjs";
import getBannerLines from "./components/Banner.mjs";
import { getContainerName, getContainerStatus } from "./lib/container.mjs";
import { execute } from "./lib/executor.mjs";
import {
  parse,
  needsContainer,
  getHelpLines,
  getPersonaLines,
  getReadMailLines,
  getListPresetsLines,
  getPresetInfoLines,
  COMMANDS,
} from "./lib/commands.mjs";
import {
  resolvePresetPath,
  extractPresetVars,
  parseInlineVars,
} from "./lib/preset-vars.mjs";

let lineId = 0;
function nextId() {
  return String(++lineId);
}

export default function App() {
  const { exit } = useApp();
  const [lines, setLines] = useState(() =>
    getBannerLines().map((l) => ({ ...l, id: nextId() })),
  );
  const [isRunning, setIsRunning] = useState(false);
  const [containerStatus, setContainerStatus] = useState("unknown");
  const [promptState, setPromptState] = useState(null);
  const childRef = useRef(null);
  const containerName = getContainerName();

  // Poll container status
  useEffect(() => {
    const check = () => setContainerStatus(getContainerStatus());
    check();
    const timer = setInterval(check, 5000);
    return () => clearInterval(timer);
  }, []);

  const appendLines = useCallback((newLines) => {
    setLines((prev) => [
      ...prev,
      ...newLines.map((l) => ({ ...l, id: nextId() })),
    ]);
  }, []);

  const appendLine = useCallback(
    (text, type) => {
      appendLines([{ text, type }]);
    },
    [appendLines],
  );

  // Ctrl+C handling
  useInput((input, key) => {
    if (key.ctrl && input === "c") {
      if (promptState) {
        appendLine("  Preset loading cancelled.", "system");
        setPromptState(null);
      } else if (isRunning && childRef.current) {
        childRef.current.kill();
        childRef.current = null;
        setIsRunning(false);
        appendLine("  Cancelled.", "system");
      } else {
        exit();
      }
    }
  });

  const runProcess = useCallback(
    (cmd, args) => {
      setIsRunning(true);
      const child = execute(cmd, args, {
        onStdout: (line) => appendLine(line, "stdout"),
        onStderr: (line) => appendLine(line, "stderr"),
        onExit: (code) => {
          if (code === 0) {
            appendLine("  Done.", "success");
          } else if (code !== null) {
            appendLine(`  Exited with code ${code}.`, "error");
          }
          setIsRunning(false);
          childRef.current = null;
          // Refresh container status after container commands
          setContainerStatus(getContainerStatus());
        },
      });
      childRef.current = child;
    },
    [appendLine],
  );

  const runProcessWithEnv = useCallback(
    (cmd, args, extraEnv) => {
      setIsRunning(true);
      const child = execute(
        cmd,
        args,
        {
          onStdout: (line) => appendLine(line, "stdout"),
          onStderr: (line) => appendLine(line, "stderr"),
          onExit: (code) => {
            if (code === 0) {
              appendLine("  Done.", "success");
            } else if (code !== null) {
              appendLine(`  Exited with code ${code}.`, "error");
            }
            setIsRunning(false);
            childRef.current = null;
            setContainerStatus(getContainerStatus());
          },
        },
        extraEnv,
      );
      childRef.current = child;
    },
    [appendLine],
  );

  const runSequence = useCallback(
    async (steps) => {
      for (const stepName of steps) {
        const result = parse(stepName);
        if (!result || result.error || !result.def.toSpawn) continue;
        const { cmd, args } = result.def.toSpawn(result.args);
        await new Promise((resolve) => {
          setIsRunning(true);
          const child = execute(cmd, args, {
            onStdout: (line) => appendLine(line, "stdout"),
            onStderr: (line) => appendLine(line, "stderr"),
            onExit: (code) => {
              setIsRunning(false);
              childRef.current = null;
              if (code !== 0) {
                appendLine(`  ${stepName} failed with code ${code}.`, "error");
              }
              resolve(code);
            },
          });
          childRef.current = child;
        });
      }
      appendLine("  Done.", "success");
      setContainerStatus(getContainerStatus());
    },
    [appendLine],
  );

  const handleVarPromptComplete = useCallback(
    (envMap) => {
      if (!promptState) return;
      const { remainingArgs, envOverrides } = promptState;
      const mergedEnv = { ...envOverrides, ...envMap };

      appendLine("  Variables configured. Loading preset...", "info");
      setPromptState(null);

      const def = COMMANDS["load-preset"];
      const { cmd, args: spawnArgs } = def.toSpawn(remainingArgs);
      runProcessWithEnv(cmd, spawnArgs, mergedEnv);
    },
    [promptState, appendLine, runProcessWithEnv],
  );

  const handleVarPromptCancel = useCallback(() => {
    appendLine("  Preset loading cancelled.", "system");
    setPromptState(null);
  }, [appendLine]);

  const handleSubmit = useCallback(
    (input) => {
      if (!input) return;

      appendLine(`  > ${input}`, "system");

      const result = parse(input);

      if (!result) return;

      if (result.error) {
        appendLine(`  ${result.error}`, "error");
        return;
      }

      const { name, args, def } = result;

      // Check container requirement
      if (needsContainer(name) && containerStatus !== "up") {
        appendLine("  Container is not running. Run 'up' first.", "error");
        return;
      }

      // Handle sequences (restart)
      if (def.sequence) {
        runSequence(def.sequence);
        return;
      }

      // Handle builtins
      if (def.builtin) {
        switch (name) {
          case "help":
            appendLines(getHelpLines());
            break;
          case "clear":
            setLines([]);
            break;
          case "exit":
          case "quit":
            exit();
            break;
          case "shell":
            appendLine(
              `  Interactive shells cannot run inside the TUI.`,
              "info",
            );
            appendLine(
              `  Run instead: make agent-shell NAME=${args[0]}`,
              "info",
            );
            break;
          case "personas":
            appendLines(getPersonaLines());
            break;
          case "read-mail":
            appendLines(getReadMailLines(args[0]));
            break;
          case "reset":
            appendLine(
              "  Full reset requires sudo and cannot run inside the TUI.",
              "info",
            );
            appendLine("  Run instead: make reset", "info");
            break;
          case "status": {
            const s = getContainerStatus();
            setContainerStatus(s);
            const icon = s === "up" ? "\u25cf" : "\u25cb";
            const label = s === "up" ? "running" : "stopped";
            appendLine(
              `  ${containerName}: ${icon} ${label}`,
              s === "up" ? "success" : "error",
            );
            break;
          }
          case "list-presets":
            appendLines(getListPresetsLines());
            break;
          case "preset-info":
            appendLines(getPresetInfoLines(args[0]));
            break;
        }
        return;
      }

      // Intercept load-preset to prompt for env vars
      if (name === "load-preset" && def.toSpawn) {
        const { envOverrides, remainingArgs } = parseInlineVars(args);
        const presetFile = remainingArgs[0];

        if (!presetFile) {
          appendLine("  Error: Preset file is required.", "error");
          return;
        }

        const resolvedPath = resolvePresetPath(presetFile);
        if (!resolvedPath) {
          appendLine(`  Preset not found: ${presetFile}`, "error");
          return;
        }

        const vars = extractPresetVars(resolvedPath);

        // Check which vars still need prompting
        const needsPrompting = vars.filter(
          (v) => !(v.name in envOverrides) && !process.env[v.name],
        );

        if (needsPrompting.length === 0) {
          // All vars satisfied — spawn immediately
          const { cmd, args: spawnArgs } = def.toSpawn(remainingArgs);
          runProcessWithEnv(cmd, spawnArgs, envOverrides);
        } else {
          // Enter prompting mode
          const presetName = presetFile
            .replace("presets/", "")
            .replace(".json", "");
          setPromptState({
            presetName,
            vars,
            envOverrides,
            remainingArgs,
          });
        }
        return;
      }

      // Spawn process
      if (def.toSpawn) {
        const { cmd, args: spawnArgs } = def.toSpawn(args);
        runProcess(cmd, spawnArgs);
      }
    },
    [
      appendLine,
      appendLines,
      containerStatus,
      containerName,
      exit,
      runProcess,
      runProcessWithEnv,
      runSequence,
    ],
  );

  return React.createElement(
    Box,
    { flexDirection: "column" },
    React.createElement(StatusBar, { containerName, status: containerStatus }),
    React.createElement(Output, { lines }),
    promptState
      ? React.createElement(VarPrompt, {
          presetName: promptState.presetName,
          vars: promptState.vars,
          envOverrides: promptState.envOverrides,
          onComplete: handleVarPromptComplete,
          onCancel: handleVarPromptCancel,
        })
      : React.createElement(Prompt, { onSubmit: handleSubmit, isRunning }),
  );
}
