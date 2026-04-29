import { spawn } from 'node:child_process';
import { createReadStream } from 'node:fs';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

function envCommand(name, fallback) {
  return process.env[name] || fallback;
}

function validationError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function shellEscape(value) {
  return `'${String(value).replaceAll('\'', `'\\''`)}'`;
}

export function validateFirstUserInput(body) {
  const username = String(body?.username || '').trim();
  const password = String(body?.password || '');
  const confirmPassword = String(body?.confirmPassword || '');

  if (!/^[a-z_][a-z0-9_-]{0,30}$/.test(username)) {
    throw validationError('username must start with a lowercase letter or underscore and contain only lowercase letters, digits, underscores, or hyphens');
  }

  if (password.length < 12) {
    throw validationError('password must be at least 12 characters');
  }

  if (password !== confirmPassword) {
    throw validationError('password confirmation does not match');
  }

  return { username, password };
}

function commandError(message, statusCode = 500) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

const setupProgressHistoryLimit = 8;

let setupProgress = {
  inProgress: false,
  result: 'idle',
  step: 'idle',
  username: null,
  startedAt: null,
  finishedAt: null,
  latestMessage: null,
  events: [],
};

const setupProgressListeners = new Set();

function cloneSetupProgress(progress = setupProgress) {
  return {
    ...progress,
    events: progress.events.map(event => ({ ...event })),
  };
}

function publishSetupProgress() {
  const snapshot = cloneSetupProgress();
  for (const listener of setupProgressListeners) {
    listener(snapshot);
  }
}

function stripAnsi(value) {
  return String(value || '').replaceAll(/\u001B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g, '');
}

function normalizeProgressLine(value) {
  return stripAnsi(value)
    .replaceAll('\u0008', '')
    .trim();
}

function appendSetupProgress(message, options = {}) {
  const normalized = normalizeProgressLine(message);
  if (!normalized) {
    return;
  }

  const nextEvent = {
    seq: (setupProgress.events.at(-1)?.seq ?? 0) + 1,
    kind: options.kind ?? 'info',
    step: options.step ?? setupProgress.step,
    message: normalized,
    timestamp: new Date().toISOString(),
  };

  setupProgress = {
    ...setupProgress,
    step: options.step ?? setupProgress.step,
    latestMessage: normalized,
    events: [
      ...setupProgress.events.slice(-(setupProgressHistoryLimit - 1)),
      nextEvent,
    ],
  };
  publishSetupProgress();
}

function beginSetupProgress(username) {
  setupProgress = {
    inProgress: true,
    result: 'running',
    step: 'starting',
    username,
    startedAt: new Date().toISOString(),
    finishedAt: null,
    latestMessage: null,
    events: [],
  };
  publishSetupProgress();
}

function finishSetupProgress(message, options = {}) {
  if (message) {
    appendSetupProgress(message, options);
  }

  setupProgress = {
    ...setupProgress,
    inProgress: false,
    result: options.result ?? setupProgress.result,
    step: options.step ?? setupProgress.step,
    finishedAt: new Date().toISOString(),
  };
  publishSetupProgress();
}

function createOutputLineBuffer(onLine) {
  let buffer = '';

  function flushLine(line) {
    const normalized = normalizeProgressLine(line);
    if (normalized) {
      onLine(normalized);
    }
  }

  return {
    push(chunk) {
      buffer += String(chunk);
      const parts = buffer.split(/\r\n|\r|\n/g);
      buffer = parts.pop() ?? '';
      for (const part of parts) {
        flushLine(part);
      }
    },
    flush() {
      flushLine(buffer);
      buffer = '';
    },
  };
}

export function getSetupProgress() {
  return cloneSetupProgress();
}

export function subscribeSetupProgress(listener) {
  setupProgressListeners.add(listener);
  return () => {
    setupProgressListeners.delete(listener);
  };
}

async function runCommand(command, args, options = {}) {
  const {
    env = process.env,
    spawnProcess = spawn,
    onOutputLine = null,
    stdinPath = null,
    timeoutMs = 120_000,
  } = options;

  await new Promise((resolve, reject) => {
    let settled = false;
    let output = '';
    const outputLines = onOutputLine ? createOutputLineBuffer(onOutputLine) : null;
    const child = spawnProcess(command, args, {
      env,
      stdio: [ 'pipe', 'pipe', 'pipe' ],
    });
    const input = stdinPath ? createReadStream(stdinPath) : null;

    const timer = setTimeout(() => {
      if (settled) {
        return;
      }

      settled = true;
      input?.destroy();
      child.kill('SIGTERM');
      reject(commandError('first-user provisioning timed out', 504));
    }, timeoutMs);

    function finish(error = null) {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(timer);
      input?.destroy();
      outputLines?.flush();
      if (error) {
        reject(error);
        return;
      }

      resolve(output.trim());
    }

    child.stdout?.on('data', chunk => {
      const text = String(chunk);
      output += text;
      outputLines?.push(text);
    });
    child.stderr?.on('data', chunk => {
      const text = String(chunk);
      output += text;
      outputLines?.push(text);
    });
    input?.on('error', error => finish(error));
    child.on('error', error => finish(error));
    child.on('exit', code => {
      if (code === 0) {
        finish();
        return;
      }

      finish(commandError(output.trim() || 'first-user provisioning failed'));
    });
    if (input) {
      if (typeof child.stdin?.on === 'function') {
        input.pipe(child.stdin);
      } else {
        readFile(stdinPath, 'utf8')
          .then(value => child.stdin?.end(value))
          .catch(error => finish(error));
      }
    } else {
      child.stdin?.end();
    }
  });
}

let activeProvision = null;

export async function createFirstUser(body, options = {}) {
  const { username, password } = validateFirstUserInput(body);
  if (activeProvision) {
    throw commandError('first setup is already in progress', 409);
  }

  const homectlBin = options.homectlBin ?? envCommand('OLC_HOMECTL', 'homectl');
  const scriptBin = options.scriptBin ?? envCommand('OLC_SCRIPT', 'script');
  const spawnProcess = options.spawnProcess ?? spawn;
  const mkdtempFn = options.mkdtempFn ?? mkdtemp;
  const writeFileFn = options.writeFileFn ?? writeFile;
  const rmFn = options.rmFn ?? rm;
  const tempRoot = options.tempRoot ?? tmpdir();
  const timeoutMs = options.timeoutMs ?? Number(process.env.OLC_FIRST_USER_TIMEOUT_MS || '120000');
  const homeDir = options.homeDir ?? `/home/${username}`;
  const shellBin = options.shellBin ?? envCommand('OLC_LOGIN_SHELL', '/run/current-system/sw/bin/bash');
  const preferredUid = options.preferredUid ?? process.env.OLC_FIRST_USER_UID ?? '1000';
  const memberOf = options.memberOf ?? process.env.OLC_FIRST_USER_GROUPS ?? 'olc-admin,wheel,kvm';
  const storage = options.storage ?? process.env.OLC_FIRST_USER_STORAGE ?? 'luks';
  const diskSize = options.diskSize ?? process.env.OLC_FIRST_USER_DISK_SIZE ?? '8G';

  beginSetupProgress(username);
  appendSetupProgress(`Starting secure account setup for ${username}.`, { step: 'starting' });

  const provision = (async () => {
    const tempDir = await mkdtempFn(join(tempRoot, 'olc-first-user-'));
    const passwordPath = join(tempDir, `${username}.password`);

    try {
      await writeFileFn(
        passwordPath,
        `${password}\n${password}\n`,
        { mode: 0o600 },
      );

      const createCommand = [
        homectlBin,
        'create',
        username,
        `--storage=${storage}`,
        `--disk-size=${diskSize}`,
        `--uid=${preferredUid}`,
        `--home-dir=${homeDir}`,
        `--shell=${shellBin}`,
        `--member-of=${memberOf}`,
        '--access-mode=0700',
        '--no-pager',
      ];

      appendSetupProgress(`Creating encrypted home for ${username}.`, { step: 'creating' });
      await runCommand(scriptBin, [
        '-qefc',
        createCommand.map(shellEscape).join(' '),
        '/dev/null',
      ], {
        env: {
          ...process.env,
          LC_ALL: 'C',
        },
        onOutputLine: line => appendSetupProgress(line, { step: 'creating', kind: 'command' }),
        spawnProcess,
        timeoutMs,
        stdinPath: passwordPath,
      });

      appendSetupProgress(`Verifying account details for ${username}.`, { step: 'verifying' });
      await runCommand(homectlBin, [
        'inspect',
        username,
        '--json=short',
        '--no-pager',
      ], {
        env: {
          ...process.env,
          LC_ALL: 'C',
        },
        onOutputLine: line => appendSetupProgress(line, { step: 'verifying', kind: 'command' }),
        spawnProcess,
        timeoutMs: Math.min(timeoutMs, 10_000),
      });
      finishSetupProgress('Setup complete. Returning to the login screen.', {
        result: 'succeeded',
        step: 'complete',
      });
    } catch (error) {
      finishSetupProgress(error.message, {
        result: 'failed',
        step: 'error',
        kind: 'error',
      });
      throw error;
    } finally {
      await rmFn(tempDir, { recursive: true, force: true });
    }
  })();

  activeProvision = provision;
  try {
    await provision;
  } finally {
    if (activeProvision === provision) {
      activeProvision = null;
    }
  }

  return {
    ok: true,
    username,
    message: 'Setup complete. Returning to the login screen.',
  };
}
