import { EditorView, basicSetup } from 'codemirror';
import { Compartment, EditorState } from '@codemirror/state';
import { defaultTerminalPreferences } from './terminal-options.mjs';
import { languageExtensionForPath, languageNameForPath } from './editor-languages.mjs';
import {
  createThemeExtension,
  resolveEditorFontFamily,
  resolveEditorTheme,
} from './editor-theme.mjs';

const nodes = {
  buffers: document.getElementById('buffers'),
  cwd: document.getElementById('cwd'),
  editor: document.getElementById('editor'),
  filter: document.getElementById('filter'),
  language: document.getElementById('editor-language'),
  reload: document.getElementById('reload-file'),
  save: document.getElementById('save-file'),
  status: document.getElementById('editor-status'),
  title: document.getElementById('editor-title'),
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
  return resolveEditorTheme(editorPreferences, appearanceMode);
}

function selectedFontFamily() {
  return resolveEditorFontFamily(editorPreferences);
}

function themeExtension(theme) {
  return createThemeExtension(theme, appearanceMode, selectedFontFamily());
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
        updateEditorHeader();
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
  nodes.status.textContent = message;
  nodes.status.dataset.error = error ? 'true' : 'false';
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
    languageName: languageNameForPath(path),
    path,
    name,
    mtimeMs,
    savedContent: content,
    restoredDraft: draft !== null,
    state: EditorState.create({
      doc: draft ?? content,
      extensions: [
        ...editorExtensions(),
        languageExtensionForPath(path),
      ],
    }),
  };
}

function updateEditorHeader() {
  const buffer = getActiveBuffer();
  nodes.title.textContent = buffer ? buffer.path : 'No file open';
  nodes.language.textContent = buffer ? buffer.languageName : 'Plain text';
  nodes.reload.disabled = !buffer;
  nodes.save.disabled = !buffer;
}

function switchToBuffer(path) {
  const buffer = openBuffers.get(path);
  if (!buffer) {
    return;
  }

  activePath = path;
  editorView.setState(buffer.state);
  document.title = `${buffer.name} - Editor`;
  updateEditorHeader();
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

function clearActiveEditor() {
  editorView.setState(EditorState.create({
    doc: '',
    extensions: editorExtensions(),
  }));
  document.title = 'Editor';
  updateEditorHeader();
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
      clearActiveEditor();
    }
  }
  renderBuffers();
  renderTree();
}

function createBufferRow(buffer) {
  const row = document.createElement('div');
  row.className = 'buffer-row';
  row.dataset.active = buffer.path === activePath ? 'true' : 'false';

  const openButton = document.createElement('button');
  openButton.type = 'button';
  openButton.className = 'buffer-open';
  openButton.title = buffer.path;
  openButton.setAttribute('role', 'listitem');
  openButton.innerHTML = '<span class="buffer-name"></span><span class="buffer-state"></span>';
  openButton.querySelector('.buffer-name').textContent = buffer.name;
  openButton.querySelector('.buffer-state').title = buffer.path === activePath
    ? bufferDirty(buffer) ? 'selected with unsaved edits' : 'selected'
    : bufferDirty(buffer) ? 'open with unsaved edits' : 'open';
  openButton.querySelector('.buffer-state').textContent = bufferStateLabel(buffer);
  openButton.addEventListener('click', () => switchToBuffer(buffer.path));

  const closeButton = document.createElement('button');
  closeButton.type = 'button';
  closeButton.className = 'buffer-close';
  closeButton.title = `Close ${buffer.name}`;
  closeButton.textContent = '×';
  closeButton.addEventListener('click', () => closeBuffer(buffer.path));

  row.append(openButton, closeButton);
  return row;
}

function renderBuffers() {
  const buffers = Array.from(openBuffers.values());
  if (buffers.length === 0) {
    nodes.buffers.replaceChildren();
    return;
  }

  nodes.buffers.replaceChildren(...buffers.map(createBufferRow));
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

async function reloadFile() {
  const activeBuffer = getActiveBuffer();
  if (!activeBuffer) {
    return;
  }

  if (bufferDirty(activeBuffer) && !window.confirm(`Reload ${activeBuffer.name} and discard unsaved edits?`)) {
    return;
  }

  window.localStorage.removeItem(draftKey(activeBuffer.path));
  openBuffers.delete(activeBuffer.path);
  await openFile(activeBuffer.path);
  setStatus(`Reloaded ${activeBuffer.path}`);
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
    updateEditorHeader();
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
updateEditorHeader();
nodes.filter.addEventListener('input', renderTree);
nodes.reload.addEventListener('click', () => {
  void reloadFile();
});
nodes.save.addEventListener('click', () => {
  void saveFile();
});
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
