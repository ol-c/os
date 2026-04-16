import http from 'node:http';
import net from 'node:net';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { URL } from 'node:url';

const fallbackTerminalTitle = 'ol-c terminal';
const backendStartupTimeoutMs = 30_000;
const reconnectGraceTimeoutMs = 60_000;
const allowedTerminalOrigins = new Set([
  'https://localhost',
  'https://127.0.0.1',
]);

function setNoStore(res) {
  res.setHeader('cache-control', 'no-store');
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

function pathForBackend(token) {
  return `/session/${token}`;
}

function terminalHtml(token, terminalPublicUrl = '') {
  const backendBasePath = pathForBackend(token);
  const publicPrefix = terminalPublicUrl.replace(/\/$/, '');

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${fallbackTerminalTitle}</title>
    <link rel="stylesheet" href="${publicPrefix}/assets/terminal.css" />
  </head>
  <body>
    <div id="app">
      <div id="terminal-status" class="terminal-status" data-visible="false"></div>
      <div id="terminal"></div>
    </div>
    <script>
      window.OLC_TERMINAL_CONFIG = {
        closeUrl: ${JSON.stringify(`${publicPrefix}${backendBasePath}/close`)},
        tokenUrl: ${JSON.stringify(`${publicPrefix}${backendBasePath}/token`)},
        wsUrl: ${JSON.stringify(`${publicPrefix}${backendBasePath}/ws`)},
      };
    </script>
    <script src="${publicPrefix}/assets/terminal.js"></script>
  </body>
</html>`;
}

function cancelTimer(timer) {
  if (timer) {
    clearTimeout(timer);
  }
  return null;
}

export function createTerminalApp(options) {
  const {
    bashBin,
    demoUser,
    spawnProcess = spawn,
    terminalClientCss,
    terminalClientJs,
    terminalPublicUrl = '',
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
    const basePath = pathForBackend(token);
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
    const child = spawnProcess(ttydBin, args, {
      stdio: [ 'ignore', 'pipe', 'pipe' ],
    });

    child.stdout.on('data', chunk => {
      process.stdout.write(`[ol-c-terminal][ttyd:${token}] ${chunk}`);
    });
    child.stderr.on('data', chunk => {
      process.stderr.write(`[ol-c-terminal][ttyd:${token}] ${chunk}`);
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
    const match = pathname.match(/^\/session\/([^/]+)(?:\/|$)/);
    return match ? match[1] : null;
  }

  function applyCors(req, res) {
    const origin = req.headers.origin;

    if (!allowedTerminalOrigins.has(origin)) {
      return;
    }

    res.setHeader('access-control-allow-origin', origin);
    res.setHeader('vary', 'Origin');
    res.setHeader('access-control-allow-methods', 'GET, POST, OPTIONS');
    res.setHeader('access-control-allow-headers', 'content-type');
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
    applyCors(req, res);

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

  async function handleRequest(req, res) {
    const reqUrl = new URL(req.url, 'https://localhost');
    applyCors(req, res);

    if (req.method === 'OPTIONS') {
      setNoStore(res);
      res.writeHead(204);
      res.end();
      return;
    }

    if (reqUrl.pathname === '/assets/terminal.css') {
      setNoStore(res);
      res.writeHead(200, {
        'content-type': 'text/css; charset=utf-8',
      });
      res.end(terminalClientCss);
      return;
    }

    if (reqUrl.pathname === '/assets/terminal.js') {
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
        res.end(terminalHtml(token, terminalPublicUrl));
      } catch (error) {
        setNoStore(res);
        res.writeHead(502, {
          'content-type': 'text/html; charset=utf-8',
        });
        res.end(proxyErrorHtml(`Unable to start a fresh terminal: ${error.message}`));
      }
      return;
    }

    if (reqUrl.pathname.match(/^\/session\/[^/]+\/close$/)) {
      closeTerminalBackend(req, res, getBackendToken(req.url));
      return;
    }

    if (reqUrl.pathname.startsWith('/session/')) {
      proxyRequest(req, res, getBackendToken(req.url));
      return;
    }

    setNoStore(res);
    res.writeHead(404, {
      'content-type': 'text/html; charset=utf-8',
    });
    res.end(proxyErrorHtml('The requested terminal page was not found.'));
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

    proxy.on('response', proxyResponse => {
      const statusCode = proxyResponse.statusCode ?? 502;
      const statusMessage = proxyResponse.statusMessage ?? 'Bad Gateway';
      socket.write(`HTTP/1.1 ${statusCode} ${statusMessage}\r\nConnection: close\r\n\r\n`);
      proxyResponse.resume();
      socket.destroy();
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
