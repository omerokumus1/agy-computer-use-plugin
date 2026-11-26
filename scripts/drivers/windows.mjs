import { spawn } from "node:child_process";
import path from "node:path";
import { resolvePluginRoot } from "./common.mjs";

export function createWindowsTransport() {
  const pluginRoot = resolvePluginRoot();
  const workerScript = path.join(pluginRoot, "scripts", "native", "win_worker.ps1");

  let proc = null;
  let buffer = "";
  let nextId = 1;
  const pending = new Map();

  function rejectAll(err) {
    for (const entry of pending.values()) {
      clearTimeout(entry.timer);
      entry.reject(err);
    }
    pending.clear();
  }

  function ensureWorker() {
    if (proc && !proc.killed && proc.exitCode === null) {
      return proc;
    }

    const shell = process.env.COMPUTER_USE_POWERSHELL || "powershell.exe";
    proc = spawn(
      shell,
      ["-NoProfile", "-NonInteractive", "-Sta", "-ExecutionPolicy", "Bypass", "-File", workerScript],
      { stdio: ["pipe", "pipe", "pipe"], windowsHide: true }
    );

    buffer = "";
    proc.stdout.setEncoding("utf8");
    proc.stdout.on("data", (chunk) => {
      buffer += chunk;
      let idx;
      while ((idx = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, idx).trim();
        buffer = buffer.slice(idx + 1);
        if (!line) continue;
        let msg;
        try {
          msg = JSON.parse(line);
        } catch {
          continue;
        }
        const entry = pending.get(msg.id);
        if (!entry) continue;
        pending.delete(msg.id);
        clearTimeout(entry.timer);
        if (msg.ok) entry.resolve(msg.result);
        else entry.reject(new Error(msg.error || "Windows worker command failed."));
      }
    });

    proc.stderr.setEncoding("utf8");
    proc.stderr.on("data", (chunk) => {
      if (chunk.trim()) process.stderr.write(`[win_worker] ${chunk}`);
    });

    proc.on("exit", (code, signal) => {
      proc = null;
      rejectAll(new Error(`Windows worker exited (code=${code}, signal=${signal})`));
    });

    proc.on("error", (err) => {
      proc = null;
      rejectAll(err);
    });

    return proc;
  }

  return {
    invoke(action, params = {}, timeoutMs = 20000) {
      const child = ensureWorker();
      const id = nextId++;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`Windows worker timed out on "${action}" after ${timeoutMs}ms`));
        }, timeoutMs);
        pending.set(id, { resolve, reject, timer });
        child.stdin.write(JSON.stringify({ id, action, params }) + "\n");
      });
    },
    async dispose() {
      if (proc && !proc.killed) {
        proc.kill();
        proc = null;
      }
    },
  };
}
