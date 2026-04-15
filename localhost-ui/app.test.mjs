import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import { createOlcApp } from './app.mjs';
import { createDefaultSystemStatus, createFakeSystemAdapter, createSystemControls } from './system-controls.mjs';

async function withServer(fn, hardwareTest = undefined) {
  const app = createOlcApp({
    bashBin: '/bin/bash',
    demoUser: { uid: '1000', gid: '100' },
    systemControls: createSystemControls(
      createFakeSystemAdapter(createDefaultSystemStatus(hardwareTest)),
      { pollIntervalMs: 0 },
    ),
    terminalClientCss: '',
    terminalClientJs: '',
    ttydBin: '/bin/false',
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
    assert.match(html, /id="bluetooth-heading">Bluetooth/);
    assert.match(html, /new EventSource\('\/api\/system\/events'\)/);
    assert.match(html, /id="network-control"/);
    assert.match(html, /id="network-implementation"/);
    assert.match(html, /id="power-implementation"/);
    assert.match(html, /id="volume-implementation"/);
    assert.match(html, /id="brightness-implementation"/);
    assert.match(html, /id="appearance-implementation"/);
    assert.match(html, /id="bluetooth-implementation"/);
    assert.match(html, /id="volume-control" type="range"/);
    assert.match(html, /id="appearance-control"/);
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
