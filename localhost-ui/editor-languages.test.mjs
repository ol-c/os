import test from 'node:test';
import assert from 'node:assert/strict';

import {
  languageDescriptionForPath,
  languageExtensionForPath,
  languageNameForPath,
  languageRegistry,
} from './editor-languages.mjs';

test('language registry resolves common repo file types', () => {
  assert.equal(languageNameForPath('/source/AGENTS.md'), 'Markdown');
  assert.equal(languageNameForPath('/source/flake.nix'), 'Nix');
  assert.equal(languageNameForPath('/source/localhost-ui/editor-client.js'), 'JavaScript');
  assert.equal(languageNameForPath('/source/package.json'), 'JSON');
  assert.equal(languageNameForPath('/source/default.nix'), 'Nix');
  assert.equal(languageNameForPath('/source/scripts/dev.sh'), 'Shell');
  assert.equal(languageNameForPath('/source/Cargo.toml'), 'TOML');
});

test('language registry handles exact filenames and case-insensitive matching', () => {
  assert.equal(languageNameForPath('/source/README'), 'Markdown');
  assert.equal(languageNameForPath('/source/.BASHRC'), 'Shell');
  assert.equal(languageNameForPath('/source/Flake.LOCK'), 'Nix');
  assert.equal(languageNameForPath('/source/notes/PLAN.MD'), 'Markdown');
});

test('language registry falls back to plain text for unknown files', () => {
  assert.equal(languageDescriptionForPath('/source/archive.unknown'), null);
  assert.equal(languageNameForPath('/source/archive.unknown'), 'Plain text');
  assert.deepEqual(languageExtensionForPath('/source/archive.unknown'), []);
});

test('language registry caches extensions for stable reuse', () => {
  const description = languageRegistry.find(entry => entry.name === 'JavaScript');
  assert.ok(description);
  assert.equal(description.load(), description.load());
});
