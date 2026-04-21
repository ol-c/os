import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import http from 'node:http';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { createOlcApp } from './app.mjs';
import { createDefaultSystemStatus, createFakeSystemAdapter, createSystemControls } from './system-controls.mjs';

async function withServer(fn, hardwareTest = undefined, options = {}) {
  const app = createOlcApp({
    systemControls: createSystemControls(
      createFakeSystemAdapter(createDefaultSystemStatus(hardwareTest)),
      { pollIntervalMs: 0 },
    ),
    ...options,
  });
  const server = http.createServer(app.handleRequest);

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

async function withTerminalUpstream(fn) {
  const seenPaths = [];
  const upstream = http.createServer((req, res) => {
    seenPaths.push(req.url);
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(`terminal upstream ${req.url}`);
  });

  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  const { port } = upstream.address();

  try {
    await withServer(
      baseUrl => fn(baseUrl, seenPaths),
      undefined,
      { terminalUpstreamUrl: `http://127.0.0.1:${port}` },
    );
  } finally {
    await new Promise(resolve => upstream.close(resolve));
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

test('root page exposes the system document and inline controls', async () => {
  await withServer(async baseUrl => {
    const response = await fetch(`${baseUrl}/`);
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(html, /<h1>System<\/h1>/);
    assert.match(html, /id="network-heading">Network/);
    assert.match(html, /id="power-heading">Power/);
    assert.match(html, /id="sound-heading">Sound/);
    assert.match(html, /id="display-heading">Display/);
    assert.match(html, /id="appearance-heading">Appearance/);
    assert.match(html, /id="terminal-heading">Terminal/);
    assert.match(html, /id="bluetooth-heading">Bluetooth/);
    assert.match(html, /new EventSource\('\/api\/system\/events'\)/);
    assert.match(html, /id="network-control"/);
    assert.match(html, /id="network-implementation"/);
    assert.match(html, /id="power-implementation"/);
    assert.match(html, /id="volume-implementation"/);
    assert.match(html, /id="brightness-implementation"/);
    assert.match(html, /id="appearance-implementation"/);
    assert.match(html, /id="terminal-implementation"/);
    assert.match(html, /id="bluetooth-implementation"/);
    assert.match(html, /id="volume-control" type="range"/);
    assert.match(html, /id="appearance-control"/);
    assert.match(html, /id="terminal-font-control"/);
    assert.match(html, /id="terminal-color-scheme-control"/);
    assert.match(html, /id="open-terminal-control" type="button">Open terminal<\/button>/);
    assert.match(html, /id="open-editor-control" type="button">Open editor<\/button>/);
    assert.doesNotMatch(html, /<a href="\/terminal"/);
    assert.match(html, /postCommand\('\/api\/system\/terminal'/);
    assert.match(html, /controls\.openTerminal\.addEventListener\('click'/);
    assert.match(html, /window\.open\('\/edit\?root=\/source', '_blank'\)/);
    assert.match(html, /WebChannelMessageToChrome/);
    assert.match(html, /olc-appearance/);
    assert.match(html, /setAppearance/);
  });
});

test('/edit page serves the browser editor without adding preference endpoints', async () => {
  await withServer(async baseUrl => {
    const response = await fetch(`${baseUrl}/edit`);
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(html, /<title>Editor<\/title>/);
    assert.match(html, /id="buffers" role="list"/);
    assert.match(html, /<script src="\/edit\/assets\/editor\.js"><\/script>/);
    assert.match(html, /#app \{/);
    assert.match(html, /overflow: hidden;/);
    assert.doesNotMatch(html, /id="status"/);
    assert.doesNotMatch(html, /#status \{/);
    assert.doesNotMatch(html, /id="filebar"/);
    assert.doesNotMatch(html, /id="save"/);

    const asset = await fetch(`${baseUrl}/edit/assets/editor.js`);
    const js = await asset.text();
    assert.equal(asset.status, 200);
    assert.match(js, /codemirror/);
    assert.match(js, /\/api\/system\/events/);
    assert.match(js, /status\?\.terminal\?\.font/);
    assert.match(js, /status\?\.terminal\?\.colorScheme/);
    assert.match(js, /maxHeight: "100%"/);
    assert.match(js, /overflow: "auto"/);
    assert.match(js, /openBuffers = .*new Map/);
    assert.match(js, /themeCompartment = new Compartment/);
    assert.match(js, /setState/);
    assert.match(js, /activeBuffer\.state = update\.state/);
    assert.match(js, /bufferStateLabel/);
    assert.match(js, /\\u25CF/);
    assert.match(js, /\\u25C6/);
    assert.match(js, /\\u25CB/);
    assert.match(js, /\\u25C7/);
    assert.match(js, /Close \$\{buffer\.name\} with unsaved edits\?/);
    assert.match(js, /window\.confirm/);
    assert.match(js, /buffer-close/);
    assert.match(js, /\\xD7/);
    assert.match(js, /event\.key\.toLowerCase\(\) === "s"/);
    assert.match(js, /preventDefault/);
    assert.doesNotMatch(js, /from: 0,\s*to: editorView\.state\.doc\.length,\s*insert: content/);
    assert.doesNotMatch(js, /\/api\/system\/editor/);
  });
});

test('editor API lists, reads, and saves demo-user visible files', async () => {
  const root = await mkdtemp(join(tmpdir(), 'olc-edit-'));
  const file = join(root, 'note.txt');
  await writeFile(file, 'first draft', 'utf8');

  await withServer(async baseUrl => {
    const listed = await requestJson(baseUrl, `/api/edit/list?path=${encodeURIComponent(root)}`);
    assert.equal(listed.response.status, 200);
    assert.equal(listed.body.path, root);
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
  });
});

test('editor API rejects malformed paths and wrong methods', async () => {
  await withServer(async baseUrl => {
    const relativeList = await requestJson(baseUrl, '/api/edit/list?path=relative');
    assert.equal(relativeList.response.status, 400);
    assert.match(relativeList.body.error, /absolute/);

    const missingContent = await requestJson(baseUrl, '/api/edit/file', {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ path: '/tmp/olc-edit-missing-content' }),
    });
    assert.equal(missingContent.response.status, 400);
    assert.match(missingContent.body.error, /content must be a string/);

    const wrongMethod = await fetch(`${baseUrl}/api/edit/list`, { method: 'POST' });
    assert.equal(wrongMethod.status, 405);
  });
});

test('SSE stream sends the initial status event', async () => {
  await withServer(async baseUrl => {
    const response = await fetch(`${baseUrl}/api/system/events`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type'), /text\/event-stream/);

    const status = await readStatusEvent(response.body);
    await response.body.cancel();
    assert.equal(status.volume.percent, 40);
    assert.equal(status.appearance.mode, 'light');
    assert.equal(status.terminal.font, 'dejavu-sans-mono');
  });
});

test('SSE stream reflects selected fake hardware capabilities', async () => {
  await withServer(async baseUrl => {
    const response = await fetch(`${baseUrl}/api/system/events`);
    const status = await readStatusEvent(response.body);
    await response.body.cancel();

    assert.equal(status.network.kind, 'wifi');
    assert.equal(status.power.available, true);
    assert.equal(status.bluetooth.available, true);
    assert.equal(status.volume.available, false);
  }, 'wifi,battery,bluetooth');
});

test('command endpoint returns status and publishes an SSE update', async () => {
  await withServer(async baseUrl => {
    const events = await fetch(`${baseUrl}/api/system/events`);
    await readStatusEvent(events.body);

    const updatePromise = readStatusEvent(events.body);
    const { body, response } = await requestJson(baseUrl, '/api/system/volume', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ percent: 73 }),
    });

    assert.equal(response.status, 200);
    assert.equal(body.volume.percent, 73);

    const published = await updatePromise;
    await events.body.cancel();
    assert.equal(published.volume.percent, 73);
  });
});

test('terminal command endpoint updates font and color scheme', async () => {
  await withServer(async baseUrl => {
    const { body, response } = await requestJson(baseUrl, '/api/system/terminal', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ font: 'inconsolata', colorScheme: 'tango' }),
    });

    assert.equal(response.status, 200);
    assert.equal(body.terminal.font, 'inconsolata');
    assert.equal(body.terminal.colorScheme, 'tango');
  });
});

