#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function resolveDataDir() {
  return (
    process.env.PLUGIN_DATA ||
    process.env.COMPUTER_USE_DATA_DIR ||
    path.join(os.tmpdir(), "agy-computer-use-data")
  );
}

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  raw += chunk;
});

process.stdin.on("end", () => {
  let payload = {};
  try {
    if (raw.trim()) payload = JSON.parse(raw);
  } catch {
    // Proceed cleanly even on malformed stdin
  }

  const dataDir = resolveDataDir();
  const stopFile = path.join(dataDir, "EMERGENCY_STOP");

  if (process.env.COMPUTER_USE_DISABLED === "1" || fs.existsSync(stopFile)) {
    process.stdout.write(
      JSON.stringify({
        decision: "deny",
        reason: `Computer Use automation is paused (remove ${stopFile} or unset COMPUTER_USE_DISABLED to resume).`,
      })
    );
    return;
  }

  try {
    fs.mkdirSync(dataDir, { recursive: true });
    const toolName = payload?.toolCall?.name || "unknown";
    const rawArgs = payload?.toolCall?.args || {};
    const redact = process.env.COMPUTER_USE_REDACT_LOGS === "1";
    const safeArgs = { ...rawArgs };
    if (redact && typeof safeArgs.text === "string") {
      safeArgs.text = `[REDACTED ${safeArgs.text.length} chars]`;
    }

    const entry = {
      ts: new Date().toISOString(),
      conversationId: payload?.conversationId || null,
      tool: toolName,
      args: safeArgs,
    };
    fs.appendFileSync(path.join(dataDir, "audit.jsonl"), JSON.stringify(entry) + "\n", "utf8");
  } catch {
    // Never fail tool execution due to audit log I/O
  }

  process.stdout.write(JSON.stringify({ decision: "allow" }));
});
