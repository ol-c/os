import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import { EventEmitter } from 'node:events';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { createFirstUser, validateFirstUserInput } from './setup-manager.mjs';

test('first-user validation accepts a secure basic username and password', () => {
  assert.deepEqual(validateFirstUserInput({
    username: 'alice',
    password: 'correct horse battery',
    confirmPassword: 'correct horse battery',
  }), {
    username: 'alice',
    password: 'correct horse battery',
  });
});

test('first-user validation rejects bad usernames and weak passwords', () => {
  assert.throws(() => validateFirstUserInput({
    username: 'Alice',
    password: 'correct horse battery',
    confirmPassword: 'correct horse battery',
  }), /lowercase/);

  assert.throws(() => validateFirstUserInput({
    username: 'alice',
    password: 'short',
    confirmPassword: 'short',
  }), /at least 12 characters/);

  assert.throws(() => validateFirstUserInput({
    username: 'alice',
    password: 'correct horse battery',
    confirmPassword: 'different horse battery',
  }), /does not match/);
});

test('first-user creation provisions through systemd-run and homectl firstboot credentials', async () => {
  let seenCommand = null;
  let seenArgs = null;
  let credentialJson = null;
  const tempRoot = await mkdtemp(join(tmpdir(), 'olc-setup-test-'));

  function spawnProcess(command, args) {
    seenCommand = command;
    seenArgs = args;

    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.stdin = null;
    child.on = child.addListener.bind(child);
    queueMicrotask(async () => {
      const credentialArg = args.find(arg => arg.startsWith('--property=LoadCredential=home.create.alice:'));
      const credentialPath = credentialArg.split(':').slice(1).join(':');
      credentialJson = JSON.parse(await readFile(credentialPath, 'utf8'));
      child.emit('exit', 0);
    });
    return child;
  }

  const result = await createFirstUser({
    username: 'alice',
    password: 'correct horse battery',
    confirmPassword: 'correct horse battery',
  }, {
    tempRoot,
    homectlBin: '/bin/homectl',
    shellBin: '/bin/bash',
    systemdRunBin: '/bin/systemd-run',
    spawnProcess,
  });

  assert.equal(seenCommand, '/bin/systemd-run');
  assert.equal(seenArgs.at(-3), '/bin/homectl');
  assert.equal(seenArgs.at(-2), 'firstboot');
  assert.equal(seenArgs.at(-1), '--no-pager');
  assert.ok(seenArgs.includes('--wait'));
  assert.ok(seenArgs.includes('--collect'));
  assert.ok(seenArgs.includes('--pipe'));
  assert.ok(seenArgs.some(arg => arg.startsWith('--unit=olc-first-user-alice-')));
  assert.ok(seenArgs.includes('--service-type=oneshot'));
  assert.deepEqual(credentialJson, {
    accessMode: '0700',
    disposition: 'regular',
    homeDirectory: '/home/alice',
    memberOf: [ 'olc-admin', 'wheel', 'kvm' ],
    secret: {
      password: [ 'correct horse battery' ],
    },
    shell: '/bin/bash',
    storage: 'luks',
    uid: 1000,
    userName: 'alice',
  });
  assert.equal(result.username, 'alice');
});

test('first-user creation times out cleanly when provisioning never exits', async () => {
  function spawnProcess() {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.kill = () => {};
    child.on = child.addListener.bind(child);
    return child;
  }

  await assert.rejects(() => createFirstUser({
    username: 'alice',
    password: 'correct horse battery',
    confirmPassword: 'correct horse battery',
  }, {
    spawnProcess,
    systemdRunBin: '/bin/systemd-run',
    homectlBin: '/bin/homectl',
    timeoutMs: 5,
  }), error => error.statusCode === 504 && /timed out/i.test(error.message));
});
