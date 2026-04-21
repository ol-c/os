import { EditorView, basicSetup } from 'codemirror';
import { Compartment, EditorState } from '@codemirror/state';
import { syntaxHighlighting, HighlightStyle } from '@codemirror/language';
import { tags } from '@lezer/highlight';
import {
  defaultTerminalPreferences,
  findTerminalFont,
} from './terminal-options.mjs';

const terminalThemes = Object.freeze({
  solarized: Object.freeze({
    light: Object.freeze({
      background: '#fdf6e3',
      foreground: '#657b83',
      panel: '#fbfbf8',
      panelForeground: '#181a1f',
      muted: '#586e75',
      line: '#eee8d5',
      accent: '#268bd2',
      selection: '#eee8d5',
      keyword: '#859900',
      string: '#2aa198',
      number: '#d33682',
      comment: '#93a1a1',
      variable: '#b58900',
      error: '#dc322f',
    }),
    dark: Object.freeze({
      background: '#002b36',
      foreground: '#839496',
      panel: '#073642',
      panelForeground: '#93a1a1',
      muted: '#586e75',
      line: '#073642',
      accent: '#268bd2',
      selection: '#073642',
      keyword: '#859900',
      string: '#2aa198',
      number: '#d33682',
      comment: '#586e75',
      variable: '#b58900',
      error: '#dc322f',
    }),
  }),
  tango: Object.freeze({
    light: Object.freeze({
      background: '#ffffff',
      foreground: '#2e3436',
      panel: '#eeeeec',
      panelForeground: '#2e3436',
      muted: '#555753',
      line: '#d3d7cf',
      accent: '#3465a4',
      selection: '#d3d7cf',
      keyword: '#4e9a06',
      string: '#06989a',
      number: '#75507b',
      comment: '#888a85',
      variable: '#c4a000',
      error: '#cc0000',
    }),
    dark: Object.freeze({
      background: '#2e3436',
      foreground: '#d3d7cf',
      panel: '#343a3b',
      panelForeground: '#eeeeec',
      muted: '#babdb6',
      line: '#555753',
      accent: '#729fcf',
      selection: '#555753',
      keyword: '#8ae234',
      string: '#34e2e2',
      number: '#ad7fa8',
      comment: '#888a85',
      variable: '#fce94f',
      error: '#ef2929',
    }),
  }),
});

const nodes = {
  buffers: document.getElementById('buffers'),
  cwd: document.getElementById('cwd'),
  editor: document.getElementById('editor'),
  filter: document.getElementById('filter'),
  tree: document.getElementById('tree'),
};

let currentDirectory = '/source';
let initialFile = null;
let activePath = null;
const openBuffers = new Map();
let entries = [];
let editorPreferences = { ...defaultTerminalPreferences };
let appearanceMode = 'light';
const themeCompartment = new Compartment();

function parseInitialLocation() {
  const url = new URL(window.location.href);
  const root = url.searchParams.get('root');
  const path = url.searchParams.get('path');
  if (root) {
    currentDirectory = root;
  }
  if (path) {
    initialFile = path;
    currentDirectory = path.slice(0, path.lastIndexOf('/')) || '/';
  }
}

function selectedTheme() {
  return terminalThemes[editorPreferences.colorScheme]?.[appearanceMode]
    ?? terminalThemes[defaultTerminalPreferences.colorScheme][appearanceMode];
}

function selectedFontFamily() {
  return findTerminalFont(editorPreferences.font)?.cssFamily
    ?? findTerminalFont(defaultTerminalPreferences.font).cssFamily;
}

