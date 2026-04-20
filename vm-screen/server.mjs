import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, normalize, resolve, sep } from 'node:path';

const listenHost = process.env.OLC_VM_SCREEN_HOST || '127.0.0.1';
const listenPort = Number.parseInt(process.env.OLC_VM_SCREEN_PORT || '0', 10);
const vncHost = process.env.OLC_VM_SCREEN_VNC_HOST || '127.0.0.1';
const vncWebsocketPort = process.env.OLC_VM_SCREEN_VNC_WS_PORT || '';
const noVncDir = process.env.OLC_NOVNC_DIR || '';

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function contentType(pathname) {
  switch (extname(pathname)) {
    case '.css':
      return 'text/css; charset=utf-8';
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
    case '.mjs':
      return 'text/javascript; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.png':
      return 'image/png';
    case '.wasm':
      return 'application/wasm';
    default:
      return 'application/octet-stream';
  }
}

function isLocalhostTarget(host) {
  return host === '127.0.0.1' || host === 'localhost' || host === '::1';
}

function safeNovncPath(pathname) {
  const relative = pathname.replace(/^\/novnc\/?/, '');
  const normalized = normalize(relative);
  if (normalized.startsWith('..') || normalized.includes(`${sep}..${sep}`)) {
    return null;
  }

  const root = resolve(noVncDir);
  const resolved = resolve(root, normalized);
  if (resolved !== root && !resolved.startsWith(`${root}${sep}`)) {
    return null;
  }

  return resolved;
}

function send(res, status, body, type = 'text/plain; charset=utf-8') {
  res.writeHead(status, {
    'content-type': type,
    'cache-control': 'no-store',
  });
  res.end(body);
}

function indexHtml() {
  const config = JSON.stringify({
    host: vncHost,
    port: Number.parseInt(vncWebsocketPort, 10),
  });

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ol-c VM</title>
  <style>
    html, body {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #101418;
      color: #f4f7f8;
      font-family: system-ui, sans-serif;
    }

    #screen {
      width: 100vw;
      height: 100vh;
    }

    #status {
      position: fixed;
      top: 8px;
      left: 8px;
      z-index: 2;
      padding: 5px 7px;
      border-radius: 4px;
      background: rgba(16, 20, 24, 0.78);
      color: #f4f7f8;
      font-size: 13px;
    }

    #clipboard-hint {
      position: fixed;
      top: 8px;
      right: 8px;
      z-index: 2;
      padding: 5px 6px;
      border-radius: 4px;
      background: rgba(16, 20, 24, 0.78);
      color: #f4f7f8;
      font-size: 13px;
    }
  </style>
</head>
<body>
  <div id="screen"></div>
  <div id="status">Connecting</div>
  <div id="clipboard-hint">Clipboard ready</div>
  <script>window.OLC_VM_SCREEN = ${config};</script>
  <script type="module" src="/screen.js"></script>
</body>
</html>`;
}

function screenJs() {
  return `import RFB from '/novnc/core/rfb.js';

const screen = document.getElementById('screen');
const status = document.getElementById('status');
const clipboardHint = document.getElementById('clipboard-hint');
const config = window.OLC_VM_SCREEN;
const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
const url = protocol + '//' + config.host + ':' + config.port + '/';
let latestVmClipboardText = '';
let clipboardHintTimer = 0;

function setStatus(message) {
  status.textContent = message;
}

function setClipboardHint(message) {
  clipboardHint.textContent = message;
  window.clearTimeout(clipboardHintTimer);
  clipboardHintTimer = window.setTimeout(() => {
    clipboardHint.textContent = 'Clipboard ready';
  }, 3500);
}

async function copyLatestVmClipboardToHost() {
  if (latestVmClipboardText.length === 0) {
    setClipboardHint('No VM clipboard text');
    return false;
  }

  if (!navigator.clipboard?.writeText) {
    setClipboardHint('Host clipboard unavailable');
    return false;
  }

  try {
    await navigator.clipboard.writeText(latestVmClipboardText);
    setClipboardHint('Copied from VM');
    return true;
  } catch {
    setClipboardHint('Press Ctrl+Shift+C to copy from VM');
    return false;
  }
}

const rfb = new RFB(screen, url, { credentials: {} });
rfb.scaleViewport = true;
rfb.resizeSession = false;
rfb.focusOnClick = true;

rfb.addEventListener('connect', () => setStatus('Connected'));
rfb.addEventListener('disconnect', event => {
  setStatus(event.detail.clean ? 'Disconnected' : 'Disconnected unexpectedly');
});
rfb.addEventListener('credentialsrequired', () => setStatus('Credentials required'));
rfb.addEventListener('securityfailure', () => setStatus('Security failure'));
rfb.addEventListener('clipboard', event => {
  latestVmClipboardText = event.detail?.text || '';
  if (latestVmClipboardText.length === 0) {
    setClipboardHint('VM clipboard empty');
    return;
  }

  void copyLatestVmClipboardToHost();
});

window.addEventListener('paste', event => {
  const text = event.clipboardData?.getData('text/plain') || '';
  if (text.length === 0) {
    return;
  }

  event.preventDefault();
  rfb.clipboardPasteFrom(text);
  setClipboardHint('Pasted to VM');
  rfb.focus();
});

window.addEventListener('keydown', event => {
  if (event.ctrlKey && event.shiftKey && event.code === 'KeyC') {
    event.preventDefault();
    void copyLatestVmClipboardToHost();
  }
});

window.addEventListener('load', () => {
  screen.focus();
});
`;
}

if (!Number.isInteger(listenPort) || listenPort < 0 || listenPort > 65535) {
  fail('OLC_VM_SCREEN_PORT must be a TCP port number');
}

if (!Number.isInteger(Number.parseInt(vncWebsocketPort, 10))) {
  fail('OLC_VM_SCREEN_VNC_WS_PORT must be set to a TCP port number');
}

if (!isLocalhostTarget(vncHost) && process.env.OLC_VM_SCREEN_ALLOW_REMOTE_VNC !== '1') {
  fail('refusing to serve a non-local VNC target without OLC_VM_SCREEN_ALLOW_REMOTE_VNC=1');
}

if (!noVncDir || !existsSync(noVncDir) || !statSync(noVncDir).isDirectory()) {
  fail('OLC_NOVNC_DIR must point to a noVNC asset directory');
}

const server = createServer((req, res) => {
  const url = new URL(req.url || '/', `http://${listenHost}`);

  if (url.pathname === '/') {
    send(res, 200, indexHtml(), 'text/html; charset=utf-8');
    return;
  }

  if (url.pathname === '/screen.js') {
    send(res, 200, screenJs(), 'text/javascript; charset=utf-8');
    return;
  }

  if (url.pathname.startsWith('/novnc/')) {
    const path = safeNovncPath(url.pathname);
    if (!path || !existsSync(path) || !statSync(path).isFile()) {
      send(res, 404, 'not found');
      return;
    }

    res.writeHead(200, {
      'content-type': contentType(path),
      'cache-control': 'no-store',
    });
    createReadStream(path).pipe(res);
    return;
  }

  send(res, 404, 'not found');
});

server.listen(listenPort, listenHost, () => {
  const address = server.address();
  console.log(`OLC_VM_SCREEN_URL http://${listenHost}:${address.port}/`);
});

function shutdown() {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1000).unref();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
