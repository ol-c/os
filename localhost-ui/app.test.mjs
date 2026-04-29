import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import http from 'node:http';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { createOlcApp } from './app.mjs';
import { createDefaultSystemStatus, createFakeSystemAdapter, createSystemControls } from './system-controls.mjs';

function createStateProvider(initialState) {
  let state = { ...initialState };

  return {
    getState: async () => ({ ...state }),
    setState(nextState) {
      state = { ...state, ...nextState };
    },
  };
}

function createSetupProgressProvider(initialProgress = {
  inProgress: false,
  result: 'idle',
  step: 'idle',
  username: null,
  startedAt: null,
  finishedAt: null,
  latestMessage: null,
  events: [],
}) {
  let progress = {
    ...initialProgress,
    events: initialProgress.events.map(event => ({ ...event })),
  };
  const listeners = new Set();

  function clone() {
    return {
      ...progress,
      events: progress.events.map(event => ({ ...event })),
    };
  }

  return {
    getProgress: () => clone(),
    publish(nextProgress) {
      progress = {
        ...nextProgress,
        events: (nextProgress.events || []).map(event => ({ ...event })),
      };
      const snapshot = clone();
      for (const listener of listeners) {
        listener(snapshot);
      }
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}

async function withServer(fn, options = {}) {
  const state = createStateProvider(options.runtimeState || { setupMode: false, activeUser: null });
  const setupProgress = createSetupProgressProvider(options.setupProgress);
  const createFirstUserCalls = [];
  const setupCompletions = [];
  const app = createOlcApp({
    createFirstUser: async body => {
      createFirstUserCalls.push(body);
      if (options.createFirstUser) {
        return await options.createFirstUser(body);
      }
      return { ok: true, message: 'Setup complete. Returning to the login prompt.' };
    },
    getSetupProgress: () => setupProgress.getProgress(),
    getRuntimeState: () => state.getState(),
    onSetupCompleted: payload => {
      setupCompletions.push(payload);
    },
    subscribeSetupProgress: listener => setupProgress.subscribe(listener),
    systemControls: createSystemControls(
      createFakeSystemAdapter(createDefaultSystemStatus(options.hardwareTest)),
      { pollIntervalMs: 0 },
    ),
    terminalUpstreamUrl: options.terminalUpstreamUrl || 'http://127.0.0.1:9',
  });
  const server = http.createServer(app.handleRequest);

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    await fn({
      baseUrl: `http://127.0.0.1:${port}`,
      createFirstUserCalls,
      publishSetupProgress: nextProgress => setupProgress.publish(nextProgress),
      setState: nextState => state.setState(nextState),
      setupCompletions,
    });
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

async function requestJson(baseUrl, path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, options);
  const body = await response.json();
  return { body, response };
}

async function readStatusEvent(stream) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      throw new Error('SSE stream ended before status event');
    }

    buffer += decoder.decode(value, { stream: true });
    const events = buffer.split('\n\n');
    buffer = events.pop();

    for (const event of events) {
      if (!event.includes('event: status')) {
        continue;
      }

      const dataLine = event.split('\n').find(line => line.startsWith('data: '));
      reader.releaseLock();
      return JSON.parse(dataLine.slice('data: '.length));
    }
  }
}

function createStatusEventReader(stream) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  return {
    async nextStatus() {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) {
          throw new Error('SSE stream ended before status event');
        }

        buffer += decoder.decode(value, { stream: true });
        const events = buffer.split('\n\n');
        buffer = events.pop();

        for (const event of events) {
          if (!event.includes('event: status')) {
            continue;
          }

          const dataLine = event.split('\n').find(line => line.startsWith('data: '));
          return JSON.parse(dataLine.slice('data: '.length));
        }
      }
    },
    release() {
      reader.releaseLock();
    },
  };
}

test('fresh machines render the setup page at root', async () => {
  await withServer(async ({ baseUrl }) => {
    const response = await fetch(`${baseUrl}/`);
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(html, /<title>First Setup<\/title>/);
    assert.match(html, /Create first admin/);
    assert.doesNotMatch(html, /<h1>System<\/h1>/);
  }, {
    runtimeState: { setupMode: true, activeUser: { name: 'olc-setup' } },
  });
});

test('configured machines render the system page and redirect /setup', async () => {
  await withServer(async ({ baseUrl }) => {
    const response = await fetch(`${baseUrl}/`);
    const html = await response.text();
    assert.equal(response.status, 200);
    assert.match(html, /<h1>System<\/h1>/);

    const setup = await fetch(`${baseUrl}/setup`, { redirect: 'manual' });
    assert.equal(setup.status, 303);
    assert.equal(setup.headers.get('location'), '/');
  }, {
    runtimeState: {
      setupMode: false,
      activeUser: {
        name: process.env.USER || 'node',
        uid: String(process.getuid?.() ?? 1000),
        gid: String(process.getgid?.() ?? 1000),
        home: process.env.HOME || tmpdir(),
      },
    },
  });
});