function themeExtension(theme) {
  return [
    EditorView.theme({
      '&': {
        height: '100%',
        maxHeight: '100%',
        color: theme.foreground,
        backgroundColor: theme.background,
        fontFamily: selectedFontFamily(),
        overflow: 'hidden',
      },
      '.cm-scroller': {
        fontFamily: selectedFontFamily(),
        lineHeight: '1.45',
        overflow: 'auto',
      },
      '.cm-gutter, .cm-content': {
        minHeight: '100%',
      },
      '.cm-content': {
        caretColor: theme.accent,
      },
      '.cm-cursor': {
        borderLeftColor: theme.accent,
      },
      '.cm-selectionBackground, ::selection': {
        backgroundColor: `${theme.selection} !important`,
      },
      '.cm-gutters': {
        backgroundColor: theme.panel,
        color: theme.muted,
        borderRightColor: theme.line,
      },
      '.cm-activeLine, .cm-activeLineGutter': {
        backgroundColor: theme.panel,
      },
      '.cm-focused': {
        outline: 'none',
      },
    }, { dark: appearanceMode === 'dark' }),
    syntaxHighlighting(HighlightStyle.define([
      { tag: tags.keyword, color: theme.keyword },
      { tag: tags.string, color: theme.string },
      { tag: tags.number, color: theme.number },
      { tag: tags.comment, color: theme.comment },
      { tag: tags.variableName, color: theme.variable },
      { tag: tags.invalid, color: theme.error },
    ])),
  ];
}

function editorExtensions() {
  return [
    basicSetup,
    EditorView.updateListener.of(update => {
      const activeBuffer = getActiveBuffer();
      if (activeBuffer) {
        activeBuffer.state = update.state;
      }
      if (update.docChanged) {
        persistDraft();
        renderBuffers();
        renderTree();
      }
    }),
    themeCompartment.of(themeExtension(selectedTheme())),
  ];
}

const editorView = new EditorView({
  parent: nodes.editor,
  state: EditorState.create({
    doc: '',
    extensions: editorExtensions(),
  }),
});

function setStatus(message, { error = false } = {}) {
  if (error) {
    console.error(message);
  } else {
    console.log(message);
  }
}

function draftKey(path) {
  return `olc-edit-draft:${path}`;
}

function getActiveBuffer() {
  return activePath ? openBuffers.get(activePath) ?? null : null;
}

function currentContent() {
  return editorView.state.doc.toString();
}

function bufferContent(buffer) {
  return buffer.state.doc.toString();
}

function bufferDirty(buffer) {
  return bufferContent(buffer) !== buffer.savedContent;
}

function createBuffer({ path, name, content, mtimeMs }) {
  const draft = window.localStorage.getItem(draftKey(path));
  return {
    path,
    name,
    mtimeMs,
    savedContent: content,
    restoredDraft: draft !== null,
    state: EditorState.create({
      doc: draft ?? content,
      extensions: editorExtensions(),
    }),
  };
}

function switchToBuffer(path) {
  const buffer = openBuffers.get(path);
  if (!buffer) {
    return;
  }

  activePath = path;
  editorView.setState(buffer.state);
  document.title = `${buffer.name} - Editor`;
  renderBuffers();
  renderTree();
  editorView.focus();
}

function bufferStateLabel(buffer) {
  if (buffer.path === activePath) {
    return bufferDirty(buffer) ? '●' : '◆';
  }
  return bufferDirty(buffer) ? '○' : '◇';
}

function nextBufferPathAfter(path) {
  const paths = Array.from(openBuffers.keys());
  const index = paths.indexOf(path);
  if (index === -1) {
    return paths[0] ?? null;
  }
  return paths[index + 1] ?? paths[index - 1] ?? null;
}

function closeBuffer(path) {
  const buffer = openBuffers.get(path);
  if (!buffer) {
    return;
  }

  if (bufferDirty(buffer) && !window.confirm(`Close ${buffer.name} with unsaved edits?`)) {
    return;
  }

  const nextPath = path === activePath ? nextBufferPathAfter(path) : activePath;
  openBuffers.delete(path);
  if (path === activePath) {
    activePath = null;
    if (nextPath && openBuffers.has(nextPath)) {
      switchToBuffer(nextPath);
    } else {
      editorView.setState(EditorState.create({
        doc: '',
        extensions: editorExtensions(),
      }));
      document.title = 'Editor';
    }
  }
  renderBuffers();
  renderTree();
}

