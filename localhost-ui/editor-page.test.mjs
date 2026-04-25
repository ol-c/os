import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

import { editorHtml } from './editor-page.mjs';

test('editor page renders explicit editor controls and status surfaces', () => {
  const dom = new JSDOM(editorHtml());
  const { document } = dom.window;

  assert.ok(document.getElementById('filter'));
  assert.ok(document.getElementById('reload-file'));
  assert.ok(document.getElementById('save-file'));
  assert.ok(document.getElementById('editor-title'));
  assert.ok(document.getElementById('editor-status'));
  assert.ok(document.getElementById('editor-language'));
  assert.ok(document.getElementById('buffers'));
  assert.ok(document.getElementById('tree'));
  assert.ok(document.querySelector('script[src="/edit/assets/editor.js"]'));
});
