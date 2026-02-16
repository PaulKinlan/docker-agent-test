import React, { useState, useCallback, useEffect, useMemo } from "react";
import { Box, Text, useInput } from "ink";
import TextInput from "ink-text-input";

/**
 * Prompts the user for preset environment variables one at a time.
 *
 * Props:
 *   presetName  - Display name of the preset being loaded
 *   vars        - Array of { name, defaultValue } from extractPresetVars
 *   envOverrides - KEY=VALUE pairs already provided inline on the command
 *   onComplete  - Called with { VAR: "value", ... } when all vars are collected
 *   onCancel    - Called when the user presses Escape
 */
export default function VarPrompt({
  presetName,
  vars,
  envOverrides,
  onComplete,
  onCancel,
}) {
  const needsPrompting = useMemo(
    () =>
      vars.filter(
        (v) => !(v.name in envOverrides) && !process.env[v.name],
      ),
    [vars, envOverrides],
  );

  const [currentIndex, setCurrentIndex] = useState(0);
  const [value, setValue] = useState("");
  const [collected, setCollected] = useState({});

  useInput((_input, key) => {
    if (key.escape) {
      onCancel();
    }
  });

  // When all vars are already satisfied, complete immediately
  useEffect(() => {
    if (needsPrompting.length === 0) {
      onComplete({});
    }
  }, [needsPrompting.length, onComplete]);

  // When we've finished prompting all vars, complete with collected values
  useEffect(() => {
    if (needsPrompting.length > 0 && currentIndex >= needsPrompting.length) {
      onComplete(collected);
    }
  }, [currentIndex, needsPrompting.length, collected, onComplete]);

  if (needsPrompting.length === 0 || currentIndex >= needsPrompting.length) {
    return null;
  }

  const currentVar = needsPrompting[currentIndex];
  const progress = `(${currentIndex + 1}/${needsPrompting.length})`;

  const handleSubmit = (input) => {
    const trimmed = input.trim();
    if (trimmed) {
      setCollected((prev) => ({ ...prev, [currentVar.name]: trimmed }));
    }
    setValue("");
    setCurrentIndex((i) => i + 1);
  };

  const defaultHint =
    currentVar.defaultValue !== null
      ? ` (default: ${currentVar.defaultValue})`
      : " (required, no default)";

  return React.createElement(
    Box,
    { flexDirection: "column" },
    React.createElement(
      Box,
      null,
      React.createElement(
        Text,
        { color: "cyan", bold: true },
        `  Configure ${presetName} `,
      ),
      React.createElement(Text, { dimColor: true }, progress),
    ),
    React.createElement(
      Box,
      null,
      React.createElement(Text, { color: "yellow" }, `  ${currentVar.name}`),
      React.createElement(Text, { dimColor: true }, defaultHint),
    ),
    React.createElement(
      Box,
      null,
      React.createElement(Text, { color: "green", bold: true }, "  > "),
      React.createElement(TextInput, {
        value,
        onChange: setValue,
        onSubmit: handleSubmit,
      }),
    ),
    React.createElement(
      Box,
      null,
      React.createElement(
        Text,
        { dimColor: true },
        "  Press Enter to accept default, Escape to cancel",
      ),
    ),
  );
}