function renderBuffers() {
  const buffers = Array.from(openBuffers.values());
  if (buffers.length === 0) {
    nodes.buffers.replaceChildren();
    return;
  }

  nodes.buffers.replaceChildren(...buffers.map(buffer => {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'buffer-row';
    row.dataset.active = buffer.path === activePath ? 'true' : 'false';
    row.title = buffer.path;
    row.setAttribute('role', 'listitem');
    row.innerHTML = '<span class="buffer-name"></span><span class="buffer-state"></span><button class="buffer-close" type="button" title="Close">×</button>';
    row.querySelector('.buffer-name').textContent = buffer.name;
    row.querySelector('.buffer-state').title = buffer.path === activePath
      ? bufferDirty(buffer) ? 'selected with unsaved edits' : 'selected'
      : bufferDirty(buffer) ? 'open with unsaved edits' : 'open';
    row.querySelector('.buffer-state').textContent = bufferStateLabel(buffer);
    row.querySelector('.buffer-close').addEventListener('click', event => {
      event.stopPropagation();
      closeBuffer(buffer.path);
    });
    row.addEventListener('click', () => switchToBuffer(buffer.path));
    return row;
  }));
}

function reconfigureOpenBufferThemes() {
  const effect = themeCompartment.reconfigure(themeExtension(selectedTheme()));
  for (const buffer of openBuffers.values()) {
    const transaction = buffer.state.update({ effects: effect });
    buffer.state = transaction.state;
  }
  if (activePath) {
    switchToBuffer(activePath);
  }
}

function persistDraft() {
  const activeBuffer = getActiveBuffer();
  if (!activeBuffer) {
    return;
  }
  const content = currentContent();
  if (content === activeBuffer.savedContent) {
    window.localStorage.removeItem(draftKey(activeBuffer.path));
    return;
  }
  window.localStorage.setItem(draftKey(activeBuffer.path), content);
}

function applyTheme() {
  const theme = selectedTheme();
  document.documentElement.style.setProperty('--editor-bg', theme.background);
  document.documentElement.style.setProperty('--editor-fg', theme.foreground);
  document.documentElement.style.setProperty('--editor-muted', theme.muted);
  document.documentElement.style.setProperty('--editor-line', theme.line);
  document.documentElement.style.setProperty('--editor-accent', theme.accent);
  document.documentElement.style.setProperty('--editor-panel', theme.panel);
  document.documentElement.style.setProperty('--editor-panel-fg', theme.panelForeground);
  document.documentElement.style.setProperty('--editor-error', theme.error);
  document.documentElement.style.setProperty('--editor-font', selectedFontFamily());
  reconfigureOpenBufferThemes();
}

async function fetchJson(path, options = {}) {
  const response = await fetch(path, {
    cache: 'no-store',
    credentials: 'same-origin',
    ...options,
  });
  const body = await response.json();
  if (!response.ok || body.ok === false) {
    throw new Error(body.error || `request failed with ${response.status}`);
  }
  return body;
}

function renderTree() {
  const filter = nodes.filter.value.trim().toLowerCase();
  const visible = entries.filter(entry => !filter || entry.name.toLowerCase().includes(filter));
  nodes.tree.replaceChildren(...visible.map(entry => {
    const buffer = openBuffers.get(entry.path);
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'tree-row';
    row.dataset.selected = entry.path === activePath ? 'true' : 'false';
    row.dataset.kind = entry.kind;
    row.innerHTML = `<span>${entry.kind === 'directory' ? '/' : ''}</span><span class="tree-name"></span><span class="tree-state"></span>`;
    row.querySelector('.tree-name').textContent = entry.name;
    const treeState = row.querySelector('.tree-state');
    treeState.textContent = buffer ? bufferStateLabel(buffer) : '';
    treeState.title = buffer
      ? buffer.path === activePath
        ? bufferDirty(buffer) ? 'selected with unsaved edits' : 'selected'
        : bufferDirty(buffer) ? 'open with unsaved edits' : 'open'
      : '';
    row.addEventListener('click', () => {
      if (entry.kind === 'directory') {
        void loadDirectory(entry.path);
      } else if (entry.kind === 'file' || entry.kind === 'symlink') {
        void openFile(entry.path);
      }
    });
    return row;
  }));
}

