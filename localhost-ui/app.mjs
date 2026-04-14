import http from 'node:http';
import net from 'node:net';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { URL } from 'node:url';
import { rootHtml } from './system-page.mjs';

const fallbackTerminalTitle = 'ol-c terminal';
const backendStartupTimeoutMs = 30_000;
const reconnectGraceTimeoutMs = 60_000;
const commandPaths = new Map([
  [ '/api/system/network', 'network' ],
  [ '/api/system/volume', 'volume' ],
  [ '/api/system/brightness', 'brightness' ],
  [ '/api/system/appearance', 'appearance' ],
  [ '/api/system/bluetooth', 'bluetooth' ],
]);

function setNoStore(res) {
  res.setHeader('cache-control', 'no-store');
}

function writeJson(res, statusCode, payload, headers = {}) {
  setNoStore(res);
  res.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    ...headers,
  });
  res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', chunk => {
      body += chunk;
      if (body.length > 65_536) {
        const error = new Error('request body is too large');
        error.statusCode = 413;
        reject(error);
        req.destroy();
      }
    });
    req.on('error', reject);
    req.on('end', () => {
      if (!body.trim()) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(body));
      } catch {
        const error = new Error('request body must be valid JSON');
        error.statusCode = 400;
        reject(error);
      }
    });
  });
}

function sendSse(res, event, payload) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function proxyErrorHtml(message) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${fallbackTerminalTitle}</title>
    <style>
      :root {
        color-scheme: dark;
        font-family: sans-serif;
        background: #11130f;
        color: #f8fafc;
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
      }

      main {
        width: min(34rem, calc(100vw - 3rem));
      }

      h1, p {
        margin: 0;
      }

      p {
        margin-top: 0.75rem;
        line-height: 1.5;
        color: #cbd5e1;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>Terminal unavailable</h1>
      <p>${message}</p>
    </main>
  </body>
</html>`;
}

function terminalHtml(token) {
  const backendBasePath = `/terminal/backend/${token}`;

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${fallbackTerminalTitle}</title>
    <link rel="stylesheet" href="/terminal/assets/terminal.css" />
  </head>
  <body>
    <div id="app">
      <div id="terminal-status" class="terminal-status" data-visible="false"></div>
      <div id="terminal"></div>
    </div>
    <script>
      window.OLC_TERMINAL_CONFIG = {
        closeUrl: ${JSON.stringify(`${backendBasePath}/close`)},
        tokenUrl: ${JSON.stringify(`${backendBasePath}/token`)},
        wsPath: ${JSON.stringify(`${backendBasePath}/ws`)},
      };
    </script>
    <script src="/terminal/assets/terminal.js"></script>
  </body>
</html>`;
}

function cancelTimer(timer) {
  if (timer) {
    clearTimeout(timer);
  }
  return null;
}

