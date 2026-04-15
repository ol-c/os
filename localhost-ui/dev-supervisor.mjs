import { existsSync, readdirSync, statSync, watch } from 'node:fs';
import { dirname } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const defaultRestartDelayMs = 150;
const defaultPollIntervalMs = 1000;
const defaultSourceRoot = '/source';
const storeRoot = dirname(fileURLToPath(import.meta.url));

function pathExists(path) {
  try {
    return existsSync(path);
  } catch {
    return false;
  }
}

function sourcePath(sourceRoot, path) {
  return `${sourceRoot}${path}`;
}

function scanWatchStamp(path) {
  let stamp = '';

  function scan(currentPath) {
    let stats;
    try {
      stats = statSync(currentPath);
    } catch {
      stamp += `${currentPath}:missing;`;
      return;
    }

    stamp += `${currentPath}:${stats.mtimeMs}:${stats.size};`;
    if (!stats.isDirectory()) {
      return;
    }

    let entries;
    try {
      entries = readdirSync(currentPath, { withFileTypes: true });
    } catch {
      return;
    }

    entries
      .sort((a, b) => a.name.localeCompare(b.name))
      .forEach(entry => scan(`${currentPath}/${entry.name}`));
  }

  scan(path);
  return stamp;
}

export function selectRuntimePaths(env = process.env) {
  const sourceRoot = env.OLC_SOURCE_ROOT || defaultSourceRoot;
  const sourceServer = sourcePath(sourceRoot, '/localhost-ui/server.mjs');

  if (!pathExists(sourceServer)) {
    return {
      mode: 'store',
      serverPath: `${storeRoot}/server.mjs`,
      watchPaths: [],
    };
  }

  return {
    mode: 'source',
    serverPath: sourceServer,
    watchPaths: [
      sourcePath(sourceRoot, '/localhost-ui'),
    ],
  };
}

export function createSourcePreviewSupervisor(options = {}) {
  const {
    env = process.env,
    nodeBin = process.execPath,
    restartDelayMs = defaultRestartDelayMs,
    pollIntervalMs = defaultPollIntervalMs,
    selectPaths = selectRuntimePaths,
    spawnProcess = spawn,
    watchPath = watch,
    scanPath = scanWatchStamp,
    setWatchInterval = setInterval,
    clearWatchInterval = clearInterval,
    log = console,
  } = options;

  const runtimePaths = selectPaths(env);
  const childEnv = {
    ...env,
  };
  const watchers = [];
  const pollers = [];
  const watchStamps = new Map();
  let child = null;
  let restartTimer = null;
  let restarting = false;
  let stopping = false;

  function clearRestartTimer() {
    if (restartTimer) {
      clearTimeout(restartTimer);
      restartTimer = null;
    }
  }

  function startChild() {
    child = spawnProcess(nodeBin, [ runtimePaths.serverPath ], {
      env: childEnv,
      stdio: 'inherit',
    });

    child.on('exit', (code, signal) => {
      child = null;
      if (restarting && !stopping) {
        restarting = false;
        startChild();
        return;
      }

      if (!stopping) {
        log.error(`ol-c-ui server exited unexpectedly: code=${code ?? ''} signal=${signal ?? ''}`);
        scheduleRestart();
      }
    });
  }

  function stopChild() {
    if (!child || child.killed) {
      return;
    }

    child.kill('SIGTERM');
  }

  function restartChild() {
    clearRestartTimer();
    if (!child) {
      startChild();
      return;
    }

    restarting = true;
    stopChild();
  }

  function scheduleRestart() {
    clearRestartTimer();
    restartTimer = setTimeout(restartChild, restartDelayMs);
  }

  function startWatchers() {
    for (const path of runtimePaths.watchPaths) {
      if (!pathExists(path)) {
        continue;
      }

      const watcher = watchPath(path, { persistent: true }, () => {
        scheduleRestart();
      });
      watchers.push(watcher);

      watchStamps.set(path, scanPath(path));
      pollers.push(setWatchInterval(() => {
        const nextStamp = scanPath(path);
        if (nextStamp === watchStamps.get(path)) {
          return;
        }

        watchStamps.set(path, nextStamp);
        scheduleRestart();
      }, pollIntervalMs));
    }
  }

  function start() {
    log.log(`OLC_SOURCE_PREVIEW_MODE=${runtimePaths.mode}`);
    startChild();
    startWatchers();
  }

  function stop() {
    stopping = true;
    restarting = false;
    clearRestartTimer();
    for (const watcher of watchers.splice(0)) {
      watcher.close();
    }
    for (const poller of pollers.splice(0)) {
      clearWatchInterval(poller);
    }
    stopChild();
  }

  return {
    get child() {
      return child;
    },
    runtimePaths,
    scheduleRestart,
    start,
    stop,
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const supervisor = createSourcePreviewSupervisor();

  process.on('SIGINT', () => {
    supervisor.stop();
    process.exit(130);
  });
  process.on('SIGTERM', () => {
    supervisor.stop();
    process.exit(143);
  });

  supervisor.start();
}
