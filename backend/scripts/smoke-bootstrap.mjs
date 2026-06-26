#!/usr/bin/env node

import { spawn } from 'node:child_process';

const port = process.env.SMOKE_PORT || process.env.PORT || '3010';
const timeoutMs = Number(process.env.SMOKE_TIMEOUT_MS || '15000');
const healthUrl = `http://127.0.0.1:${port}/health`;

const child = spawn('node', ['dist/main.js'], {
  cwd: process.cwd(),
  env: {
    ...process.env,
    PORT: String(port),
    NODE_ENV: process.env.NODE_ENV || 'development',
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});

let stdout = '';
let stderr = '';
let finished = false;

function append(buffer, chunk) {
  const next = buffer + chunk.toString();
  return next.length > 8000 ? next.slice(-8000) : next;
}

child.stdout.on('data', (chunk) => {
  stdout = append(stdout, chunk);
});

child.stderr.on('data', (chunk) => {
  stderr = append(stderr, chunk);
});

function cleanup(code, message) {
  if (finished) return;
  finished = true;
  child.kill('SIGTERM');
  if (message) {
    console.error(message);
  }
  process.exit(code);
}

child.on('exit', (code, signal) => {
  if (finished) return;
  cleanup(
    1,
    [
      `[smoke] backend exited before health check (code=${code ?? 'null'}, signal=${signal ?? 'null'})`,
      stdout ? `[smoke] stdout:\n${stdout}` : '',
      stderr ? `[smoke] stderr:\n${stderr}` : '',
    ]
        .filter(Boolean)
        .join('\n'),
  );
});

const deadline = Date.now() + timeoutMs;

async function pollHealth() {
  while (Date.now() < deadline) {
    try {
      const response = await fetch(healthUrl);
      if (response.ok) {
        const body = await response.text();
        cleanup(0, `[smoke] health OK: ${body}`);
        return;
      }
    } catch {
      // keep polling until timeout
    }
    await new Promise((resolve) => setTimeout(resolve, 300));
  }

  cleanup(
    1,
    [
      `[smoke] timed out waiting for ${healthUrl}`,
      stdout ? `[smoke] stdout:\n${stdout}` : '',
      stderr ? `[smoke] stderr:\n${stderr}` : '',
    ]
        .filter(Boolean)
        .join('\n'),
  );
}

void pollHealth();
