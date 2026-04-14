import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import http from 'node:http';
import { createServer } from 'node:https';
import net from 'node:net';
import { URL } from 'node:url';

function requireEnv(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

const marker = 'OLC_LOCALHOST_UI_OK';
const ttydBin = requireEnv('OLC_TTYD');
const bashBin = requireEnv('OLC_BASH');
const fallbackTerminalTitle = 'OL-C Terminal';
const backendStartupTimeoutMs = 30_000;
const reconnectGraceTimeoutMs = 60_000;
const tlsKeyPath = requireEnv('OLC_TLS_KEY');
const tlsCertPath = requireEnv('OLC_TLS_CERT');
const terminalClientJsPath = requireEnv('OLC_TERMINAL_CLIENT_JS');
const terminalClientCssPath = requireEnv('OLC_TERMINAL_CLIENT_CSS');
const terminalClientJs = readFileSync(terminalClientJsPath, 'utf8');
const terminalClientCss = readFileSync(terminalClientCssPath, 'utf8');
const demoUser = (() => {
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
})();
const terminalBackends = new Map();

function rootHtml() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>OL-C</title>
    <style>
      :root {
        color-scheme: dark;
        font-family: sans-serif;
        background: #09111f;
        color: #f4f7fb;
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background:
          radial-gradient(circle at top, rgba(94, 234, 212, 0.18), transparent 30%),
          linear-gradient(180deg, #0b1220, #050814);
      }

      main {
        width: min(44rem, calc(100vw - 3rem));
        padding: 2rem;
        border: 1px solid rgba(255, 255, 255, 0.1);
        border-radius: 1.25rem;
        background: rgba(9, 17, 31, 0.82);
        box-shadow: 0 2rem 5rem rgba(0, 0, 0, 0.35);
      }

      h1, p {
        margin: 0;
      }

      p {
        margin-top: 1rem;
        line-height: 1.5;
        color: #c7d2e3;
      }

      code {
        font-family: monospace;
        color: #5eead4;
      }

      a {
        color: #93c5fd;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>OL-C control surface</h1>
      <p>Firefox now boots to <code>https://localhost</code>, served inside the guest by a Node.js process on port <code>443</code>.</p>
      <p>The next proof surface is <a href="/terminal" onclick="window.open('/terminal', '_blank'); return false;"><code>/terminal</code></a>, which opens a fresh in-browser terminal session each time it is loaded.</p>
      <p id="proof">${marker}</p>
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
        background: #0b1220;
        color: #f8fafc;
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background:
          radial-gradient(circle at top, rgba(248, 113, 113, 0.15), transparent 32%),
          linear-gradient(180deg, #0b1220, #050814);
      }

      main {
        width: min(34rem, calc(100vw - 3rem));
        padding: 2rem;
        border-radius: 1rem;
        border: 1px solid rgba(248, 113, 113, 0.25);
        background: rgba(15, 23, 42, 0.92);
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

function setNoStore(res) {
  res.setHeader('cache-control', 'no-store');
}

function cancelTimer(timer) {
  if (timer) {
    clearTimeout(timer);
  }
  return null;
}

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

  return backend;
}

function recordSocketOpen(token) {
  const backend = terminalBackends.get(token);

  if (!backend) {
    return null;
  }

  backend.startupTimer = cancelTimer(backend.startupTimer);
  backend.reconnectGraceTimer = cancelTimer(backend.reconnectGraceTimer);
  backend.activeSockets += 1;
  return backend;
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

function proxyUpgrade(req, socket, head, token) {
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

const server = createServer({
  key: readFileSync(tlsKeyPath),
  cert: readFileSync(tlsCertPath),
}, async (req, res) => {
  const reqUrl = new URL(req.url, 'https://localhost');

  if (reqUrl.pathname === '/') {
    setNoStore(res);
    res.writeHead(200, {
      'content-type': 'text/html; charset=utf-8',
    });
    res.end(rootHtml());
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
  res.end(proxyErrorHtml('The requested OL-C page was not found.'));
});

server.on('upgrade', (req, socket, head) => {
  const token = getBackendToken(req.url);

  if (!token) {
    socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
    socket.destroy();
    return;
  }

  proxyUpgrade(req, socket, head, token);
});

server.listen(443, '127.0.0.1', () => {
  console.log('OLC_UI_SERVER_OK https://localhost');
});
