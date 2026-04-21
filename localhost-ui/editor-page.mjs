import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, resolve } from 'node:path';

const maxEditableBytes = 2 * 1024 * 1024;

function setNoStore(res) {
  res.setHeader('cache-control', 'no-store');
}

function jsonError(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function writeJson(res, statusCode, payload, headers = {}) {
  setNoStore(res);
  res.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    ...headers,
  });
  res.end(JSON.stringify(payload));
}

function parseRequestPath(value, fallback = process.cwd()) {
  const raw = String(value || fallback);
  if (raw.includes('\0')) {
    throw jsonError('path must not contain NUL bytes');
  }

  if (!isAbsolute(raw)) {
    throw jsonError('path must be absolute');
  }

  return resolve(raw);
}

function entryKind(dirent) {
  if (dirent.isDirectory()) {
    return 'directory';
  }
  if (dirent.isSymbolicLink()) {
    return 'symlink';
  }
  if (dirent.isFile()) {
    return 'file';
  }
  return 'other';
}

async function readJsonBody(req) {
  return new Promise((resolveBody, reject) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', chunk => {
      body += chunk;
      if (body.length > maxEditableBytes + 4096) {
        reject(jsonError('request body is too large', 413));
        req.destroy();
      }
    });
    req.on('error', reject);
    req.on('end', () => {
      try {
        resolveBody(body.trim() ? JSON.parse(body) : {});
      } catch {
        reject(jsonError('request body must be valid JSON'));
      }
    });
  });
}

export function editorHtml() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Editor</title>
    <style>
      :root {
        color-scheme: light dark;
        --editor-bg: #fdf6e3;
        --editor-fg: #657b83;
        --editor-muted: #586e75;
        --editor-line: #eee8d5;
        --editor-accent: #268bd2;
        --editor-panel: #fbfbf8;
        --editor-panel-fg: #181a1f;
        --editor-error: #dc322f;
        --editor-font: "DejaVu Sans Mono", "DejaVu Sans Mono Book", monospace;
        background: var(--editor-bg);
        color: var(--editor-fg);
        font-family: var(--editor-font);
        letter-spacing: 0;
      }

      * {
        box-sizing: border-box;
      }

      html,
      body {
        width: 100%;
        height: 100%;
        margin: 0;
        padding: 0;
      }

      body {
        overflow: hidden;
        background: var(--editor-bg);
        color: var(--editor-fg);
      }

      #app {
        display: grid;
        grid-template-columns: minmax(15rem, 24rem) minmax(0, 1fr);
        width: 100%;
        height: 100%;
        min-height: 0;
        overflow: hidden;
      }

      #sidebar {
        min-width: 0;
        min-height: 0;
        border-right: 1px solid var(--editor-line);
        background: var(--editor-panel);
        color: var(--editor-panel-fg);
        display: grid;
        grid-template-rows: auto auto auto minmax(0, 1fr);
      }

      #toolbar {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        min-width: 0;
        min-height: 2.75rem;
        padding: 0.5rem;
        border-bottom: 1px solid var(--editor-line);
      }

      #filter {
        width: 100%;
        min-width: 0;
        height: 2rem;
        border: 1px solid var(--editor-line);
        border-radius: 6px;
        background: var(--editor-bg);
        color: var(--editor-fg);
        font: 14px/1.2 var(--editor-font);
        padding: 0 0.5rem;
      }

      #cwd {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        padding: 0.5rem;
        border-bottom: 1px solid var(--editor-line);
        color: var(--editor-muted);
        font-size: 0.85rem;
      }

      #buffers {
        display: grid;
        gap: 0.25rem;
        max-height: 32vh;
        overflow: auto;
        padding: 0.35rem;
        border-bottom: 1px solid var(--editor-line);
      }

      .buffer-row {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto auto;
        align-items: center;
        gap: 0.45rem;
        width: 100%;
        min-height: 1.85rem;
        border: 0;
        border-radius: 6px;
        background: transparent;
        color: inherit;
        font: 14px/1.2 var(--editor-font);
        text-align: left;
        padding: 0 0.4rem;
      }

      .buffer-row:hover,
      .buffer-row:focus-visible {
        background: var(--editor-line);
        outline: 0;
      }

      .buffer-row[data-active="true"] {
        background: var(--editor-accent);
        color: var(--editor-bg);
      }

      .buffer-name,
      .tree-name {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .buffer-state,
      .tree-state {
        font: 14px/1 var(--editor-font);
        opacity: 0.82;
        white-space: nowrap;
      }

      .buffer-close {
        width: 1.5rem;
        height: 1.5rem;
        border: 0;
        border-radius: 6px;
        background: transparent;
        color: inherit;
        font: 15px/1 system-ui, sans-serif;
        padding: 0;
      }

      .buffer-close:hover,
      .buffer-close:focus-visible {
        background: color-mix(in srgb, currentColor 16%, transparent);
        outline: 0;
      }

      #tree {
        overflow: auto;
        padding: 0.35rem;
      }

      .tree-row {
        display: grid;
        grid-template-columns: 1.25rem minmax(0, 1fr) auto;
        align-items: center;
        gap: 0.35rem;
        width: 100%;
        min-height: 1.85rem;
        border: 0;
        border-radius: 6px;
        background: transparent;
        color: inherit;
        font: 14px/1.2 var(--editor-font);
        text-align: left;
        padding: 0 0.4rem;
      }

      .tree-row:hover,
      .tree-row:focus-visible {
        background: var(--editor-line);
        outline: 0;
      }

      .tree-row[data-selected="true"] {
        background: var(--editor-accent);
        color: var(--editor-bg);
      }

      #main {
        min-width: 0;
        min-height: 0;
        display: grid;
        grid-template-rows: minmax(0, 1fr);
        background: var(--editor-bg);
        overflow: hidden;
      }

      #editor {
        min-width: 0;
        min-height: 0;
        width: 100%;
        height: 100%;
        overflow: hidden;
      }

      @media (max-width: 44rem) {
        #app {
          grid-template-columns: 1fr;
          grid-template-rows: minmax(12rem, 35%) minmax(0, 1fr);
        }

        #sidebar {
          border-right: 0;
          border-bottom: 1px solid var(--editor-line);
        }
      }
    </style>
  </head>
  <body>
    <div id="app">
      <aside id="sidebar">
        <div id="toolbar">
          <input id="filter" type="search" placeholder="Filter files" autocomplete="off" />
        </div>
        <div id="cwd"></div>
        <div id="buffers" role="list" aria-label="Open files"></div>
        <div id="tree" role="listbox" aria-label="Files"></div>
      </aside>
      <main id="main">
        <div id="editor"></div>
      </main>
    </div>
    <script src="/edit/assets/editor.js"></script>
  </body>
