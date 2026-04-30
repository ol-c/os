import { execFile } from 'node:child_process';
import { dirname, isAbsolute, resolve } from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const maxEditableBytes = 2 * 1024 * 1024;
const workerPath = fileURLToPath(new URL('./editor-worker.mjs', import.meta.url));

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
        --editor-font: "Noto Sans Mono", "Noto Sans CJK SC", "Noto Sans CJK TC", "Noto Sans CJK HK", "Noto Sans CJK JP", "Noto Sans CJK KR", "Noto Color Emoji", monospace;
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

      #toolbar-actions {
        display: flex;
        align-items: center;
        gap: 0.45rem;
      }

      .toolbar-button {
        height: 2rem;
        border: 1px solid var(--editor-line);
        border-radius: 6px;
        background: var(--editor-bg);
        color: var(--editor-fg);
        font: 13px/1.2 var(--editor-font);
        padding: 0 0.75rem;
      }

      .toolbar-button:hover,
      .toolbar-button:focus-visible {
        background: var(--editor-line);
        outline: 0;
      }

      .toolbar-button:disabled {
        opacity: 0.55;
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

      #editor-meta {
        display: grid;
        gap: 0.2rem;
        padding: 0.5rem;
        border-bottom: 1px solid var(--editor-line);
        background: color-mix(in srgb, var(--editor-panel) 72%, var(--editor-bg));
      }

      #editor-title {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: 0.88rem;
      }

      #editor-status-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        min-width: 0;
      }

      #editor-status {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: 0.8rem;
        color: var(--editor-muted);
      }

      #editor-status[data-error="true"] {
        color: var(--editor-error);
      }

      #editor-language {
        flex: 0 0 auto;
        border: 1px solid var(--editor-line);
        border-radius: 999px;
        padding: 0.1rem 0.45rem;
        font-size: 0.72rem;
        color: var(--editor-panel-fg);
        background: var(--editor-bg);
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
        grid-template-columns: minmax(0, 1fr) auto;
        align-items: center;
        gap: 0.45rem;
        min-height: 1.85rem;
        border-radius: 6px;
      }

      .buffer-open {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        align-items: center;
        gap: 0.45rem;
        min-height: 1.85rem;
        width: 100%;
        border: 0;
        border-radius: 6px;
        background: transparent;
        color: inherit;
        font: 14px/1.2 var(--editor-font);
        text-align: left;
        padding: 0 0.4rem;
      }

      .buffer-open:hover,
      .buffer-open:focus-visible,
      .buffer-close:hover,
      .buffer-close:focus-visible {
        background: var(--editor-line);
        outline: 0;
      }

      .buffer-row[data-active="true"] .buffer-open,
      .buffer-row[data-active="true"] .buffer-close {
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
        font: 15px/1 "Noto Sans", "Noto Sans CJK SC", "Noto Sans CJK TC", "Noto Sans CJK HK", "Noto Sans CJK JP", "Noto Sans CJK KR", "Noto Color Emoji", sans-serif;
        padding: 0;
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
          <div id="toolbar-actions">
            <button id="reload-file" class="toolbar-button" type="button" disabled>Reload</button>
            <button id="save-file" class="toolbar-button" type="button" disabled>Save</button>
          </div>
        </div>
        <div id="cwd"></div>
        <div id="editor-meta">
          <div id="editor-title">No file open</div>
          <div id="editor-status-row">
            <div id="editor-status" data-error="false">Ready</div>
            <div id="editor-language">Plain text</div>
          </div>
        </div>
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

async function runEditorWorker(editorUser, args, options = {}) {
  const execPath = options.execPath ?? process.execPath;
  const worker = options.workerPath ?? workerPath;
  const workerCwd = options.workerCwd ?? '/';
  const systemdRunPath =
    options.systemdRunPath
    ?? process.env.OLC_SYSTEMD_RUN
    ?? (process.env.OLC_LOGINCTL ? `${dirname(process.env.OLC_LOGINCTL)}/systemd-run` : null)
    ?? '/run/current-system/sw/bin/systemd-run';
  const spawnOptions = options.spawnOptions ?? {};
  const workerEnv = {
    ...process.env,
    HOME: editorUser.home,
    USER: editorUser.name,
    LOGNAME: editorUser.name,
  };

  try {
    const { stdout } = await execFileAsync(execPath, [ worker, ...args ], {
      timeout: 4000,
      uid: Number(editorUser.uid),
      gid: Number(editorUser.gid),
      env: workerEnv,
      cwd: workerCwd,
      maxBuffer: maxEditableBytes * 4,
      ...spawnOptions,
    });

    return JSON.parse(stdout);
  } catch (error) {
    if (
      (error.code !== 'EACCES' && error.code !== 'EPERM')
      || Number(process.getuid?.()) !== 0
    ) {
      throw error;
    }

    const systemdArgs = [
      '--quiet',
      '--pipe',
      '--wait',
      '--collect',
      '--service-type=exec',
      `--uid=${editorUser.name}`,
      `--gid=${editorUser.gid}`,
      '--same-dir',
      `--setenv=HOME=${editorUser.home}`,
      `--setenv=USER=${editorUser.name}`,
      `--setenv=LOGNAME=${editorUser.name}`,
      execPath,
      worker,
      ...args,
    ];

    const { stdout } = await execFileAsync(systemdRunPath, systemdArgs, {
      timeout: 6000,
      env: workerEnv,
      cwd: workerCwd,
      maxBuffer: maxEditableBytes * 4,
      ...spawnOptions,
    });

    return JSON.parse(stdout);
  }
}

export async function handleEditorApi(req, res, reqUrl, options = {}) {
  const getEditorUser = options.getEditorUser;

  try {
    if (!getEditorUser) {
      throw jsonError('editor user resolver is required', 500);
    }

    const editorUser = await getEditorUser();
    if (!editorUser) {
      throw jsonError('editor is unavailable until a signed-in user session exists', 409);
    }

    if (reqUrl.pathname === '/api/edit/list') {
      if (req.method !== 'GET') {
        writeJson(res, 405, { ok: false, error: 'method not allowed' }, { allow: 'GET' });
        return;
      }

      const targetPath = parseRequestPath(reqUrl.searchParams.get('path'));
      writeJson(res, 200, await runEditorWorker(editorUser, [ 'list', targetPath ], options));
      return;
    }

    if (reqUrl.pathname === '/api/edit/file' && req.method === 'GET') {
      const targetPath = parseRequestPath(reqUrl.searchParams.get('path'));
      writeJson(res, 200, await runEditorWorker(editorUser, [ 'read', targetPath ], options));
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

      writeJson(res, 200, await runEditorWorker(editorUser, [ 'write', targetPath, body.content ], options));
      return;
    }

    writeJson(res, 404, { ok: false, error: 'editor API endpoint was not found' });
  } catch (error) {
    const stderr = String(error.stderr || '');
    let payload = { error: error.message };

    try {
      if (stderr.trim()) {
        payload = JSON.parse(stderr);
      }
    } catch {
      payload = { error: stderr.trim() || error.message };
    }

    const inferredStatus =
      payload.code === 'EACCES' ? 403 :
      payload.code === 'EINVAL' ? 400 :
      payload.code === 'EFBIG' ? 413 :
      500;
    writeJson(res, error.statusCode ?? inferredStatus, {
      ok: false,
      error: payload.code === 'EACCES' ? 'permission denied' : payload.error,
    });
  }
}
