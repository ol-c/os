import { StreamLanguage } from '@codemirror/language';
import { cpp } from '@codemirror/lang-cpp';
import { css } from '@codemirror/lang-css';
import { go } from '@codemirror/lang-go';
import { html } from '@codemirror/lang-html';
import { java } from '@codemirror/lang-java';
import { javascript } from '@codemirror/lang-javascript';
import { json } from '@codemirror/lang-json';
import { markdown } from '@codemirror/lang-markdown';
import { php } from '@codemirror/lang-php';
import { python } from '@codemirror/lang-python';
import { rust } from '@codemirror/lang-rust';
import { sql } from '@codemirror/lang-sql';
import { xml } from '@codemirror/lang-xml';
import { yaml } from '@codemirror/lang-yaml';
import { nix } from '@replit/codemirror-lang-nix';
import { shell } from '@codemirror/legacy-modes/mode/shell';
import { toml } from '@codemirror/legacy-modes/mode/toml';

function createExtensionFactory(load) {
  let cached = null;
  return () => {
    if (!cached) {
      cached = load();
    }
    return cached;
  };
}

function createLanguageEntry({
  name,
  extensions = [],
  exactFilenames = [],
  match = null,
  load,
}) {
  return Object.freeze({
    name,
    extensions: extensions.map(extension => extension.toLowerCase()),
    exactFilenames: exactFilenames.map(filename => filename.toLowerCase()),
    match,
    load: createExtensionFactory(load),
  });
}

function basename(path) {
  const normalized = String(path || '').replace(/\\/g, '/');
  const parts = normalized.split('/');
  return (parts.pop() || '').toLowerCase();
}

function extensionForPath(path) {
  const fileName = basename(path);
  const dotIndex = fileName.lastIndexOf('.');
  return dotIndex === -1 ? '' : fileName.slice(dotIndex);
}

export const languageRegistry = Object.freeze([
  createLanguageEntry({
    name: 'Nix',
    extensions: [ '.nix' ],
    exactFilenames: [ 'flake.lock' ],
    load: () => nix(),
  }),
  createLanguageEntry({
    name: 'JavaScript',
    extensions: [ '.js', '.mjs', '.cjs', '.jsx' ],
    load: () => javascript({ jsx: true }),
  }),
  createLanguageEntry({
    name: 'TypeScript',
    extensions: [ '.ts', '.tsx' ],
    load: () => javascript({ typescript: true, jsx: true }),
  }),
  createLanguageEntry({
    name: 'JSON',
    extensions: [ '.json', '.jsonc' ],
    exactFilenames: [ '.eslintrc', '.prettierrc' ],
    load: () => json(),
  }),
  createLanguageEntry({
    name: 'Markdown',
    extensions: [ '.md', '.markdown', '.mdx' ],
    exactFilenames: [ 'readme', 'readme.md', 'agents.md', 'license.md' ],
    load: () => markdown(),
  }),
  createLanguageEntry({
    name: 'HTML',
    extensions: [ '.html', '.htm' ],
    load: () => html(),
  }),
  createLanguageEntry({
    name: 'CSS',
    extensions: [ '.css', '.scss', '.sass', '.less' ],
    load: () => css(),
  }),
  createLanguageEntry({
    name: 'XML',
    extensions: [ '.xml', '.svg', '.rss', '.atom' ],
    load: () => xml(),
  }),
  createLanguageEntry({
    name: 'YAML',
    extensions: [ '.yaml', '.yml' ],
    load: () => yaml(),
  }),
  createLanguageEntry({
    name: 'Python',
    extensions: [ '.py', '.pyw' ],
    load: () => python(),
  }),
  createLanguageEntry({
    name: 'Rust',
    extensions: [ '.rs' ],
    load: () => rust(),
  }),
  createLanguageEntry({
    name: 'Go',
    extensions: [ '.go' ],
    load: () => go(),
  }),
  createLanguageEntry({
    name: 'Java',
    extensions: [ '.java' ],
    load: () => java(),
  }),
  createLanguageEntry({
    name: 'PHP',
    extensions: [ '.php' ],
    load: () => php(),
  }),
  createLanguageEntry({
    name: 'SQL',
    extensions: [ '.sql' ],
    load: () => sql(),
  }),
  createLanguageEntry({
    name: 'C/C++',
    extensions: [ '.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.hxx' ],
    load: () => cpp(),
  }),
  createLanguageEntry({
    name: 'Shell',
    extensions: [ '.sh', '.bash', '.zsh', '.ksh', '.env' ],
    exactFilenames: [ '.bashrc', '.bash_profile', '.profile', '.zshrc', '.zprofile' ],
    match: fileName => fileName.endsWith('rc'),
    load: () => StreamLanguage.define(shell),
  }),
  createLanguageEntry({
    name: 'TOML',
    extensions: [ '.toml' ],
    exactFilenames: [ 'cargo.lock' ],
    load: () => StreamLanguage.define(toml),
  }),
]);

export function languageDescriptionForPath(path) {
  const fileName = basename(path);
  const extension = extensionForPath(path);
  return languageRegistry.find(language =>
    language.exactFilenames.includes(fileName)
    || language.extensions.includes(extension)
    || (typeof language.match === 'function' && language.match(fileName, extension))
  ) ?? null;
}

export function languageNameForPath(path) {
  return languageDescriptionForPath(path)?.name ?? 'Plain text';
}

export function languageExtensionForPath(path) {
  return languageDescriptionForPath(path)?.load() ?? [];
}
