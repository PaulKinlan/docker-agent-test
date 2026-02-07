#!/usr/bin/env node
import React from "react";
import { render } from "ink";
import App from "./app.mjs";

if (!process.stdin.isTTY) {
  console.error("agent-tui requires an interactive terminal (TTY).");
  console.error("Run it directly: node cli.mjs  or  make tui");
  process.exit(1);
}

render(React.createElement(App));