export function createOlcApp(options) {
  const {
    bashBin,
    demoUser,
    systemControls,
    terminalClientCss,
    terminalClientJs,
    ttydBin,
  } = options;
  const terminalBackends = new Map();

  function terminateBackend(token) {
    const backend = terminalBackends.get(token);

    if (!backend) {
      return;
    }

    backend.startupTimer = cancelTimer(backend.startupTimer);
    backend.reconnectGraceTimer = cancelTimer(backend.reconnectGraceTimer);
    terminalBackends.delete(token);

    if (!backend.child.killed) {
      backend.child.kill('SIGTERM');
    }
  }

  function scheduleStartupTimeout(token) {
    return setTimeout(() => {
      terminateBackend(token);
    }, backendStartupTimeoutMs);
  }

  function scheduleReconnectGraceTimeout(token) {
    return setTimeout(() => {
      terminateBackend(token);
    }, reconnectGraceTimeoutMs);
  }

  async function reservePort() {
    return await new Promise((resolve, reject) => {
      const socket = net.createServer();

      socket.on('error', reject);
      socket.listen(0, '127.0.0.1', () => {
        const address = socket.address();
        const port = typeof address === 'object' && address ? address.port : null;

        socket.close(error => {
          if (error) {
            reject(error);
            return;
          }

          if (!port) {
            reject(new Error('Unable to reserve a local port for ttyd'));
            return;
          }

          resolve(port);
        });
      });
    });
  }

  async function waitForBackend(port, basePath) {
    let lastError = null;

    for (let attempt = 0; attempt < 40; attempt += 1) {
      try {
        await new Promise((resolve, reject) => {
          const probe = http.request({
            host: '127.0.0.1',
            port,
            method: 'GET',
            path: `${basePath}/`,
          }, response => {
            response.resume();
            resolve();
          });

          probe.on('error', reject);
          probe.end();
        });
        return;
      } catch (error) {
        lastError = error;
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }

    throw lastError ?? new Error('Timed out waiting for ttyd');
  }

  async function spawnTerminalBackend() {
    const token = randomUUID();
    const port = await reservePort();
    const basePath = `/terminal/backend/${token}`;
    const args = [
      '--port', String(port),
      '--interface', 'lo',
      '--writable',
      '--base-path', basePath,
      '--uid', demoUser.uid,
      '--gid', demoUser.gid,
      '--cwd', '/home/demo',
      bashBin,
      '--login',
    ];
    const child = spawn(ttydBin, args, {
      stdio: [ 'ignore', 'pipe', 'pipe' ],
    });

    child.stdout.on('data', chunk => {
      process.stdout.write(`[ol-c-ui][ttyd:${token}] ${chunk}`);
    });
    child.stderr.on('data', chunk => {
      process.stderr.write(`[ol-c-ui][ttyd:${token}] ${chunk}`);
    });
    child.on('exit', () => {
      const current = terminalBackends.get(token);

      if (!current || current.child !== child) {
        return;
      }

      current.startupTimer = cancelTimer(current.startupTimer);
      current.reconnectGraceTimer = cancelTimer(current.reconnectGraceTimer);
      terminalBackends.delete(token);
    });

    terminalBackends.set(token, {
      activeSockets: 0,
      child,
      port,
      reconnectGraceTimer: null,
      startupTimer: scheduleStartupTimeout(token),
    });

    try {
      await waitForBackend(port, basePath);
    } catch (error) {
      terminateBackend(token);
      throw error;
    }

    return token;
  }

  function getBackendToken(reqUrl) {
    const pathname = new URL(reqUrl, 'https://localhost').pathname;
    const match = pathname.match(/^\/terminal\/backend\/([^/]+)(?:\/|$)/);
    return match ? match[1] : null;
  }

  function markBackendActive(token) {
    const backend = terminalBackends.get(token);

    if (!backend) {
      return null;
    }

    backend.startupTimer = cancelTimer(backend.startupTimer);
    backend.reconnectGraceTimer = cancelTimer(backend.reconnectGraceTimer);
    return backend;
  }

  function recordSocketOpen(token) {
    const backend = terminalBackends.get(token);

    if (!backend) {
      return;
    }

    backend.activeSockets += 1;
  }

  function recordSocketClose(token) {
    const backend = terminalBackends.get(token);

    if (!backend) {
      return;
    }

    backend.activeSockets = Math.max(backend.activeSockets - 1, 0);
    if (backend.activeSockets === 0) {
      backend.reconnectGraceTimer = cancelTimer(backend.reconnectGraceTimer);
      backend.reconnectGraceTimer = scheduleReconnectGraceTimeout(token);
    }
  }

  function closeTerminalBackend(req, res, token) {
    if (req.method !== 'POST') {
      setNoStore(res);
      res.writeHead(405, {
        'allow': 'POST',
        'content-type': 'application/json; charset=utf-8',
      });
      res.end(JSON.stringify({ ok: false, error: 'method not allowed' }));
      return;
    }

    if (token) {
      terminateBackend(token);
    }

    setNoStore(res);
    res.writeHead(204);
    res.end();
  }

  function proxyRequest(req, res, token) {
    const backend = markBackendActive(token);

    if (!backend) {
      setNoStore(res);
      res.writeHead(404, { 'content-type': 'text/html; charset=utf-8' });
      res.end(proxyErrorHtml('This terminal session is no longer available.'));
      return;
    }

    const proxy = http.request({
      host: '127.0.0.1',
      port: backend.port,
      method: req.method,
      path: req.url,
      headers: {
        ...req.headers,
        host: `127.0.0.1:${backend.port}`,
      },
    }, proxyResponse => {
      setNoStore(res);
      res.writeHead(proxyResponse.statusCode ?? 502, proxyResponse.headers);
      proxyResponse.pipe(res);
    });

    proxy.on('error', error => {
      setNoStore(res);
      res.writeHead(502, { 'content-type': 'text/html; charset=utf-8' });
      res.end(proxyErrorHtml(`Unable to reach terminal backend: ${error.message}`));
    });

    req.pipe(proxy);
  }

  async function handleSystemEvents(req, res) {
    if (req.method !== 'GET') {
      writeJson(res, 405, { ok: false, error: 'method not allowed' }, { allow: 'GET' });
      return;
    }

    setNoStore(res);
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    });
    res.write(': connected\n\n');

    const unsubscribe = systemControls.subscribe(status => {
      sendSse(res, 'status', status);
    });

    req.on('close', unsubscribe);

    try {
      const status = await systemControls.getStatus();
      sendSse(res, 'status', status);
    } catch (error) {
      sendSse(res, 'error', { error: error.message });
    }
  }

  async function handleSystemCommand(req, res, area) {
    if (req.method !== 'POST') {
      writeJson(res, 405, { ok: false, error: 'method not allowed' }, { allow: 'POST' });
      return;
    }

    try {
      const body = await readJsonBody(req);
      const status = await systemControls.command(area, body);
      writeJson(res, 200, status);
    } catch (error) {
      writeJson(res, error.statusCode ?? 500, {
        ok: false,
        error: error.message,
      });
    }
  }

  async function handleRequest(req, res) {
    const reqUrl = new URL(req.url, 'https://localhost');

    if (reqUrl.pathname === '/') {
      setNoStore(res);
      res.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
      });
      res.end(rootHtml());
      return;
    }

    if (reqUrl.pathname === '/api/system/events') {
      await handleSystemEvents(req, res);
      return;
    }

    if (commandPaths.has(reqUrl.pathname)) {
      await handleSystemCommand(req, res, commandPaths.get(reqUrl.pathname));
      return;
    }

    if (reqUrl.pathname === '/terminal/assets/terminal.css') {
      setNoStore(res);
      res.writeHead(200, {
        'content-type': 'text/css; charset=utf-8',
      });
      res.end(terminalClientCss);
      return;
    }

    if (reqUrl.pathname === '/terminal/assets/terminal.js') {
      setNoStore(res);
      res.writeHead(200, {
        'content-type': 'text/javascript; charset=utf-8',
      });
      res.end(terminalClientJs);
      return;
    }

    if (reqUrl.pathname === '/terminal') {
      try {
        const token = await spawnTerminalBackend();

        setNoStore(res);
        res.writeHead(200, {
          'content-type': 'text/html; charset=utf-8',
        });
        res.end(terminalHtml(token));
      } catch (error) {
        setNoStore(res);
        res.writeHead(502, {
          'content-type': 'text/html; charset=utf-8',
        });
        res.end(proxyErrorHtml(`Unable to start a fresh terminal: ${error.message}`));
      }
      return;
    }

    if (reqUrl.pathname.match(/^\/terminal\/backend\/[^/]+\/close$/)) {
      closeTerminalBackend(req, res, getBackendToken(req.url));
      return;
    }

    if (reqUrl.pathname.startsWith('/terminal/backend/')) {
      proxyRequest(req, res, getBackendToken(req.url));
      return;
    }

    setNoStore(res);
    res.writeHead(404, {
      'content-type': 'text/html; charset=utf-8',
    });
    res.end(proxyErrorHtml('The requested ol-c page was not found.'));
  }

  function handleUpgrade(req, socket, head) {
    const token = getBackendToken(req.url);

    if (!token) {
      socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }

    const backend = markBackendActive(token);

    if (!backend) {
      socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }

    const proxy = http.request({
      host: '127.0.0.1',
      port: backend.port,
      path: req.url,
      headers: {
        ...req.headers,
        host: `127.0.0.1:${backend.port}`,
      },
    });

    proxy.on('upgrade', (proxyResponse, proxySocket, proxyHead) => {
      let closed = false;
      const handleClose = () => {
        if (closed) {
          return;
        }
        closed = true;
        recordSocketClose(token);
      };
      const statusCode = proxyResponse.statusCode ?? 101;
      const statusMessage = proxyResponse.statusMessage ?? 'Switching Protocols';
      const headerLines = Object.entries(proxyResponse.headers)
        .flatMap(([name, value]) => {
          if (Array.isArray(value)) {
            return value.map(item => `${name}: ${item}`);
          }

          if (value === undefined) {
            return [];
          }

          return [ `${name}: ${value}` ];
        })
        .join('\r\n');

      socket.write(`HTTP/1.1 ${statusCode} ${statusMessage}\r\n${headerLines}\r\n\r\n`);

      if (proxyHead.length > 0) {
        socket.write(proxyHead);
      }
      if (head.length > 0) {
        proxySocket.write(head);
      }

      recordSocketOpen(token);
      proxySocket.pipe(socket);
      socket.pipe(proxySocket);

      proxySocket.on('close', () => {
        handleClose();
        proxy.destroy();
      });
      socket.on('close', () => {
        handleClose();
        proxySocket.destroy();
      });
    });

    proxy.on('error', () => {
      socket.write('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n');
      socket.destroy();
    });
    proxy.end();
  }

  return {
    handleRequest,
    handleUpgrade,
  };
}
