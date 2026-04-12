import assert from 'node:assert/strict';
import test from 'node:test';
import { createSessionLifecycle } from './session-lifecycle.mjs';

function createWindowStub({ closes = true } = {}) {
  const timers = [];
  const windowRef = {
    closed: false,
    closeCount: 0,
    close() {
      this.closeCount += 1;
      this.closed = closes;
    },
    setTimeout(callback, delayMs) {
      timers.push({ callback, delayMs });
      return timers.length;
    },
  };

  return { timers, windowRef };
}

test('closeRootSessionTab asks the browser to close the current tab once', () => {
  const { timers, windowRef } = createWindowStub();
  const terminalNode = { dataset: {} };
  let closeBlocked = false;
  const lifecycle = createSessionLifecycle({
    windowRef,
    terminalNode,
    onCloseBlocked: () => {
      closeBlocked = true;
    },
  });

  lifecycle.closeRootSessionTab();
  lifecycle.closeRootSessionTab();

  assert.equal(windowRef.closeCount, 1);
  assert.equal(terminalNode.dataset.rootSessionExited, 'true');
  assert.equal(timers.length, 1);

  timers[0].callback();

  assert.equal(closeBlocked, false);
});

test('closeRootSessionTab reports a blocked close without retrying', () => {
  const { timers, windowRef } = createWindowStub({ closes: false });
  let closeBlockedCount = 0;
  const lifecycle = createSessionLifecycle({
    windowRef,
    closeFallbackDelayMs: 10,
    onCloseBlocked: () => {
      closeBlockedCount += 1;
    },
  });

  lifecycle.closeRootSessionTab();
  lifecycle.closeRootSessionTab();
  timers[0].callback();

  assert.equal(windowRef.closeCount, 1);
  assert.equal(timers[0].delayMs, 10);
  assert.equal(closeBlockedCount, 1);
});
