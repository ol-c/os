import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { chmodSync } from 'node:fs';
import http from 'node:http';
import { join } from 'node:path';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { createLoginGreeterApp } from './login-greeter-app.mjs';
import { loginGreeterHtml } from './login-greeter-page.mjs';
import { createLoginAccountProvider, parseHomectlAccounts, parseLoginAccounts } from './login-accounts.mjs';

function fakeClient() {
  return {
    authenticate() {
      throw new Error('not used');
    },
    respond() {
      throw new Error('not used');
    },
    cancel() {
      return { ok: true };
    },
  };
}

async function withGreeterServer(app, fn) {
  const server = http.createServer(app.handleRequest);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

async function waitFor(condition) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (condition()) {
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 0));
  }

  throw new Error('timed out waiting for condition');
}

test('login account parsing returns only safe human usernames', () => {
  const users = parseLoginAccounts(`
root:x:0:0:root:/root:/run/current-system/sw/bin/bash
daemon:x:1:1:daemon:/run/daemon:/run/current-system/sw/sbin/nologin
olc-greeter:x:996:996:greeter:/var/lib/ol-c/greeter:/run/current-system/sw/bin/bash
olc-setup:x:1100:995:setup:/var/lib/ol-c/setup:/run/current-system/sw/bin/bash
alice:x:1000:100:Alice Example:/home/alice:/run/current-system/sw/bin/bash
bob:x:1001:100:Bob Example:/home/bob:/run/current-system/sw/bin/fish
locked:x:1002:100:Locked User:/home/locked:/run/current-system/sw/sbin/nologin
nobody:x:65534:65534:nobody:/var/empty:/run/current-system/sw/sbin/nologin
bad:name:x:1003:100:Bad Name:/home/bad:/run/current-system/sw/bin/bash
alice:x:1000:100:Alice Duplicate:/home/alice:/run/current-system/sw/bin/bash
`, {
    excludedUsers: [ 'olc-setup' ],
  });

  assert.deepEqual(users, [ 'alice', 'bob' ]);
});

test('homectl account parsing returns only user names from JSON and table output', () => {
  assert.deepEqual(parseHomectlAccounts(JSON.stringify([
    { userName: 'jason', uid: 1000, shell: '/bin/bash' },
    { userName: 'olc-setup', uid: 1100, shell: '/bin/bash' },
    { userName: 'root', uid: 0, shell: '/bin/bash' },
    { userName: 'locked', uid: 1001, shell: '/sbin/nologin' },
  ])), [ 'jason' ]);

  assert.deepEqual(parseHomectlAccounts(`
NAME        UID   GID STATE
jason       1000  100 active
olc-setup   1100  995 active
systemd-coredump 999 999 active
`), [ 'jason' ]);
});

test('homectl account parsing accepts common object-shaped JSON output', () => {
  assert.deepEqual(parseHomectlAccounts(JSON.stringify({
    users: [
      { name: 'alice', uidNumber: 1000 },
      { user: 'bob', uid: 1001 },
    ],
  })), [ 'alice', 'bob' ]);

  assert.deepEqual(parseHomectlAccounts(JSON.stringify({
    zoe: { uid: 1002 },
    root: { uid: 0 },
  })), [ 'zoe' ]);
});

test('login account provider merges passwd and homectl accounts', async () => {
  const root = join(process.cwd(), '.tmp-tests');
  await mkdir(root, { recursive: true });
  const dir = await mkdtemp(join(root, 'olc-login-accounts-'));
  const getent = join(dir, 'getent');
  const homectl = join(dir, 'homectl');
  await writeFile(getent, `#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "passwd" ]]; then
  exit 1
fi
cat <<'PASSWD'
zoe:x:1002:100:Zoe:/home/zoe:/bin/bash
alice:x:1000:100:Alice:/home/alice:/bin/bash
olc-setup:x:1100:995:Setup:/var/lib/ol-c/setup:/bin/bash
PASSWD
`);
  await writeFile(homectl, `#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "list" ]]; then
  exit 1
fi
cat <<'JSON'
[
  { "userName": "jason", "uid": 1000, "shell": "/bin/bash" },
  { "userName": "olc-greeter", "uid": 996, "shell": "/bin/bash" }
]
JSON
`);
  chmodSync(getent, 0o755);
  chmodSync(homectl, 0o755);

  try {
    const listLoginAccounts = createLoginAccountProvider({
      getentBin: getent,
      homectlBin: homectl,
      excludedUsers: [ 'olc-setup' ],
    });
    assert.deepEqual(await listLoginAccounts(), [ 'alice', 'jason', 'zoe' ]);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('greeter account API returns only usernames and no-store headers', async () => {
  const app = createLoginGreeterApp({
    client: fakeClient(),
    listLoginAccounts: async () => [ 'alice', 'bob' ],
  });

  await withGreeterServer(app, async baseUrl => {
    const response = await fetch(`${baseUrl}/api/login/users`);
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(payload, {
      ok: true,
      users: [ 'alice', 'bob' ],
    });
    assert.equal(JSON.stringify(payload).includes('uid'), false);
    assert.equal(JSON.stringify(payload).includes('/home/'), false);
  });
});

test('login page renders account choices and keeps manual username fallback', async () => {
  const dom = new JSDOM(loginGreeterHtml(), {
    runScripts: 'dangerously',
    url: 'https://localhost/login',
    beforeParse(window) {
      window.fetch = async path => {
        assert.equal(path, '/api/login/users');
        return new Response(JSON.stringify({
          ok: true,
          users: [ 'alice', 'bob' ],
        }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      };
    },
  });
  const { document } = dom.window;

  await waitFor(() => document.querySelectorAll('.account-button').length === 2);

  const accountButtons = [ ...document.querySelectorAll('.account-button') ];
  const username = document.getElementById('username');
  const usernameLabel = document.getElementById('username-label');
  const manualAccount = document.getElementById('manual-account');
  const password = document.getElementById('password');

  assert.deepEqual(accountButtons.map(button => button.textContent), [ 'alice', 'bob' ]);
  assert.equal(usernameLabel.classList.contains('hidden'), true);
  assert.equal(username.value, 'alice');
  assert.equal(accountButtons[0].getAttribute('aria-pressed'), 'true');
  assert.equal(dom.window.document.activeElement, password);

  accountButtons[1].click();
  assert.equal(username.value, 'bob');
  assert.equal(accountButtons[1].getAttribute('aria-pressed'), 'true');

  manualAccount.click();
  assert.equal(username.value, '');
  assert.equal(usernameLabel.classList.contains('hidden'), false);
  assert.equal(accountButtons[1].getAttribute('aria-pressed'), 'false');
});