test('setup status and first-user creation are routed through the setup API', async () => {
  await withServer(async ({ baseUrl, createFirstUserCalls, setupCompletions }) => {
    const status = await requestJson(baseUrl, '/api/setup/status');
    assert.equal(status.response.status, 200);
    assert.equal(status.body.setupMode, true);
    assert.equal(status.body.progress.inProgress, false);

    const created = await requestJson(baseUrl, '/api/setup/first-user', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        username: 'alice',
        password: 'correct horse battery',
        confirmPassword: 'correct horse battery',
      }),
    });
    assert.equal(created.response.status, 200);
    assert.equal(createFirstUserCalls.length, 1);
    assert.equal(createFirstUserCalls[0].username, 'alice');
    assert.equal(setupCompletions.length, 1);
  }, {
    runtimeState: { setupMode: true, activeUser: { name: 'olc-setup' } },
  });
});

test('setup mode blocks system controls, terminal, and editor routes', async () => {
  await withServer(async ({ baseUrl }) => {
    const terminal = await fetch(`${baseUrl}/terminal`);
    assert.equal(terminal.status, 409);

    const editor = await fetch(`${baseUrl}/edit`);
    assert.equal(editor.status, 409);

    const systemEvents = await requestJson(baseUrl, '/api/system/volume', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ percent: 73 }),
    });
    assert.equal(systemEvents.response.status, 409);
    assert.match(systemEvents.body.error, /unavailable during first setup/i);
  }, {
    runtimeState: { setupMode: true, activeUser: { name: 'olc-setup' } },
  });
});

test('editor API lists, reads, and saves files as the active signed-in user', async () => {
  const root = await mkdtemp(join(tmpdir(), 'olc-edit-'));
  const file = join(root, 'note.txt');
  await writeFile(file, 'first draft', 'utf8');

  await withServer(async ({ baseUrl }) => {
    const listed = await requestJson(baseUrl, `/api/edit/list?path=${encodeURIComponent(root)}`);
    assert.equal(listed.response.status, 200);
    assert.deepEqual(listed.body.entries.map(entry => [entry.name, entry.kind]), [
      ['note.txt', 'file'],
    ]);

    const read = await requestJson(baseUrl, `/api/edit/file?path=${encodeURIComponent(file)}`);
    assert.equal(read.response.status, 200);
    assert.equal(read.body.content, 'first draft');

    const saved = await requestJson(baseUrl, '/api/edit/file', {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ path: file, content: 'saved draft' }),
    });
    assert.equal(saved.response.status, 200);
    assert.equal(await readFile(file, 'utf8'), 'saved draft');
  }, {
    runtimeState: {
      setupMode: false,
      activeUser: {
        name: process.env.USER || 'node',
        uid: String(process.getuid?.() ?? 1000),
        gid: String(process.getgid?.() ?? 1000),
        home: process.env.HOME || tmpdir(),
      },
    },
  });
});

test('setup progress SSE sends initial and live provisioning updates', async () => {
  await withServer(async ({ baseUrl, publishSetupProgress }) => {
    const response = await fetch(`${baseUrl}/api/setup/events`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type'), /text\/event-stream/);

    const reader = createStatusEventReader(response.body);
    const initial = await reader.nextStatus();
    assert.equal(initial.inProgress, false);
    assert.equal(initial.result, 'idle');

    publishSetupProgress({
      inProgress: true,
      result: 'running',
      step: 'creating',
      username: 'alice',
      startedAt: '2026-04-29T00:00:00.000Z',
      finishedAt: null,
      latestMessage: 'Creating encrypted home for alice.',
      events: [
        {
          seq: 1,
          kind: 'info',
          step: 'creating',
          message: 'Creating encrypted home for alice.',
          timestamp: '2026-04-29T00:00:00.000Z',
        },
      ],
    });

    const update = await reader.nextStatus();
    assert.equal(update.inProgress, true);
    assert.equal(update.latestMessage, 'Creating encrypted home for alice.');
    assert.equal(update.events.length, 1);

    reader.release();
    await response.body.cancel();
  }, {
    runtimeState: { setupMode: true, activeUser: { name: 'olc-setup' } },
  });
});

test('SSE stream sends the initial status event on configured machines', async () => {
  await withServer(async ({ baseUrl }) => {
    const response = await fetch(`${baseUrl}/api/system/events`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type'), /text\/event-stream/);

    const status = await readStatusEvent(response.body);
    await response.body.cancel();
    assert.equal(status.volume.percent, 40);
    assert.equal(status.appearance.mode, 'light');
    assert.equal(status.terminal.font, 'dejavu-sans-mono');
  }, {
    runtimeState: {
      setupMode: false,
      activeUser: {
        name: process.env.USER || 'node',
        uid: String(process.getuid?.() ?? 1000),
        gid: String(process.getgid?.() ?? 1000),
        home: process.env.HOME || tmpdir(),
      },
    },
  });
});
