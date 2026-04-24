import assert from 'node:assert/strict';
import test from 'node:test';
import { validateFirstUserInput } from './setup-manager.mjs';

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
