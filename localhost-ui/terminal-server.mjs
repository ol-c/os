import { readFileSync } from 'node:fs';
import { createServer } from 'node:https';
import { createTerminalApp } from './terminal-app.mjs';
import { getActiveConsoleUser } from './runtime-state.mjs';

function requireEnv(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

const app = createTerminalApp({
  bashBin: requireEnv('OLC_BASH'),
  getTerminalUser: () => getActiveConsoleUser(),
  terminalClientCss: readFileSync(requireEnv('OLC_TERMINAL_CLIENT_CSS'), 'utf8'),
  terminalClientJs: readFileSync(requireEnv('OLC_TERMINAL_CLIENT_JS'), 'utf8'),
  terminalPublicUrl: process.env.OLC_TERMINAL_PUBLIC_URL || '',
  ttydBin: requireEnv('OLC_TTYD'),
});

const server = createServer({
  key: readFileSync(requireEnv('OLC_TLS_KEY')),
  cert: readFileSync(requireEnv('OLC_TLS_CERT')),
}, app.handleRequest);

server.on('upgrade', app.handleUpgrade);

server.listen(Number(process.env.OLC_TERMINAL_PORT || 9443), '127.0.0.1', () => {
  console.log('OLC_TERMINAL_SERVER_OK https://localhost:9443/terminal');
});
