import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { setupHtml } from './setup-page.mjs';

async function waitFor(condition) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (condition()) {
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 0));
  }

  throw new Error('timed out waiting for condition');
}

test('setup page streams provisioning status while first-user creation is running', async () => {
  let eventSource = null;
  let fetchRequest = null;
  let resolveFetch = null;

  class FakeEventSource {
    constructor(url) {
      this.url = url;
      this.listeners = new Map();
      eventSource = this;
    }

    addEventListener(type, listener) {
      const listeners = this.listeners.get(type) || [];
      listeners.push(listener);
      this.listeners.set(type, listeners);
    }

    close() {}

    emit(type, payload) {
      for (const listener of this.listeners.get(type) || []) {
        listener({ data: JSON.stringify(payload) });
      }
    }
  }

  const dom = new JSDOM(setupHtml(), {
    runScripts: 'dangerously',
    url: 'https://localhost/setup',
    beforeParse(window) {
      window.EventSource = FakeEventSource;
      window.fetch = async (path, options) => {
        fetchRequest = {
          path,
          options,
        };
        return await new Promise(resolve => {
          resolveFetch = resolve;
        });
      };
    },
  });
  const { document, Event } = dom.window;

  assert.ok(eventSource);
  assert.equal(eventSource.url, '/api/setup/events');

  document.getElementById('username').value = 'alice';
  document.getElementById('password').value = 'correct horse battery';
  document.getElementById('confirm-password').value = 'correct horse battery';
  document.getElementById('setup-form').dispatchEvent(new Event('submit', {
    bubbles: true,
    cancelable: true,
  }));

  await waitFor(() => fetchRequest !== null);

  assert.equal(fetchRequest.path, '/api/setup/first-user');
  assert.equal(JSON.parse(fetchRequest.options.body).username, 'alice');
  assert.equal(document.getElementById('submit').disabled, true);
  assert.equal(document.getElementById('message').textContent, 'In progress');
  assert.equal(document.getElementById('setup-progress').hidden, false);
  assert.equal(document.querySelector('[role="progressbar"]').getAttribute('aria-valuetext'), 'In progress');

  eventSource.emit('status', {
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
        step: 'starting',
        message: 'Starting secure account setup for alice.',
        timestamp: '2026-04-29T00:00:00.000Z',
      },
      {
        seq: 2,
        kind: 'info',
        step: 'creating',
        message: 'Creating encrypted home for alice.',
        timestamp: '2026-04-29T00:00:01.000Z',
      },
    ],
  });

  await waitFor(() => document.getElementById('message').textContent === 'In progress');
  assert.equal(document.getElementById('setup-progress').textContent.replace(/\s+/g, ' ').trim(), 'In progress');

  resolveFetch(new Response(JSON.stringify({
    ok: true,
    message: 'Setup complete. Returning to the login screen.',
  }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  }));

  await waitFor(() => document.getElementById('message').textContent === 'Setup complete. Returning to the login screen.');
  assert.equal(document.getElementById('setup-progress').hidden, true);
});
