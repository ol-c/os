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

async function runCommand(command, args, options = {}) {
  const {
    env = process.env,
    spawnProcess = spawn,
    stdinPath = null,
    timeoutMs = 120_000,
  } = options;

  await new Promise((resolve, reject) => {
    let settled = false;
    let output = '';
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
      if (error) {
        reject(error);
        return;
      }

      resolve(output.trim());
    }

    child.stdout?.on('data', chunk => {
      output += String(chunk);
    });
    child.stderr?.on('data', chunk => {
      output += String(chunk);
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
        `--uid=${preferredUid}`,
        `--home-dir=${homeDir}`,
        `--shell=${shellBin}`,
        `--member-of=${memberOf}`,
        '--access-mode=0700',
        '--no-pager',
      ];

      await runCommand(scriptBin, [
        '-qefc',
        createCommand.map(shellEscape).join(' '),
        '/dev/null',
      ], {
        env: {
          ...process.env,
          LC_ALL: 'C',
        },
        spawnProcess,
        timeoutMs,
        stdinPath: passwordPath,
      });

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
        spawnProcess,
        timeoutMs: Math.min(timeoutMs, 10_000),
      });
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
