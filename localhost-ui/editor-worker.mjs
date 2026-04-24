import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, resolve } from 'node:path';

const maxEditableBytes = 2 * 1024 * 1024;

function jsonError(message, code = 'EINVAL') {
  const error = new Error(message);
  error.code = code;
  return error;
}

function parsePath(value) {
  const raw = String(value || '');
  if (!raw || raw.includes('\0')) {
    throw jsonError('path must be an absolute path');
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

async function listPath(targetPath) {
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

  return {
    ok: true,
    path: targetPath,
    parent: dirname(targetPath) === targetPath ? null : dirname(targetPath),
    entries: rows,
  };
}

async function readPath(targetPath) {
  const info = await stat(targetPath);
  if (!info.isFile()) {
    throw jsonError('path is not a regular file');
  }
  if (info.size > maxEditableBytes) {
    throw jsonError('file is too large for the basic editor proof', 'EFBIG');
  }

  return {
    ok: true,
    path: targetPath,
    name: basename(targetPath),
    content: await readFile(targetPath, 'utf8'),
    mtimeMs: info.mtimeMs,
    size: info.size,
  };
}

async function writePath(targetPath, content) {
  if (typeof content !== 'string') {
    throw jsonError('content must be a string');
  }
  if (Buffer.byteLength(content, 'utf8') > maxEditableBytes) {
    throw jsonError('content is too large for the basic editor proof', 'EFBIG');
  }

  await writeFile(targetPath, content, 'utf8');
  const info = await stat(targetPath);
  return {
    ok: true,
    path: targetPath,
    mtimeMs: info.mtimeMs,
    size: info.size,
  };
}

async function main() {
  const [ action, rawPath, content = '' ] = process.argv.slice(2);
  const targetPath = parsePath(rawPath);

  let payload;
  if (action === 'list') {
    payload = await listPath(targetPath);
  } else if (action === 'read') {
    payload = await readPath(targetPath);
  } else if (action === 'write') {
    payload = await writePath(targetPath, content);
  } else {
    throw jsonError(`unknown editor action: ${action}`);
  }

  process.stdout.write(JSON.stringify(payload));
}

main().catch(error => {
  process.stderr.write(JSON.stringify({
    error: error.message,
    code: error.code || 'EUNKNOWN',
  }));
  process.exit(1);
});
