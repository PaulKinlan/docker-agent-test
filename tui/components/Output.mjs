import React from "react";
import { Static, Text } from "ink";

const COLORS = {
  stdout: undefined,
  stderr: "red",
  info: "cyan",
  success: "green",
  error: "red",
  system: "gray",
};

export default function Output({ lines }) {
  return React.createElement(
    Static,
    { items: lines },
    (line) =>
      React.createElement(
        Text,
        {
          key: line.id,
          color: COLORS[line.type],
          bold: line.type === "error",
          dimColor: line.type === "system",
        },
        line.text
      )
  );
}
