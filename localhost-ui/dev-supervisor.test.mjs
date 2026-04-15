import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { createSourcePreviewSupervisor, selectRuntimePaths } from './dev-supervisor.mjs';

function makeSourceTree() {
  const root = mkdtempSync(join(tmpdir(), 'ol-c-source-preview-test.'));
  mkdirSync(join(root, 'localhost-ui'), { recursive: true });
  writeFileSync(join(root, 'localhost-ui', 'server.mjs'), '');
  return root;
}

test('selects source server without owning terminal assets when /source-style tree exists', () => {
  const root = makeSourceTree();

  try {
    const paths = selectRuntimePaths({ OLC_SOURCE_ROOT: root });

    assert.equal(paths.mode, 'source');
    assert.equal(paths.serverPath, join(root, 'localhost-ui', 'server.mjs'));
    assert.deepEqual(paths.watchPaths, [
      join(root, 'localhost-ui'),
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('falls back to packaged server when source tree is absent', () => {
  const root = mkdtempSync(join(tmpdir(), 'ol-c-source-preview-empty.'));

  try {
    const paths = selectRuntimePaths({
      OLC_SOURCE_ROOT: root,
    });

    assert.equal(paths.mode, 'store');
    assert.match(paths.serverPath, /\/localhost-ui\/server\.mjs$/);
    assert.deepEqual(paths.watchPaths, []);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('debounces file events and restarts after the old server exits', async () => {
  const root = makeSourceTree();
  const spawned = [];
  const watchCallbacks = [];

  function spawnProcess(command, args, options) {
    const child = new EventEmitter();
    child.command = command;
    child.args = args;
    child.options = options;
    child.killed = false;
    child.kill = signal => {
      child.killed = true;
      child.killSignal = signal;
      queueMicrotask(() => child.emit('exit', null, signal));
    };
    spawned.push(child);
    return child;
  }

  function watchPath(path, options, callback) {
    watchCallbacks.push(callback);
    return { close() {} };
  }

  try {
    const serverPath = join(root, 'localhost-ui', 'server.mjs');
    const supervisor = createSourcePreviewSupervisor({
      env: {},
      nodeBin: '/bin/node',
      restartDelayMs: 5,
      selectPaths: () => ({
        mode: 'source',
        serverPath,
        watchPaths: [ join(root, 'localhost-ui') ],
      }),
      spawnProcess,
      watchPath,
      log: { log() {}, error() {} },
    });

    supervisor.start();
    assert.equal(spawned.length, 1);
    assert.equal(watchCallbacks.length, 1);
    assert.equal(spawned[0].args[0], serverPath);
    assert.equal(spawned[0].options.env.OLC_TERMINAL_CLIENT_JS, undefined);

    watchCallbacks[0]();
    watchCallbacks[0]();
    await new Promise(resolve => setTimeout(resolve, 25));

    assert.equal(spawned.length, 2);
    assert.equal(spawned[0].killSignal, 'SIGTERM');
    assert.equal(spawned[1].args[0], serverPath);

    supervisor.stop();
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('polling fallback restarts when file events are missed', async () => {
  const root = makeSourceTree();
  const spawned = [];
  const intervalCallbacks = [];
  let stamp = 'before';

  function spawnProcess(command, args, options) {
    const child = new EventEmitter();
    child.command = command;
    child.args = args;
    child.options = options;
    child.killed = false;
    child.kill = signal => {
      child.killed = true;
      child.killSignal = signal;
      queueMicrotask(() => child.emit('exit', null, signal));
    };
    spawned.push(child);
    return child;
  }

  function watchPath() {
    return { close() {} };
  }

  function setWatchInterval(callback) {
    intervalCallbacks.push(callback);
    return callback;
  }

  try {
    const serverPath = join(root, 'localhost-ui', 'server.mjs');
    const supervisor = createSourcePreviewSupervisor({
      env: {},
      nodeBin: '/bin/node',
      restartDelayMs: 5,
      pollIntervalMs: 5,
      selectPaths: () => ({
        mode: 'source',
        serverPath,
        watchPaths: [ join(root, 'localhost-ui') ],
      }),
      spawnProcess,
      watchPath,
      scanPath: () => stamp,
      setWatchInterval,
      clearWatchInterval() {},
      log: { log() {}, error() {} },
    });

    supervisor.start();
    assert.equal(spawned.length, 1);
    assert.equal(intervalCallbacks.length, 1);

    stamp = 'after';
    intervalCallbacks[0]();
    await new Promise(resolve => setTimeout(resolve, 25));

    assert.equal(spawned.length, 2);
    assert.equal(spawned[0].killSignal, 'SIGTERM');
    assert.equal(spawned[1].args[0], serverPath);

    supervisor.stop();
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