test('command endpoint validates request bodies and methods', async () => {
  await withServer(async baseUrl => {
    const badBody = await fetch(`${baseUrl}/api/system/volume`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{',
    });
    assert.equal(badBody.status, 400);

    const badValue = await requestJson(baseUrl, '/api/system/appearance', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ mode: 'auto' }),
    });
    assert.equal(badValue.response.status, 400);
    assert.match(badValue.body.error, /mode must be light or dark/);

    const badTerminal = await requestJson(baseUrl, '/api/system/terminal', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ colorScheme: 'custom' }),
    });
    assert.equal(badTerminal.response.status, 400);
    assert.match(badTerminal.body.error, /light and dark terminal color schemes/);

    const wrongMethod = await requestJson(baseUrl, '/api/system/bluetooth');
    assert.equal(wrongMethod.response.status, 405);
  });
});

test('command endpoint rejects disabled hardware capabilities', async () => {
  await withServer(async baseUrl => {
    const { body, response } = await requestJson(baseUrl, '/api/system/volume', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ percent: 73 }),
    });

    assert.equal(response.status, 409);
    assert.match(body.error, /volume control is unavailable/);
  }, 'none');
});

test('/terminal is proxied to the stable terminal service', async () => {
  await withTerminalUpstream(async (baseUrl, seenPaths) => {
    const response = await fetch(`${baseUrl}/terminal`);
    const body = await response.text();

    assert.equal(response.status, 200);
    assert.equal(body, 'terminal upstream /terminal');
    assert.deepEqual(seenPaths, [ '/terminal' ]);
  });
});

test('terminal backend paths are not proxied through the reloadable UI service', async () => {
  await withTerminalUpstream(async (baseUrl, seenPaths) => {
    const response = await fetch(`${baseUrl}/session/session-token/token`);
    const body = await response.text();

    assert.equal(response.status, 404);
    assert.match(body, /requested ol-c page was not found/);
    assert.deepEqual(seenPaths, []);
  });
});
