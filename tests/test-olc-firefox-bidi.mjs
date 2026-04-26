import test from 'node:test';
import assert from 'node:assert/strict';

import { pickContext, runBidiCommand } from '../tools/olc-firefox-bidi.mjs';

test('pickContext prefers matching localhost prefix', () => {
  const context = pickContext([
    { context: 'a', url: 'about:blank' },
    { context: 'b', url: 'https://localhost/terminal' },
  ], 'https://localhost/');

  assert.equal(context.context, 'b');
});

test('runBidiCommand evaluates script in matching context', async () => {
  const calls = [];
  const connection = {
    async sendCommand(method, params) {
      calls.push({ method, params });
      if (method === 'session.new' || method === 'session.end') {
        return {};
      }
      if (method === 'browsingContext.getTree') {
        return {
          contexts: [
            { context: 'ctx-localhost', url: 'https://localhost/' },
          ],
        };
      }
      if (method === 'script.evaluate') {
        return { result: { value: 'System' } };
      }
      throw new Error(`unexpected method: ${method}`);
    },
  };

  const result = await runBidiCommand({
    connection,
    command: 'eval',
    argument: 'document.title',
  });

  assert.equal(result, 'System');
  assert.deepEqual(calls.map(call => call.method), [
    'session.new',
    'browsingContext.getTree',
    'script.evaluate',
    'session.end',
  ]);
});

test('runBidiCommand navigates matching context', async () => {
  const calls = [];
  const connection = {
    async sendCommand(method, params) {
      calls.push({ method, params });
      if (method === 'session.new' || method === 'session.end') {
        return {};
      }
      if (method === 'browsingContext.getTree') {
        return {
          contexts: [
            { context: 'ctx-localhost', url: 'https://localhost/' },
          ],
        };
      }
      if (method === 'browsingContext.navigate') {
        return { navigation: 'done' };
      }
      throw new Error(`unexpected method: ${method}`);
    },
  };

  await runBidiCommand({
    connection,
    command: 'navigate',
    argument: 'https://localhost/terminal',
  });

  assert.equal(calls[2].method, 'browsingContext.navigate');
  assert.equal(calls[2].params.context, 'ctx-localhost');
  assert.equal(calls[2].params.url, 'https://localhost/terminal');
});
