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

function getDemoUser() {
  const entry = readFileSync('/etc/passwd', 'utf8')
    .split('\n')
    .find(line => line.startsWith('demo:'));

  if (!entry) {
    throw new Error('Unable to resolve demo user from /etc/passwd');
  }

  const fields = entry.split(':');
  return {
    uid: fields[2],
    gid: fields[3],
  };
}

const tlsKeyPath = requireEnv('OLC_TLS_KEY');
const tlsCertPath = requireEnv('OLC_TLS_CERT');
const app = createOlcApp({
  bashBin: requireEnv('OLC_BASH'),
  demoUser: getDemoUser(),
  systemControls: createSelectedSystemControls(),
  terminalClientCss: readFileSync(requireEnv('OLC_TERMINAL_CLIENT_CSS'), 'utf8'),
  terminalClientJs: readFileSync(requireEnv('OLC_TERMINAL_CLIENT_JS'), 'utf8'),
  ttydBin: requireEnv('OLC_TTYD'),
});

const server = createServer({
  key: readFileSync(tlsKeyPath),
  cert: readFileSync(tlsCertPath),
}, app.handleRequest);

server.on('upgrade', app.handleUpgrade);

server.listen(443, '127.0.0.1', () => {
  console.log('OLC_UI_SERVER_OK https://localhost');
});
