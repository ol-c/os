import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

function envCommand(name, fallback) {
  return process.env[name] || fallback;
}

function parseKeyValueOutput(stdout) {
  const values = {};

  for (const line of String(stdout || '').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }

    const separator = trimmed.indexOf('=');
    if (separator === -1) {
      continue;
    }

    values[trimmed.slice(0, separator)] = trimmed.slice(separator + 1);
  }

  return values;
}

function parsePasswdEntry(stdout) {
  const line = String(stdout || '').trim();
  if (!line) {
    return null;
  }

  const fields = line.split(':');
  if (fields.length < 7) {
    return null;
  }

  return {
    name: fields[0],
    uid: fields[2],
    gid: fields[3],
    home: fields[5],
    shell: fields[6],
  };
}

function parseGroupMembers(stdout) {
  const line = String(stdout || '').trim();
  if (!line) {
    return [];
  }

  const fields = line.split(':');
  if (fields.length < 4) {
    return [];
  }

  return fields[3]
    .split(',')
    .map(member => member.trim())
    .filter(Boolean);
}

export async function getAdminUsers(options = {}) {
  const getentBin = options.getentBin ?? envCommand('OLC_GETENT', 'getent');
  const groupName = options.groupName ?? process.env.OLC_ADMIN_GROUP ?? 'olc-admin';

  try {
    const { stdout } = await execFileAsync(getentBin, [ 'group', groupName ], { timeout: 2000 });
    return parseGroupMembers(stdout);
  } catch {
    return [];
  }
}

export async function isSetupMode(options = {}) {
  const admins = await getAdminUsers(options);
  return admins.length === 0;
}

export async function getUserEntry(userName, options = {}) {
  if (!userName) {
    return null;
  }

  const getentBin = options.getentBin ?? envCommand('OLC_GETENT', 'getent');

  try {
    const { stdout } = await execFileAsync(getentBin, [ 'passwd', userName ], { timeout: 2000 });
    return parsePasswdEntry(stdout);
  } catch {
    return null;
  }
}

export async function getActiveConsoleUser(options = {}) {
  const loginctlBin = options.loginctlBin ?? envCommand('OLC_LOGINCTL', 'loginctl');
  const preferredSeat = options.seat ?? 'seat0';

  try {
    const { stdout: seatStdout } = await execFileAsync(
      loginctlBin,
      [ 'show-seat', preferredSeat, '--property=ActiveSession', '--value' ],
      { timeout: 2000 },
    );
    const sessionId = String(seatStdout || '').trim();
    if (!sessionId) {
      return null;
    }

    const { stdout: sessionStdout } = await execFileAsync(
      loginctlBin,
      [
        'show-session',
        sessionId,
        '--property=Name',
        '--property=Class',
        '--property=Remote',
        '--property=State',
        '--property=TTY',
      ],
      { timeout: 2000 },
    );
    const session = parseKeyValueOutput(sessionStdout);
    if (!session.Name || session.Class !== 'user' || session.Remote === 'yes') {
      return null;
    }
    if (session.State && session.State !== 'active') {
      return null;
    }

    const user = await getUserEntry(session.Name, options);
    if (!user) {
      return null;
    }

    return {
      ...user,
      tty: session.TTY || null,
      sessionId,
    };
  } catch {
    return null;
  }
}

export async function getRuntimeState(options = {}) {
  const setupMode = await isSetupMode(options);
  const activeUser = await getActiveConsoleUser(options);

  return {
    setupMode,
    activeUser,
  };
}
