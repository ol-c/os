import { spawn } from 'node:child_process';

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

function shellEscape(value) {
  return `'${String(value).replaceAll('\'', `'\\''`)}'`;
}

export async function createFirstUser(body, options = {}) {
  const { username, password } = validateFirstUserInput(body);
  const homectlBin = options.homectlBin ?? envCommand('OLC_HOMECTL', 'homectl');
  const scriptBin = options.scriptBin ?? envCommand('OLC_SCRIPT', 'script');
  const shellBin = options.shellBin ?? envCommand('OLC_LOGIN_SHELL', '/run/current-system/sw/bin/bash');
  const preferredUid = options.preferredUid ?? process.env.OLC_FIRST_USER_UID ?? '1000';
  const memberOf = options.memberOf ?? process.env.OLC_FIRST_USER_GROUPS ?? 'olc-admin,wheel,kvm';
  const storage = options.storage ?? process.env.OLC_FIRST_USER_STORAGE ?? 'luks';
  const imagePath = options.imagePath ?? process.env.OLC_FIRST_USER_IMAGE_PATH ?? '';
  const command = [
    homectlBin,
    'create',
    username,
    `--storage=${storage}`,
    `--uid=${preferredUid}`,
    `--shell=${shellBin}`,
    `--member-of=${memberOf}`,
    '--access-mode=0700',
  ];

  if (imagePath) {
    command.push(`--image-path=${imagePath}`);
  }

  await new Promise((resolve, reject) => {
    const child = spawn(scriptBin, [ '-qefc', command.map(shellEscape).join(' '), '/dev/null' ], {
      stdio: [ 'pipe', 'pipe', 'pipe' ],
      env: {
        ...process.env,
        LC_ALL: 'C',
      },
    });
    let output = '';
    let sentPassword = false;
    let sentConfirmation = false;

    function maybeSendPassword(chunk) {
      output += String(chunk);

      if (!sentPassword && /new password[:\s]*$/im.test(output)) {
        child.stdin.write(`${password}\n`);
        sentPassword = true;
        return;
      }

      if (sentPassword && !sentConfirmation && /(again|repeat).*(password)|password.*again/im.test(output)) {
        child.stdin.write(`${password}\n`);
        sentConfirmation = true;
      }
    }

    child.stdout.on('data', maybeSendPassword);
    child.stderr.on('data', maybeSendPassword);
    child.on('error', reject);
    child.on('exit', code => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(new Error(output.trim() || 'homectl create failed'));
    });
  });

  return {
    ok: true,
    username,
    message: 'Setup complete. Returning to the login prompt.',
  };
}
