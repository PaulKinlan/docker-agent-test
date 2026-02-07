import React from "react";
import { Box, Text } from "ink";

export default function StatusBar({ containerName, status }) {
  const statusColor = status === "up" ? "green" : "red";
  const statusIcon = status === "up" ? "\u25cf" : "\u25cb";
  const statusLabel = status === "up" ? "running" : "stopped";

  return (
    React.createElement(Box, { paddingX: 1 },
      React.createElement(Text, { bold: true, color: "cyan" }, "agent-tui"),
      React.createElement(Text, { dimColor: true }, "  \u2502  "),
      React.createElement(Text, { dimColor: true }, containerName),
      React.createElement(Text, null, " "),
      React.createElement(Text, { color: statusColor }, `${statusIcon} ${statusLabel}`),
    )
  );
}
