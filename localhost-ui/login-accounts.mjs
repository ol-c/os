import { execFile } from 'node:child_process';

const DEFAULT_EXCLUDED_USERS = [
  'root',
  'nobody',
  'olc-setup',
  'olc-greeter',
];

function parseList(value) {
  if (Array.isArray(value)) {
    return value.map(item => String(item).trim()).filter(Boolean);
  }

  return String(value ?? '')
    .split(/[\s,:]+/)
    .map(item => item.trim())
    .filter(Boolean);
}

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isSafeInteger(parsed) ? parsed : fallback;
}

function isDisabledShell(shell) {
  return /(?:^|\/)(?:false|nologin)$/.test(shell);
}

function isSafeUsername(username) {
  return /^[A-Za-z_][A-Za-z0-9_.-]{0,63}\$?$/.test(username);
}

function accountFilter(options = {}) {
  const minUid = parseInteger(options.minUid, 1000);
  const maxUid = parseInteger(options.maxUid, 60000);
  const excludedUsers = new Set([
    ...DEFAULT_EXCLUDED_USERS,
    ...parseList(options.excludedUsers),
  ]);

  return account => {
    if (!isSafeUsername(account.username)) {
      return false;
    }
    if (excludedUsers.has(account.username)) {
      return false;
    }
    if (account.uid != null) {
      const uid = Number.parseInt(String(account.uid), 10);
      if (!Number.isSafeInteger(uid) || uid < minUid || uid >= maxUid) {
        return false;
      }
    }
    if (account.shell && isDisabledShell(account.shell)) {
      return false;
    }
    return true;
  };
}

function sortedUniqueUsernames(accounts, options = {}) {
  const includeAccount = accountFilter(options);
  const users = [];
  for (const account of accounts) {
    if (includeAccount(account)) {
      users.push(account.username);
    }
  }

  return [ ...new Set(users) ].sort((a, b) => a.localeCompare(b));
}

export function parseLoginAccounts(passwdText, options = {}) {
  const accounts = [];
  for (const line of String(passwdText ?? '').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }

    const fields = trimmed.split(':');
    if (fields.length < 7) {
      continue;
    }

    const [ username, , uidText, , , , shell ] = fields;
    accounts.push({
      username,
      uid: uidText,
      shell,
    });
  }

  return sortedUniqueUsernames(accounts, options);
}

function userNameFromRecord(record) {
  if (!record || typeof record !== 'object') {
    return '';
  }

  return String(record.userName ?? record.user ?? record.name ?? record.userNameForDisplay ?? '').trim();
}

function uidFromRecord(record) {
  if (!record || typeof record !== 'object') {
    return null;
  }

  return record.uid ?? record.uidNumber ?? record.disposition?.uid ?? null;
}

function recordsFromHomectlJson(value) {
  if (Array.isArray(value)) {
    return value;
  }
  if (Array.isArray(value?.users)) {
    return value.users;
  }
  if (value && typeof value === 'object') {
    return Object.entries(value).map(([ name, record ]) => {
      if (record && typeof record === 'object') {
        return { name, ...record };
      }
      return { name };
    });
  }
  return [];
}

export function parseHomectlAccounts(homectlText, options = {}) {
  const text = String(homectlText ?? '').trim();
  if (!text) {
    return [];
  }

  try {
    const parsed = JSON.parse(text);
    return sortedUniqueUsernames(recordsFromHomectlJson(parsed).map(record => ({
      username: userNameFromRecord(record),
      uid: uidFromRecord(record),
      shell: record.shell ?? record.loginShell ?? null,
    })), options);
  } catch {
    // Older or differently configured homectl output can be tabular; use only
    // the username column and let shared filters reject unsafe/system names.
  }

  const accounts = [];
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || /^NAME(?:\s|$)/i.test(trimmed)) {
      continue;
    }

    const [ username, uid ] = trimmed.split(/\s+/);
    accounts.push({ username, uid });
  }

  return sortedUniqueUsernames(accounts, options);
}

function execFileText(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    execFile(command, args, {
      encoding: 'utf8',
      maxBuffer: 512 * 1024,
      ...options,
    }, (error, stdout) => {
      if (error) {
        reject(error);
        return;
      }

      resolve(stdout);
    });
  });
}

export function createLoginAccountProvider(options = {}) {
  const getentBin = options.getentBin ?? process.env.OLC_GETENT ?? 'getent';
  const homectlBin = options.homectlBin ?? process.env.OLC_HOMECTL ?? 'homectl';
  const minUid = options.minUid ?? process.env.OLC_GREETER_MIN_UID ?? 1000;
  const maxUid = options.maxUid ?? process.env.OLC_GREETER_MAX_UID ?? 60000;
  const excludedUsers = options.excludedUsers ?? process.env.OLC_GREETER_EXCLUDE_USERS ?? '';

  return async function listLoginAccounts() {
    const filterOptions = {
      minUid,
      maxUid,
      excludedUsers,
    };
    const [ passwdText, homectlText ] = await Promise.all([
      execFileText(getentBin, [ 'passwd' ]).catch(() => ''),
      execFileText(homectlBin, [ 'list', '--json=short', '--no-pager' ]).catch(() => ''),
    ]);

    return [ ...new Set([
      ...parseLoginAccounts(passwdText, filterOptions),
      ...parseHomectlAccounts(homectlText, filterOptions),
    ]) ].sort((a, b) => a.localeCompare(b));
  };
}
