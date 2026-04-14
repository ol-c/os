import assert from 'node:assert/strict';
import test from 'node:test';
import { createFakeSystemAdapter, createSystemControls } from './system-controls.mjs';

test('fake adapter returns a complete initial status', async () => {
  const adapter = createFakeSystemAdapter();
  const status = await adapter.getStatus();

  assert.deepEqual(Object.keys(status), [
    'network',
    'power',
    'volume',
    'brightness',
    'appearance',
    'bluetooth',
  ]);
  assert.equal(status.network.connected, true);
  assert.match(status.network.implementation, /Fake backend/);
  assert.equal(status.volume.percent, 40);
  assert.match(status.volume.implementation, /Fake backend/);
  assert.equal(status.appearance.mode, 'light');
  assert.match(status.appearance.implementation, /Fake backend/);
});

test('fake adapter updates mutable controls', async () => {
  const adapter = createFakeSystemAdapter();

  await adapter.volume({ percent: 65 });
  await adapter.volume({ muted: true });
  await adapter.brightness({ percent: 25 });
  await adapter.appearance({ mode: 'dark' });
  await adapter.bluetooth({ enabled: true });
  await adapter.network({ selected: 'offline' });

  const status = await adapter.getStatus();
  assert.equal(status.volume.percent, 65);
  assert.equal(status.volume.muted, true);
  assert.equal(status.brightness.percent, 25);
  assert.equal(status.appearance.mode, 'dark');
  assert.equal(status.bluetooth.enabled, true);
  assert.equal(status.network.connected, false);
});

test('fake adapter rejects invalid commands', async () => {
  const adapter = createFakeSystemAdapter();

  await assert.rejects(() => adapter.volume({ percent: 101 }), /integer from 0 to 100/);
  await assert.rejects(() => adapter.volume({ muted: 'yes' }), /muted must be true or false/);
  await assert.rejects(() => adapter.brightness({ percent: -1 }), /integer from 0 to 100/);
  await assert.rejects(() => adapter.appearance({ mode: 'auto' }), /mode must be light or dark/);
  await assert.rejects(() => adapter.bluetooth({ enabled: 'true' }), /enabled must be true or false/);
  await assert.rejects(() => adapter.network({ selected: 'wifi' }), /not available/);
});

test('system controls publishes status after commands', async () => {
  const controls = createSystemControls(createFakeSystemAdapter(), { pollIntervalMs: 0 });
  const events = [];
  const unsubscribe = controls.subscribe(status => events.push(status));

  const status = await controls.command('volume', { percent: 55 });
  unsubscribe();

  assert.equal(status.volume.percent, 55);
  assert.equal(events.length, 1);
  assert.equal(events[0].volume.percent, 55);
  controls.close();
});

test('system controls publishes externally observed status changes', async () => {
  let status = { value: 1 };
  const controls = createSystemControls({
    async getStatus() {
      return status;
    },
  }, { pollIntervalMs: 10 });
  const published = new Promise(resolve => {
    controls.subscribe(nextStatus => {
      if (nextStatus.value === 2) {
        resolve(nextStatus);
      }
    });
  });

  await controls.getStatus();
  status = { value: 2 };

  const result = await Promise.race([
    published,
    new Promise((_, reject) => setTimeout(() => reject(new Error('timed out waiting for poll event')), 200)),
  ]);
  assert.equal(result.value, 2);
  controls.close();
});
