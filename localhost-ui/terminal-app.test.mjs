import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import { EventEmitter } from 'node:events';
import { createTerminalApp } from './terminal-app.mjs';

function createFakeTtydSpawner() {
  const servers = [];
  const children = [];

  function spawnProcess(command, args) {
    const port = Number(args[args.indexOf('--port') + 1]);
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.killed = false;
    child.kill = signal => {
      child.killed = true;
      for (const server of servers.splice(0)) {
        server.close();
      }
      queueMicrotask(() => child.emit('exit', null, signal));
    };

    const server = http.createServer((req, res) => {
      res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('fake ttyd ' + req.url);
    });
    server.listen(port, '127.0.0.1');
    servers.push(server);
    children.push(child);
    return child;
  }

  return {
    children,
    spawnProcess,
    cleanup: () => {
      for (const server of servers.splice(0)) {
        server.close();
      }
    },
  };
}

async function withTerminalServer(fn) {
  const { spawnProcess, cleanup } = createFakeTtydSpawner();
  const app = createTerminalApp({
    bashBin: '/bin/bash',
    demoUser: { uid: '1000', gid: '100' },
    spawnProcess,
    terminalClientCss: '/* terminal css */',
    terminalClientJs: '/* terminal js */',
    terminalPublicUrl: 'https://localhost:9443',
    ttydBin: '/bin/ttyd',
  });
  const server = http.createServer(app.handleRequest);

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise(resolve => server.close(resolve));
    cleanup();
  }
}

function extractBackendToken(html) {
  const match = html.match(/\/session\/([^/]+)\/token/);
  assert.ok(match, 'expected terminal HTML to include a backend token URL');
  return match[1];
}

test('/terminal creates a fresh hidden backend token on each visit', async () => {
  await withTerminalServer(async baseUrl => {
    const first = await fetch(`${baseUrl}/terminal`);
    const firstHtml = await first.text();
    const firstToken = extractBackendToken(firstHtml);

    const second = await fetch(`${baseUrl}/terminal`);
    const secondHtml = await second.text();
    const secondToken = extractBackendToken(secondHtml);

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.notEqual(firstToken, secondToken);
    assert.match(firstHtml, /window\.OLC_TERMINAL_CONFIG/);
    assert.match(firstHtml, /https:\/\/localhost:9443\/session\/[^/]+\/token/);
    assert.match(firstHtml, /https:\/\/localhost:9443\/session\/[^/]+\/close/);
    assert.match(firstHtml, /https:\/\/localhost:9443\/session\/[^/]+\/ws/);
    assert.match(firstHtml, /https:\/\/localhost:9443\/assets\/terminal\.css/);
    assert.match(firstHtml, /https:\/\/localhost:9443\/assets\/terminal\.js/);

    await fetch(`${baseUrl}/session/${firstToken}/close`, { method: 'POST' });
    await fetch(`${baseUrl}/session/${secondToken}/close`, { method: 'POST' });
  });
});

test('terminal assets are served by the stable terminal app', async () => {
  await withTerminalServer(async baseUrl => {
    const css = await fetch(`${baseUrl}/assets/terminal.css`);
    const js = await fetch(`${baseUrl}/assets/terminal.js`);

    assert.equal(css.status, 200);
    assert.equal(await css.text(), '/* terminal css */');
    assert.equal(js.status, 200);
    assert.equal(await js.text(), '/* terminal js */');
  });
});

test('terminal backend accepts localhost CORS requests from the UI origin', async () => {
  await withTerminalServer(async baseUrl => {
    const page = await fetch(`${baseUrl}/terminal`);
    const token = extractBackendToken(await page.text());

    const tokenResponse = await fetch(`${baseUrl}/session/${token}/token`, {
      headers: { origin: 'https://localhost' },
    });
    assert.equal(tokenResponse.headers.get('access-control-allow-origin'), 'https://localhost');

    const preflight = await fetch(`${baseUrl}/session/${token}/close`, {
      method: 'OPTIONS',
      headers: {
        origin: 'https://localhost',
        'access-control-request-method': 'POST',
      },
    });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('access-control-allow-origin'), 'https://localhost');
    assert.match(preflight.headers.get('access-control-allow-methods'), /POST/);

    const closeResponse = await fetch(`${baseUrl}/session/${token}/close`, {
      method: 'POST',
      headers: { origin: 'https://localhost' },
    });
    assert.equal(closeResponse.status, 204);
    assert.equal(closeResponse.headers.get('access-control-allow-origin'), 'https://localhost');
  });
});

test('terminal token endpoint reports a recent backend exit reason', async () => {
  const spawner = createFakeTtydSpawner();
  const app = createTerminalApp({
    bashBin: '/bin/bash',
    demoUser: { uid: '1000', gid: '100' },
    spawnProcess: spawner.spawnProcess,
    terminalClientCss: '/* terminal css */',
    terminalClientJs: '/* terminal js */',
    terminalPublicUrl: 'https://localhost:9443',
    ttydBin: '/bin/ttyd',
  });
  const server = http.createServer(app.handleRequest);

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const page = await fetch(`${baseUrl}/terminal`);
    const token = extractBackendToken(await page.text());
    const child = spawner.children.at(-1);

    child.stderr.emit('data', Buffer.from('No space left on device\n'));
    child.emit('exit', 1, null);

    const response = await fetch(`${baseUrl}/session/${token}/token`);
    const body = await response.json();

    assert.equal(response.status, 410);
    assert.match(body.error, /terminal backend exited unexpectedly/i);
    assert.match(body.error, /exit code 1/);
    assert.match(body.error, /No space left on device/);
  } finally {
    await new Promise(resolve => server.close(resolve));
    spawner.cleanup();
  }
});
