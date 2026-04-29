import { readFileSync } from 'node:fs';
import { createServer } from 'node:https';
import { GreetdClient } from './greetd-client.mjs';
import { createLoginGreeterApp } from './login-greeter-app.mjs';

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const tlsKeyPath = requireEnv('OLC_TLS_KEY');
const tlsCertPath = requireEnv('OLC_TLS_CERT');
const listenPort = Number(process.env.OLC_GREETER_PORT || '9444');
const client = new GreetdClient({
  socketPath: requireEnv('GREETD_SOCK'),
  sessionCommand: requireEnv('OLC_GREETD_LOGIN_CMD'),
});

let shuttingDown = false;
let server = null;

function closeSoon() {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  setTimeout(async () => {
    try {
      await client.cancel();
    } catch {
      // Ignore cancellation during shutdown.
    }
    server?.close(() => {
      process.exit(0);
    });
    setTimeout(() => process.exit(0), 500).unref();
  }, 150).unref();
}

const app = createLoginGreeterApp({
  client,
  onSessionStarted: () => {
    closeSoon();
  },
});

server = createServer({
  key: readFileSync(tlsKeyPath),
  cert: readFileSync(tlsCertPath),
}, app.handleRequest);

for (const signal of [ 'SIGINT', 'SIGTERM' ]) {
  process.on(signal, async () => {
    try {
      await client.cancel();
    } finally {
      process.exit(0);
    }
  });
}

server.listen(listenPort, '127.0.0.1', () => {
  console.log(`OLC_LOGIN_GREETER_OK https://localhost:${listenPort}/login`);
});