async function loadDirectory(path) {
  try {
    const body = await fetchJson(`/api/edit/list?path=${encodeURIComponent(path)}`);
    currentDirectory = body.path;
    nodes.cwd.textContent = currentDirectory;
    entries = [];
    if (body.parent) {
      entries.push({ name: '..', path: body.parent, kind: 'directory' });
    }
    entries.push(...body.entries);
    renderTree();
    setStatus(`Browsing ${currentDirectory}`);
  } catch (error) {
    setStatus(error.message, { error: true });
  }
}

async function openFile(path) {
  try {
    if (openBuffers.has(path)) {
      switchToBuffer(path);
      setStatus(`Switched to ${path}`);
      return;
    }

    const body = await fetchJson(`/api/edit/file?path=${encodeURIComponent(path)}`);
    const buffer = createBuffer(body);
    openBuffers.set(buffer.path, buffer);
    switchToBuffer(buffer.path);
    setStatus(buffer.restoredDraft ? `Restored unsaved draft for ${buffer.path}` : `Opened ${buffer.path}`);
  } catch (error) {
    setStatus(error.message, { error: true });
  }
}

async function saveFile() {
  const activeBuffer = getActiveBuffer();
  if (!activeBuffer) {
    return;
  }

  try {
    await fetchJson('/api/edit/file', {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ path: activeBuffer.path, content: currentContent() }),
    });
    activeBuffer.savedContent = currentContent();
    activeBuffer.state = editorView.state;
    window.localStorage.removeItem(draftKey(activeBuffer.path));
    renderBuffers();
    renderTree();
    setStatus(`Saved ${activeBuffer.path}`);
  } catch (error) {
    setStatus(error.message, { error: true });
  }
}

function applySystemStatus(status) {
  if (status?.appearance?.mode === 'light' || status?.appearance?.mode === 'dark') {
    appearanceMode = status.appearance.mode;
  }
  if (status?.terminal?.font && status?.terminal?.colorScheme) {
    editorPreferences = {
      font: status.terminal.font,
      colorScheme: status.terminal.colorScheme,
    };
  }
  applyTheme();
}

async function syncSystemStatus() {
  try {
    const response = await fetch('/api/system/events', {
      cache: 'no-store',
      credentials: 'same-origin',
    });
    if (!response.ok || !response.body) {
      return;
    }

    const reader = response.body.getReader();
    const textDecoder = new TextDecoder();
    let buffer = '';
    for (;;) {
      const { done, value } = await reader.read();
      if (done) {
        return;
      }

      buffer += textDecoder.decode(value, { stream: true });
      const events = buffer.split('\n\n');
      buffer = events.pop() || '';
      for (const event of events) {
        if (!event.includes('event: status')) {
          continue;
        }
        const dataLine = event.split('\n').find(line => line.startsWith('data: '));
        if (dataLine) {
          applySystemStatus(JSON.parse(dataLine.slice('data: '.length)));
        }
      }
    }
  } catch {
    applyTheme();
  }
}

parseInitialLocation();
applyTheme();
nodes.filter.addEventListener('input', renderTree);
window.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
    event.preventDefault();
    void saveFile();
  }
});
void syncSystemStatus();
void loadDirectory(currentDirectory).then(() => {
  if (initialFile) {
    void openFile(initialFile);
  }
});
