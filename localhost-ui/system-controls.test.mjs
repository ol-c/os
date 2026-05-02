import assert from 'node:assert/strict';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  createDefaultSystemStatus,
  createFakeSystemAdapter,
  createRealSystemAdapter,
  createSystemControls,
  listFakeHardwareCapabilityTokens,
  parseFakeHardwareCapabilities,
} from './system-controls.mjs';

test('hardware test capability parsing accepts comma and colon separators', () => {
  assert.deepEqual(
    Array.from(parseFakeHardwareCapabilities('wifi:bluetooth,battery')).sort(),
    [ 'appearance', 'battery', 'bluetooth', 'wifi' ],
  );
  assert.deepEqual(
    Array.from(parseFakeHardwareCapabilities('wifi:wifi')).sort(),
    [ 'appearance', 'wifi' ],
  );
});

test('hardware test convenience tokens expand to capability sets', () => {
  assert.deepEqual(
    Array.from(parseFakeHardwareCapabilities('none')).sort(),
    [ 'appearance' ],
  );
  assert.deepEqual(
    Array.from(parseFakeHardwareCapabilities('desktop')).sort(),
    [ 'appearance', 'audio', 'network' ],
  );
  assert.deepEqual(
    Array.from(parseFakeHardwareCapabilities('laptop')).sort(),
    [ 'appearance', 'audio', 'battery', 'bluetooth', 'brightness', 'network', 'wifi' ],
  );
  assert.deepEqual(
    Array.from(parseFakeHardwareCapabilities('all')).sort(),
    [ 'appearance', 'audio', 'battery', 'bluetooth', 'brightness', 'network', 'wifi' ],
  );
});

test('hardware test capability parsing rejects unknown tokens', () => {
  assert.throws(() => parseFakeHardwareCapabilities('wifi,camera'), /unknown hardware test capability: camera/);
  assert.ok(listFakeHardwareCapabilityTokens().includes('wifi'));
});

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
    'browser',
    'terminal',
  ]);
  assert.equal(status.network.connected, true);
  assert.match(status.network.implementation, /Fake hardware test/);
  assert.deepEqual(status.power.actions, [ 'shutdown', 'restart' ]);
  assert.equal(status.power.controlAvailable, true);
  assert.equal(status.power.lifecycleState, 'running');
  assert.equal(status.volume.percent, 40);
  assert.match(status.volume.implementation, /Fake hardware test/);
  assert.equal(status.appearance.mode, 'light');
  assert.match(status.appearance.implementation, /Fake hardware test/);
  assert.equal(status.browser.firefoxVersion, 'test-firefox');
  assert.match(status.browser.implementation, /Firefox version/);
  assert.equal(status.terminal.font, 'noto-sans-mono');
  assert.equal(status.terminal.colorScheme, 'solarized');
  assert.deepEqual(status.terminal.fonts.map(choice => choice.id), [ 'noto-sans-mono' ]);
  assert.deepEqual(status.terminal.colorSchemes.map(choice => choice.id), [ 'solarized', 'tango' ]);
});

test('hardware test capabilities shape facility availability', async () => {
  const status = createDefaultSystemStatus('wifi,battery,bluetooth');

  assert.equal(status.network.available, true);
  assert.equal(status.network.kind, 'wifi');
  assert.deepEqual(status.network.choices.map(choice => choice.id), [ 'wifi-home', 'wifi-office', 'offline' ]);
  assert.equal(status.power.available, true);
  assert.equal(status.volume.available, false);
  assert.equal(status.brightness.available, false);
  assert.equal(status.appearance.available, true);
  assert.equal(status.bluetooth.available, true);
  assert.equal(status.browser.firefoxVersion, 'test-firefox');
  assert.equal(status.terminal.available, true);
  assert.match(status.volume.implementation, /OLC_HARDWARE_TEST=audio/);
});

test('real adapter reports packaged Firefox version from environment', async () => {
  const adapter = createRealSystemAdapter({ firefoxVersion: '149.0.2', pactl: '/does/not/exist' });
  const status = await adapter.getStatus();

  assert.equal(status.browser.firefoxVersion, '149.0.2');
  assert.match(status.browser.implementation, /packaged system service environment/);
});

