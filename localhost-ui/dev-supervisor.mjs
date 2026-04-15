import { existsSync, watch } from 'node:fs';
import { dirname } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const defaultRestartDelayMs = 150;
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

export function selectRuntimePaths(env = process.env) {
  const sourceRoot = env.OLC_SOURCE_ROOT || defaultSourceRoot;
  const sourceServer = sourcePath(sourceRoot, '/localhost-ui/server.mjs');

  if (!pathExists(sourceServer)) {
    return {
      mode: 'store',
      serverPath: `${storeRoot}/server.mjs`,
      terminalClientCss: env.OLC_TERMINAL_CLIENT_CSS,
      terminalClientJs: env.OLC_TERMINAL_CLIENT_JS,
      watchPaths: [],
    };
  }

  return {
    mode: 'source',
    serverPath: sourceServer,
    terminalClientCss: sourcePath(sourceRoot, '/terminal-client/dist/terminal.css'),
    terminalClientJs: sourcePath(sourceRoot, '/terminal-client/dist/terminal.js'),
    watchPaths: [
      sourcePath(sourceRoot, '/localhost-ui'),
      sourcePath(sourceRoot, '/terminal-client/dist'),
    ],
  };
}

export function createSourcePreviewSupervisor(options = {}) {
  const {
    env = process.env,
    nodeBin = process.execPath,
    restartDelayMs = defaultRestartDelayMs,
    selectPaths = selectRuntimePaths,
    spawnProcess = spawn,
    watchPath = watch,
    log = console,
  } = options;

  const runtimePaths = selectPaths(env);
  const childEnv = {
    ...env,
    OLC_TERMINAL_CLIENT_CSS: runtimePaths.terminalClientCss,
    OLC_TERMINAL_CLIENT_JS: runtimePaths.terminalClientJs,
  };
  const watchers = [];
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
