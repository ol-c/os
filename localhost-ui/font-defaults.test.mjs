import assert from 'node:assert/strict';
import test from 'node:test';
import { editorHtml } from './editor-page.mjs';
import { loginGreeterHtml } from './login-greeter-page.mjs';
import { setupHtml } from './setup-page.mjs';
import { rootHtml } from './system-page.mjs';
import {
  defaultTerminalPreferences,
  terminalFontChoices,
} from './terminal-options.mjs';

test('browser shell pages use Noto font stacks', () => {
  const html = [
    editorHtml(),
    loginGreeterHtml(),
    setupHtml(),
    rootHtml(),
  ].join('\n');

  assert.match(html, /Noto Sans/);
  assert.match(html, /Noto Serif/);
  assert.match(html, /Noto Color Emoji/);
  assert.doesNotMatch(html, /DejaVu|Inconsolata|Iowan|Palatino|Book Antiqua|Georgia|system-ui|"Segoe UI"/);
});

test('terminal and editor font preference defaults are Noto-only', () => {
  assert.equal(defaultTerminalPreferences.font, 'noto-sans-mono');
  assert.deepEqual(terminalFontChoices.map(choice => choice.id), [ 'noto-sans-mono' ]);
  assert.match(terminalFontChoices[0].cssFamily, /Noto Sans Mono/);
  assert.match(terminalFontChoices[0].cssFamily, /Noto Color Emoji/);
});
