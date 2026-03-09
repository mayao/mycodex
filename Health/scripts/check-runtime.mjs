const [major] = process.versions.node.split(".").map(Number);

const isSupportedNode = major >= 22 && major < 25;

if (isSupportedNode) {
  process.exit(0);
}

const messageLines = [
  `Unsupported Node.js runtime: v${process.versions.node}`,
  "Use Node.js 22.x LTS for this project.",
  "The current stack can fail on macOS under Node 25 with `EPERM: operation not permitted, read` while starting Next.js or ESLint."
];

if (process.platform === "darwin") {
  messageLines.push(
    'Example: PATH="/opt/homebrew/opt/node@22/bin:$PATH" npm run dev'
  );
}

console.error(messageLines.join("\n"));
process.exit(1);
