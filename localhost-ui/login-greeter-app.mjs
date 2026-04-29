import { loginGreeterHtml } from './login-greeter-page.mjs';
import { createLoginAccountProvider } from './login-accounts.mjs';

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
      if (body.length > 32_768) {
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

function errorHtml(message) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Unavailable</title>
  </head>
  <body>
    <main>${message}</main>
  </body>
</html>`;
}

export function createLoginGreeterApp(options) {
  const client = options.client;
  const listLoginAccounts = options.listLoginAccounts ?? createLoginAccountProvider(options.accounts);
  const onSessionStarted = options.onSessionStarted ?? (() => {});

  if (!client) {
    throw new Error('greeter client is required');
  }

  async function handlePost(req, res, action) {
    try {
      const body = await readJsonBody(req);
      const result = await action(body);
      writeJson(res, 200, result);
      if (result?.status === 'starting') {
        res.on('finish', () => {
          onSessionStarted(result);
        });
      }
    } catch (error) {
      writeJson(res, error.statusCode ?? 500, {
        ok: false,
        error: error.message,
      });
    }
  }

  async function handleRequest(req, res) {
    const pathname = new URL(req.url, 'https://localhost').pathname;

    if (pathname === '/' || pathname === '/login') {
      setNoStore(res);
      res.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
      });
      res.end(loginGreeterHtml());
      return;
    }

    if (pathname === '/api/login/users') {
      if (req.method !== 'GET') {
        writeJson(res, 405, { ok: false, error: 'method not allowed' }, { allow: 'GET' });
        return;
      }

      try {
        writeJson(res, 200, {
          ok: true,
          users: await listLoginAccounts(),
        });
      } catch {
        writeJson(res, 200, {
          ok: true,
          users: [],
        });
      }
      return;
    }

    if (pathname === '/api/login') {
      if (req.method !== 'POST') {
        writeJson(res, 405, { ok: false, error: 'method not allowed' }, { allow: 'POST' });
        return;
      }

      await handlePost(req, res, body => client.authenticate(body));
      return;
    }

    if (pathname === '/api/respond') {
      if (req.method !== 'POST') {
        writeJson(res, 405, { ok: false, error: 'method not allowed' }, { allow: 'POST' });
        return;
      }

      await handlePost(req, res, body => client.respond(body));
      return;
    }

    if (pathname === '/api/cancel') {
      if (req.method !== 'POST') {
        writeJson(res, 405, { ok: false, error: 'method not allowed' }, { allow: 'POST' });
        return;
      }

      await handlePost(req, res, () => client.cancel());
      return;
    }

    setNoStore(res);
    res.writeHead(404, {
      'content-type': 'text/html; charset=utf-8',
    });
    res.end(errorHtml('The requested login page was not found.'));
  }

  return { handleRequest };
}
