import http from 'node:http';
import https from 'node:https';
import { readFileSync } from 'node:fs';
import { URL } from 'node:url';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { editorHtml, handleEditorApi } from './editor-page.mjs';
import { rootHtml } from './system-page.mjs';

const moduleDir = dirname(fileURLToPath(import.meta.url));
const editorClientJs = readFileSync(join(moduleDir, 'editor-client.bundle.js'), 'utf8');

const commandPaths = new Map([
  [ '/api/system/network', 'network' ],
  [ '/api/system/volume', 'volume' ],
  [ '/api/system/brightness', 'brightness' ],
  [ '/api/system/appearance', 'appearance' ],
  [ '/api/system/terminal', 'terminal' ],
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
    <title>ol-c terminal</title>
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

function parseUpstream(url) {
  const parsed = new URL(url);
  return {
    host: parsed.hostname,
    port: Number(parsed.port || (parsed.protocol === 'https:' ? 443 : 80)),
    rejectUnauthorized: parsed.protocol === 'https:' ? false : undefined,
    request: parsed.protocol === 'https:' ? https.request : http.request,
  };
}

function stripHopByHopHeaders(headers) {
  const nextHeaders = { ...headers };
  delete nextHeaders.connection;
  delete nextHeaders['content-length'];
  delete nextHeaders.host;
  delete nextHeaders.upgrade;
  return nextHeaders;
}

export function createOlcApp(options) {
  const {
    systemControls,
    terminalUpstreamUrl = 'https://127.0.0.1:9443',
  } = options;
  const terminalUpstream = parseUpstream(terminalUpstreamUrl);

  function proxyTerminalRequest(req, res) {
    const proxy = terminalUpstream.request({
      host: terminalUpstream.host,
      port: terminalUpstream.port,
      method: req.method,
      path: req.url,
      rejectUnauthorized: terminalUpstream.rejectUnauthorized,
      headers: {
        ...stripHopByHopHeaders(req.headers),
        host: `${terminalUpstream.host}:${terminalUpstream.port}`,
      },
    }, proxyResponse => {
      setNoStore(res);
      res.writeHead(proxyResponse.statusCode ?? 502, proxyResponse.headers);
      proxyResponse.pipe(res);
    });

    proxy.on('error', error => {
      setNoStore(res);
      res.writeHead(503, { 'content-type': 'text/html; charset=utf-8' });
      res.end(proxyErrorHtml(`Terminal service is unavailable: ${error.message}`));
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

    if (reqUrl.pathname.startsWith('/terminal')) {
      proxyTerminalRequest(req, res);
      return;
    }

    if (reqUrl.pathname === '/edit') {
      setNoStore(res);
      res.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
      });
      res.end(editorHtml());
      return;
    }

    if (reqUrl.pathname === '/edit/assets/editor.js') {
      setNoStore(res);
      res.writeHead(200, {
        'content-type': 'text/javascript; charset=utf-8',
      });
      res.end(editorClientJs);
      return;
    }

    if (reqUrl.pathname.startsWith('/api/edit/')) {
      await handleEditorApi(req, res, reqUrl);
      return;
    }

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

    setNoStore(res);
    res.writeHead(404, {
      'content-type': 'text/html; charset=utf-8',
    });
    res.end(proxyErrorHtml('The requested ol-c page was not found.'));
  }

  function handleUpgrade(req, socket) {
    socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
    socket.destroy();
  }

  return {
    handleRequest,
    handleUpgrade,
  };
}
