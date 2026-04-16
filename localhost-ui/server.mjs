import { readFileSync } from 'node:fs';
import { createServer } from 'node:https';
import { createOlcApp } from './app.mjs';
import { createSelectedSystemControls } from './system-controls.mjs';

function requireEnv(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

const tlsKeyPath = requireEnv('OLC_TLS_KEY');
const tlsCertPath = requireEnv('OLC_TLS_CERT');
const app = createOlcApp({
  systemControls: createSelectedSystemControls(),
  terminalUpstreamUrl: process.env.OLC_TERMINAL_UPSTREAM || 'https://127.0.0.1:9443',
});

const server = createServer({
  key: readFileSync(tlsKeyPath),
  cert: readFileSync(tlsCertPath),
}, app.handleRequest);

server.on('upgrade', app.handleUpgrade);

server.listen(443, '127.0.0.1', () => {
  console.log('OLC_UI_SERVER_OK https://localhost');
});