test('real adapter falls back to installed Firefox binary version', async () => {
  const base = join(process.cwd(), '.tmp-tests');
  await mkdir(base, { recursive: true });
  const dir = await mkdtemp(join(base, 'ol-c-firefox-version-test-'));
  const firefox = join(dir, 'firefox');
  await writeFile(firefox, '#!/bin/sh\nprintf "%s\\n" "Mozilla Firefox 149.0.2"\n');
  await chmod(firefox, 0o755);
  const adapter = createRealSystemAdapter({
    firefox,
    firefoxVersion: '',
    pactl: '/does/not/exist',
  });

  try {
    const status = await adapter.getStatus();

    assert.equal(status.browser.firefoxVersion, '149.0.2');
    assert.match(status.browser.implementation, /installed Firefox binary/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('real adapter records lifecycle request and invokes systemctl for power commands', async () => {
  const base = join(process.cwd(), '.tmp-tests');
  await mkdir(base, { recursive: true });
  const dir = await mkdtemp(join(base, 'ol-c-power-command-test-'));
  const systemctl = join(dir, 'systemctl');
  const lifecycleRequestPath = join(dir, 'guest-request.json');
  const staleTmpPath = `${lifecycleRequestPath}.tmp`;
  const systemctlArgsPath = join(dir, 'systemctl.args');
  await writeFile(systemctl, `#!/bin/sh\nprintf '%s\\n' "$*" > ${JSON.stringify(systemctlArgsPath)}\n`);
  await chmod(systemctl, 0o755);
  await writeFile(staleTmpPath, 'stale request temp\n');
  await chmod(staleTmpPath, 0o444);
  const adapter = createRealSystemAdapter({
    firefoxVersion: '149.0.2',
    lifecycleRequestPath,
    pactl: '/does/not/exist',
    systemctl,
  });

  try {
    const status = await adapter.power({ action: 'shutdown' });
    const request = JSON.parse(await readFile(lifecycleRequestPath, 'utf8'));

    assert.equal(status.power.lastAction, 'shutdown');
    assert.equal(status.power.lifecycleState, 'shutting-down');
    assert.equal(request.action, 'shutdown');
    assert.match(request.requestId, /^\d+-\d+$/);
    assert.equal(await readFile(staleTmpPath, 'utf8'), 'stale request temp\n');
    assert.equal((await readFile(systemctlArgsPath, 'utf8')).trim(), 'poweroff --no-block');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('real adapter skips lifecycle request when lifecycle is unavailable', async () => {
  const base = join(process.cwd(), '.tmp-tests');
  await mkdir(base, { recursive: true });
  const dir = await mkdtemp(join(base, 'ol-c-power-command-test-'));
  const systemctl = join(dir, 'systemctl');
  const lifecycleRequestPath = join(dir, 'guest-request.json');
  const systemctlArgsPath = join(dir, 'systemctl.args');
  await writeFile(systemctl, `#!/bin/sh\nprintf '%s\\n' "$*" > ${JSON.stringify(systemctlArgsPath)}\n`);
  await chmod(systemctl, 0o755);
  const adapter = createRealSystemAdapter({
    firefoxVersion: '149.0.2',
    lifecycleRequestPath: null,
    pactl: '/does/not/exist',
    systemctl,
  });

  try {
    const status = await adapter.power({ action: 'restart' });

    assert.equal(status.power.lastAction, 'restart');
    assert.equal(status.power.lifecycleState, 'restarting');
    await assert.rejects(readFile(lifecycleRequestPath, 'utf8'), { code: 'ENOENT' });
    assert.equal((await readFile(systemctlArgsPath, 'utf8')).trim(), 'reboot --no-block');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('fake adapter updates mutable controls', async () => {
  const adapter = createFakeSystemAdapter(createDefaultSystemStatus('all'));

  await adapter.volume({ percent: 65 });
  await adapter.volume({ muted: true });
  await adapter.brightness({ percent: 25 });
  await adapter.appearance({ mode: 'dark' });
  await adapter.power({ action: 'restart' });
  await adapter.terminal({ font: 'noto-sans-mono', colorScheme: 'tango' });
  await adapter.bluetooth({ enabled: true });
  await adapter.network({ selected: 'offline' });

  const status = await adapter.getStatus();
  assert.equal(status.volume.percent, 65);
  assert.equal(status.volume.muted, true);
  assert.equal(status.brightness.percent, 25);
  assert.equal(status.appearance.mode, 'dark');
  assert.equal(status.power.lastAction, 'restart');
  assert.equal(status.power.lifecycleState, 'restarting');
  assert.equal(status.terminal.font, 'noto-sans-mono');
  assert.equal(status.terminal.colorScheme, 'tango');
  assert.equal(status.bluetooth.enabled, true);
  assert.equal(status.network.connected, false);
});

test('fake Wi-Fi choices update kind and SSID', async () => {
  const adapter = createFakeSystemAdapter(createDefaultSystemStatus('wifi'));

  await adapter.network({ selected: 'wifi-office' });
  const status = await adapter.getStatus();

  assert.equal(status.network.connected, true);
  assert.equal(status.network.kind, 'wifi');
  assert.equal(status.network.ssid, 'Office Wi-Fi');
});

test('fake unavailable controls reject commands', async () => {
  const adapter = createFakeSystemAdapter(createDefaultSystemStatus('none'));

  await assert.rejects(() => adapter.network({ selected: 'offline' }), /network control is unavailable/);
  await assert.rejects(() => adapter.volume({ percent: 10 }), /volume control is unavailable/);
  await assert.rejects(() => adapter.brightness({ percent: 10 }), /brightness control is unavailable/);
  await assert.rejects(() => adapter.bluetooth({ enabled: true }), /bluetooth control is unavailable/);
});

test('fake adapter rejects invalid commands', async () => {
  const adapter = createFakeSystemAdapter(createDefaultSystemStatus('all'));

  await assert.rejects(() => adapter.volume({ percent: 101 }), /integer from 0 to 100/);
  await assert.rejects(() => adapter.volume({ muted: 'yes' }), /muted must be true or false/);
  await assert.rejects(() => adapter.brightness({ percent: -1 }), /integer from 0 to 100/);
  await assert.rejects(() => adapter.appearance({ mode: 'auto' }), /mode must be light or dark/);
  await assert.rejects(() => adapter.power({ action: 'sleep' }), /action must be shutdown or restart/);
  await assert.rejects(() => adapter.terminal({ font: 'comic-sans' }), /available terminal fonts/);
  await assert.rejects(() => adapter.terminal({ colorScheme: 'monochrome' }), /light and dark terminal color schemes/);
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
