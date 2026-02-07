import React, { useState, useCallback } from "react";
import { Box, Text, useInput } from "ink";
import TextInput from "ink-text-input";
import { complete } from "../lib/completions.mjs";

export default function Prompt({ onSubmit, isRunning }) {
  const [value, setValue] = useState("");
  const [history, setHistory] = useState([]);
  const [historyIndex, setHistoryIndex] = useState(-1);

  const handleSubmit = useCallback(
    (input) => {
      const trimmed = input.trim();
      if (trimmed) {
        setHistory((prev) => [trimmed, ...prev]);
      }
      setHistoryIndex(-1);
      setValue("");
      onSubmit(trimmed);
    },
    [onSubmit]
  );

  useInput((input, key) => {
    if (isRunning) return;

    // Up arrow — navigate history
    if (key.upArrow) {
      if (history.length > 0) {
        const next = Math.min(historyIndex + 1, history.length - 1);
        setHistoryIndex(next);
        setValue(history[next]);
      }
      return;
    }

    // Down arrow — navigate history forward
    if (key.downArrow) {
      if (historyIndex > 0) {
        const next = historyIndex - 1;
        setHistoryIndex(next);
        setValue(history[next]);
      } else {
        setHistoryIndex(-1);
        setValue("");
      }
      return;
    }

    // Tab — autocomplete
    if (key.tab) {
      const matches = complete(value);
      if (matches.length === 1) {
        const parts = value.trimStart().split(/\s+/);
        parts[parts.length - 1] = matches[0];
        setValue(parts.join(" ") + " ");
      }
      return;
    }
  });

  if (isRunning) {
    return React.createElement(
      Box,
      null,
      React.createElement(Text, { color: "yellow" }, "  ... "),
      React.createElement(Text, { dimColor: true }, "running (Ctrl+C to cancel)")
    );
  }

  return React.createElement(
    Box,
    null,
    React.createElement(Text, { color: "green", bold: true }, "  > "),
    React.createElement(TextInput, {
      value,
      onChange: setValue,
      onSubmit: handleSubmit,
    })
  );
}
