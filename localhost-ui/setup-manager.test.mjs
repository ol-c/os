import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
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

test('first-user creation provisions through script-wrapped homectl create and verifies the result', async () => {
  const seenCalls = [];
  let passwordInput = null;
  const tempRoot = await mkdtemp(join(tmpdir(), 'olc-setup-test-'));

  function spawnProcess(command, args) {
    seenCalls.push({ command, args });

    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.stdin = {
      end(value) {
        if (command === '/bin/script') {
          passwordInput = String(value);
        }
      },
    };
    child.kill = () => {};
    child.on = child.addListener.bind(child);
    queueMicrotask(async () => {
      try {
        child.emit('exit', 0);
      } catch (error) {
        child.emit('error', error);
      }
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
    scriptBin: '/bin/script',
    shellBin: '/bin/bash',
    spawnProcess,
  });

  assert.equal(seenCalls.length, 2);
  assert.equal(seenCalls[0].command, '/bin/script');
  assert.equal(seenCalls[0].args[0], '-qefc');
  assert.match(seenCalls[0].args[1], /'\/bin\/homectl' 'create' 'alice'/);
  assert.match(seenCalls[0].args[1], /'--storage=luks'/);
  assert.match(seenCalls[0].args[1], /'--disk-size=8G'/);
  assert.match(seenCalls[0].args[1], /'--uid=1000'/);
  assert.match(seenCalls[0].args[1], /'--home-dir=\/home\/alice'/);
  assert.match(seenCalls[0].args[1], /'--shell=\/bin\/bash'/);
  assert.match(seenCalls[0].args[1], /'--member-of=olc-admin,wheel,kvm'/);
  assert.match(seenCalls[0].args[1], /'--access-mode=0700'/);
  assert.equal(seenCalls[0].args[2], '/dev/null');
  assert.equal(passwordInput, 'correct horse battery\ncorrect horse battery\n');
  assert.equal(seenCalls[1].command, '/bin/homectl');
  assert.deepEqual(seenCalls[1].args, [
    'inspect',
    'alice',
    '--json=short',
    '--no-pager',
  ]);
  assert.equal(result.username, 'alice');
});

test('first-user creation times out cleanly when provisioning never exits', async () => {
  function spawnProcess(command, args) {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.stdin = {
      end() {},
    };
    child.kill = () => {};
    child.on = child.addListener.bind(child);
    if (command === '/bin/script') {
      return child;
    }
    if (command === '/bin/homectl' && args?.[0] === 'inspect') {
      queueMicrotask(() => {
        child.emit('exit', 0);
      });
    }
    return child;
  }

  await assert.rejects(() => createFirstUser({
    username: 'alice',
    password: 'correct horse battery',
    confirmPassword: 'correct horse battery',
  }, {
    spawnProcess,
    homectlBin: '/bin/homectl',
    scriptBin: '/bin/script',
    timeoutMs: 5,
  }), error => error.statusCode === 504 && /timed out/i.test(error.message));
});