</html>`;
}

export async function handleEditorApi(req, res, reqUrl) {
  try {
    if (reqUrl.pathname === '/api/edit/list') {
      if (req.method !== 'GET') {
        writeJson(res, 405, { ok: false, error: 'method not allowed' }, { allow: 'GET' });
        return;
      }

      const targetPath = parseRequestPath(reqUrl.searchParams.get('path'));
      const entries = await readdir(targetPath, { withFileTypes: true });
      const rows = entries
        .map(entry => ({
          name: entry.name,
          path: resolve(targetPath, entry.name),
          kind: entryKind(entry),
        }))
        .sort((a, b) => {
          if (a.kind === 'directory' && b.kind !== 'directory') return -1;
          if (a.kind !== 'directory' && b.kind === 'directory') return 1;
          return a.name.localeCompare(b.name);
        });

      writeJson(res, 200, {
        ok: true,
        path: targetPath,
        parent: dirname(targetPath) === targetPath ? null : dirname(targetPath),
        entries: rows,
      });
      return;
    }

    if (reqUrl.pathname === '/api/edit/file' && req.method === 'GET') {
      const targetPath = parseRequestPath(reqUrl.searchParams.get('path'));
      const info = await stat(targetPath);
      if (!info.isFile()) {
        throw jsonError('path is not a regular file', 400);
      }
      if (info.size > maxEditableBytes) {
        throw jsonError('file is too large for the basic editor proof', 413);
      }

      writeJson(res, 200, {
        ok: true,
        path: targetPath,
        name: basename(targetPath),
        content: await readFile(targetPath, 'utf8'),
        mtimeMs: info.mtimeMs,
        size: info.size,
      });
      return;
    }

    if (reqUrl.pathname === '/api/edit/file' && req.method === 'PUT') {
      const body = await readJsonBody(req);
      const targetPath = parseRequestPath(body.path);
      if (typeof body.content !== 'string') {
        throw jsonError('content must be a string');
      }
      if (Buffer.byteLength(body.content, 'utf8') > maxEditableBytes) {
        throw jsonError('content is too large for the basic editor proof', 413);
      }

      await writeFile(targetPath, body.content, 'utf8');
      const info = await stat(targetPath);
      writeJson(res, 200, {
        ok: true,
        path: targetPath,
        mtimeMs: info.mtimeMs,
        size: info.size,
      });
      return;
    }

    writeJson(res, 404, { ok: false, error: 'editor API endpoint was not found' });
  } catch (error) {
    writeJson(res, error.statusCode ?? 500, {
      ok: false,
      error: error.code === 'EACCES' ? 'permission denied' : error.message,
    });
  }
}
