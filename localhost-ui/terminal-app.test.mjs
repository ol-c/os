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
    children.push({ args, child });
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

async function withTerminalServer(fn, options = {}) {
  const { spawnProcess, cleanup: cleanupSpawner, children } = createFakeTtydSpawner();
  const app = createTerminalApp({
    bashBin: '/bin/bash',
    getTerminalUser: options.getTerminalUser || (async () => ({
      uid: '1000',
      gid: '1000',
      home: '/home/alice',
    })),
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
    await fn(`http://127.0.0.1:${port}`, children);
  } finally {
    await new Promise(resolve => server.close(resolve));
    app.cleanup();
    cleanupSpawner();
  }
}

function extractBackendToken(html) {
  const match = html.match(/\/session\/([^/]+)\/token/);
  assert.ok(match, 'expected terminal HTML to include a backend token URL');
  return match[1];
}

test('/terminal creates a fresh hidden backend token on each visit', async () => {
  await withTerminalServer(async (baseUrl, children) => {
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
    assert.equal(children[0].args[children[0].args.indexOf('--cwd') + 1], '/home/alice');
    assert.equal(children[0].args[children[0].args.indexOf('--uid') + 1], '1000');

    await fetch(`${baseUrl}/session/${firstToken}/close`, { method: 'POST' });
    await fetch(`${baseUrl}/session/${secondToken}/close`, { method: 'POST' });
  });
});

test('terminal reports a clear error when no signed-in user session exists', async () => {
  await withTerminalServer(async baseUrl => {
    const response = await fetch(`${baseUrl}/terminal`);
    const html = await response.text();
    assert.equal(response.status, 409);
    assert.match(html, /signed-in user session exists/i);
  }, {
    getTerminalUser: async () => null,
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
