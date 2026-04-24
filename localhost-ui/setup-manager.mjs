import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
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

function transientUnitName(username) {
  return `olc-first-user-${username}-${Date.now()}`;
}

function createFirstUserRecord({
  username,
  password,
  homeDirectory,
  shellBin,
  preferredUid,
  memberOf,
  storage,
}) {
  return {
    accessMode: '0700',
    disposition: 'regular',
    homeDirectory,
    memberOf: memberOf.split(',').map(group => group.trim()).filter(Boolean),
    secret: {
      password: [ password ],
    },
    shell: shellBin,
    storage,
    uid: Number(preferredUid),
    userName: username,
  };
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
    timeoutMs = 120_000,
  } = options;

  await new Promise((resolve, reject) => {
    let settled = false;
    let output = '';
    const child = spawnProcess(command, args, {
      env,
      stdio: [ 'ignore', 'pipe', 'pipe' ],
    });

    const timer = setTimeout(() => {
      if (settled) {
        return;
      }

      settled = true;
      child.kill('SIGTERM');
      reject(commandError('first-user provisioning timed out', 504));
    }, timeoutMs);

    function finish(error = null) {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(timer);
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
    child.on('error', error => finish(error));
    child.on('exit', code => {
      if (code === 0) {
        finish();
        return;
      }

      finish(commandError(output.trim() || 'first-user provisioning failed'));
    });
  });
}

let activeProvision = null;

export async function createFirstUser(body, options = {}) {
  const { username, password } = validateFirstUserInput(body);
  if (activeProvision) {
    throw commandError('first setup is already in progress', 409);
  }

  const homectlBin = options.homectlBin ?? envCommand('OLC_HOMECTL', 'homectl');
  const systemdRunBin = options.systemdRunBin ?? envCommand('OLC_SYSTEMD_RUN', 'systemd-run');
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
    const credentialPath = join(tempDir, `home.create.${username}.json`);

    try {
      const userRecord = createFirstUserRecord({
        username,
        password,
        homeDirectory: homeDir,
        shellBin,
        preferredUid,
        memberOf,
        storage,
      });

      await writeFileFn(
        credentialPath,
        `${JSON.stringify(userRecord, null, 2)}\n`,
        { mode: 0o600 },
      );

      await runCommand(systemdRunBin, [
        '--quiet',
        '--wait',
        '--collect',
        '--pipe',
        '--service-type=oneshot',
        `--unit=${transientUnitName(username)}`,
        `--property=LoadCredential=home.create.${username}:${credentialPath}`,
        '--',
        homectlBin,
        'firstboot',
        '--no-pager',
      ], {
        env: {
          ...process.env,
          LC_ALL: 'C',
        },
        spawnProcess,
        timeoutMs,
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
