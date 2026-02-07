export default function getBannerLines() {
  return [
    { text: "", type: "stdout" },
    { text: "  agent-tui v0.1.0", type: "info" },
    { text: "  Interactive CLI for docker-agent-test", type: "stdout" },
    { text: '  Type "help" for available commands, "exit" to quit.', type: "stdout" },
    { text: "", type: "stdout" },
  ];
}
