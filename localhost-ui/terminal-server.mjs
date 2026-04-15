import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { createTerminalApp } from './terminal-app.mjs';

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

const app = createTerminalApp({
  bashBin: requireEnv('OLC_BASH'),
  demoUser: getDemoUser(),
  terminalClientCss: readFileSync(requireEnv('OLC_TERMINAL_CLIENT_CSS'), 'utf8'),
  terminalClientJs: readFileSync(requireEnv('OLC_TERMINAL_CLIENT_JS'), 'utf8'),
  ttydBin: requireEnv('OLC_TTYD'),
});

const server = createServer(app.handleRequest);

server.on('upgrade', app.handleUpgrade);

server.listen(Number(process.env.OLC_TERMINAL_PORT || 9444), '127.0.0.1', () => {
  console.log('OLC_TERMINAL_SERVER_OK http://127.0.0.1:9444/terminal');
});
