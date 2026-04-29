import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { GreetdClient } from './greetd-client.mjs';
import { createLoginGreeterApp } from './login-greeter-app.mjs';

function encodeMessage(payload) {
  const body = Buffer.from(JSON.stringify(payload), 'utf8');
  const header = Buffer.allocUnsafe(4);
  header.writeUInt32LE(body.length, 0);
  return Buffer.concat([ header, body ]);
}

function decodeMessages(buffer) {
  const messages = [];
  let offset = 0;

  while (buffer.length - offset >= 4) {
    const bodyLength = buffer.readUInt32LE(offset);
    if (buffer.length - offset < 4 + bodyLength) {
      break;
    }

    const body = buffer.subarray(offset + 4, offset + 4 + bodyLength);
    messages.push(JSON.parse(body.toString('utf8')));
    offset += 4 + bodyLength;
  }

  return {
    messages,
    rest: buffer.subarray(offset),
  };
}

async function withFakeGreetd(sessionHandler, fn) {
  const dir = await mkdtemp(join(tmpdir(), 'olc-greetd-'));
  const socketPath = join(dir, 'greetd.sock');
  const seenSessions = [];

  const server = net.createServer(socket => {
    let buffer = Buffer.alloc(0);
    const messages = [];

    socket.on('data', chunk => {
      buffer = Buffer.concat([ buffer, chunk ]);
      const decoded = decodeMessages(buffer);
      buffer = decoded.rest;

      for (const message of decoded.messages) {
        messages.push(message);
        const responses = sessionHandler(message, messages);
        for (const response of responses) {
          socket.write(encodeMessage(response));
        }
        if (responses.some(response => response.type === 'success' && message.type === 'start_session')) {
          seenSessions.push(messages.slice());
        }
      }
    });
  });

  await new Promise(resolve => server.listen(socketPath, resolve));

  try {
    await fn({ socketPath, seenSessions });
  } finally {
    await new Promise(resolve => server.close(resolve));
    await rm(dir, { recursive: true, force: true });
  }
}

async function withGreeterServer(client, fn) {
  const app = createLoginGreeterApp({ client });
  const server = http.createServer(app.handleRequest);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test('greetd client authenticates and starts the configured session command', async () => {
  await withFakeGreetd((message, seen) => {
    if (message.type === 'create_session') {
      return [
        { type: 'auth_message', auth_message_type: 'secret', auth_message: 'Password:' },
      ];
    }
    if (message.type === 'post_auth_message_response') {
      assert.equal(message.response, 'correct horse battery');
      return [ { type: 'success' } ];
    }
    if (message.type === 'start_session') {
      assert.deepEqual(message.cmd, [ '/bin/start-user-session' ]);
      assert.deepEqual(message.env, []);
      return [ { type: 'success' } ];
    }
    throw new Error(`unexpected message: ${JSON.stringify(message)} after ${JSON.stringify(seen)}`);
  }, async ({ socketPath }) => {
    const client = new GreetdClient({
      socketPath,
      sessionCommand: '/bin/start-user-session',
    });
    const result = await client.authenticate({
      username: 'alice',
      password: 'correct horse battery',
    });
    assert.equal(result.status, 'starting');
  });
});

test('greetd client surfaces extra prompts after the initial password', async () => {
  await withFakeGreetd(message => {
    if (message.type === 'create_session') {
      return [
        { type: 'auth_message', auth_message_type: 'secret', auth_message: 'Password:' },
      ];
    }
    if (message.type === 'post_auth_message_response' && message.response === 'correct horse battery') {
      return [
        { type: 'auth_message', auth_message_type: 'visible', auth_message: 'One-time code:' },
      ];
    }
    if (message.type === 'post_auth_message_response' && message.response === '123456') {
      return [ { type: 'success' } ];
    }
    if (message.type === 'start_session') {
      return [ { type: 'success' } ];
    }
    return [];
  }, async ({ socketPath }) => {
    const client = new GreetdClient({
      socketPath,
      sessionCommand: '/bin/start-user-session',
    });
    const prompt = await client.authenticate({
      username: 'alice',
      password: 'correct horse battery',
    });
    assert.equal(prompt.status, 'prompt');
    assert.equal(prompt.prompt.type, 'visible');
    assert.match(prompt.prompt.message, /one-time code/i);

    const started = await client.respond({ response: '123456' });
    assert.equal(started.status, 'starting');
  });
});

test('greeter app serves the browser login flow and maps auth failures to HTTP 401', async () => {
  await withFakeGreetd(message => {
    if (message.type === 'create_session') {
      return [ { type: 'error', error_type: 'auth_error', description: 'Authentication failed.' } ];
    }
    return [];
  }, async ({ socketPath }) => {
    const client = new GreetdClient({
      socketPath,
      sessionCommand: '/bin/start-user-session',
    });

    await withGreeterServer(client, async baseUrl => {
      const page = await fetch(`${baseUrl}/login`);
      const html = await page.text();
      assert.equal(page.status, 200);
      assert.match(html, /Welcome Back/);
      assert.match(html, /Authentication is handled by the system login stack/);

      const response = await fetch(`${baseUrl}/api/login`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          username: 'alice',
          password: 'wrong password',
        }),
      });
      const payload = await response.json();
      assert.equal(response.status, 401);
      assert.match(payload.error, /authentication failed/i);
    });
  });
});
