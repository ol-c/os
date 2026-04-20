import { execFile } from 'node:child_process';
import { readdir, readFile } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import { promisify } from 'node:util';
import {
  defaultTerminalPreferences,
  findTerminalColorScheme,
  findTerminalFont,
  terminalColorSchemeChoices,
  terminalFontChoices,
} from './terminal-options.mjs';

const execFileAsync = promisify(execFile);
const defaultFakeHardwareTest = 'network,audio,brightness,appearance';
const supportedCapabilityTokens = new Set([
  'appearance',
  'audio',
  'battery',
  'bluetooth',
  'brightness',
  'network',
  'wifi',
]);
const convenienceCapabilityTokens = new Map([
  [ 'all', [ 'network', 'wifi', 'battery', 'audio', 'brightness', 'appearance', 'bluetooth' ] ],
  [ 'desktop', [ 'network', 'audio', 'appearance' ] ],
  [ 'laptop', [ 'network', 'wifi', 'battery', 'audio', 'brightness', 'appearance', 'bluetooth' ] ],
  [ 'none', [ 'appearance' ] ],
]);

export function listFakeHardwareCapabilityTokens() {
  return [
    ...Array.from(supportedCapabilityTokens).sort(),
    ...Array.from(convenienceCapabilityTokens.keys()).sort(),
  ];
}

export function parseFakeHardwareCapabilities(value = defaultFakeHardwareTest) {
  const rawTokens = String(value || defaultFakeHardwareTest)
    .split(/[,:]/)
    .map(token => token.trim().toLowerCase())
    .filter(Boolean);
  const capabilities = new Set();

  for (const token of rawTokens) {
    if (convenienceCapabilityTokens.has(token)) {
      for (const capability of convenienceCapabilityTokens.get(token)) {
        capabilities.add(capability);
      }
      continue;
    }

    if (!supportedCapabilityTokens.has(token)) {
      throw validationError(`unknown hardware test capability: ${token}`);
    }

    capabilities.add(token);
  }

  capabilities.add('appearance');
  return capabilities;
}

function capabilityListText(capabilities) {
  return Array.from(capabilities).sort().join(', ');
}

function fakeImplementation(capabilities, capability, availableText, unavailableText) {
  const enabled = capabilities.has(capability);
  const status = enabled ? availableText : unavailableText;
  return `Fake hardware test (${capabilityListText(capabilities)}): ${status}`;
}

export function createDefaultSystemStatus(capabilityInput = defaultFakeHardwareTest) {
  const capabilities = capabilityInput instanceof Set
    ? new Set(capabilityInput)
    : parseFakeHardwareCapabilities(capabilityInput);
  const hasNetwork = capabilities.has('network') || capabilities.has('wifi');
  const hasWifi = capabilities.has('wifi');
  const networkChoices = [];
  if (capabilities.has('network')) {
    networkChoices.push({ id: 'wired', label: 'Wired' });
  }
  if (hasWifi) {
    networkChoices.push(
      { id: 'wifi-home', label: 'Home Wi-Fi' },
      { id: 'wifi-office', label: 'Office Wi-Fi' },
    );
  }
  networkChoices.push({ id: 'offline', label: 'Offline' });
  const selectedNetwork = hasNetwork
    ? networkChoices.find(choice => choice.id !== 'offline')?.id ?? 'offline'
    : null;
  const terminalPreferences = { ...defaultTerminalPreferences };

  return {
    network: {
      available: hasNetwork,
      connected: hasNetwork,
      implementation: fakeImplementation(
        capabilities,
        hasWifi ? 'wifi' : 'network',
        hasWifi ? 'Wi-Fi and wired network choices are fake-controllable.' : 'wired network is fake-controllable.',
        'enable with OLC_HARDWARE_TEST=network or wifi.',
      ),
      kind: selectedNetwork?.startsWith('wifi-') ? 'wifi' : hasNetwork ? 'ethernet' : null,
      ssid: null,
      address: hasNetwork ? '10.0.2.15' : null,
      choices: hasNetwork ? networkChoices : [],
      selected: selectedNetwork,
    },
    power: {
      available: capabilities.has('battery'),
      charging: capabilities.has('battery') ? false : null,
      implementation: fakeImplementation(
        capabilities,
        'battery',
        'battery state is fake-readable.',
        'enable with OLC_HARDWARE_TEST=battery.',
      ),
      percent: capabilities.has('battery') ? 82 : null,
      timeRemainingSeconds: null,
    },
    volume: {
      available: capabilities.has('audio'),
      implementation: fakeImplementation(
        capabilities,
        'audio',
        'volume and mute are fake-controllable.',
        'enable with OLC_HARDWARE_TEST=audio.',
      ),
      muted: capabilities.has('audio') ? false : null,
      percent: capabilities.has('audio') ? 40 : null,
    },
    brightness: {
      available: capabilities.has('brightness'),
      implementation: fakeImplementation(
        capabilities,
        'brightness',
        'brightness is fake-controllable.',
        'enable with OLC_HARDWARE_TEST=brightness.',
      ),
      percent: capabilities.has('brightness') ? 70 : null,
    },
    appearance: {
      available: true,
      implementation: fakeImplementation(
        capabilities,
        'appearance',
        'appearance is fake-controllable and applied to this page.',
        'appearance remains available for the test display.',
      ),
      mode: 'light',
    },
    bluetooth: {
      available: capabilities.has('bluetooth'),
      enabled: capabilities.has('bluetooth') ? false : null,
      implementation: fakeImplementation(
        capabilities,
        'bluetooth',
        'Bluetooth power state is fake-controllable.',
        'enable with OLC_HARDWARE_TEST=bluetooth.',
      ),
      discovering: capabilities.has('bluetooth') ? false : null,
    },
    browser: {
      firefoxVersion: process.env.OLC_FIREFOX_VERSION || 'test-firefox',
      implementation: 'Fake hardware test: Firefox version is supplied by the test environment.',
    },
    terminal: createTerminalStatus(
      terminalPreferences,
      'Fake hardware test: terminal preferences are fake-controllable and applied to new and live terminal pages.',
    ),
  };
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function validationError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function unavailableError(message) {
  const error = new Error(message);
  error.statusCode = 409;
  return error;
}

function requireObject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw validationError('request body must be a JSON object');
  }
}

function validatePercent(value, field = 'percent') {
  if (!Number.isInteger(value) || value < 0 || value > 100) {
    throw validationError(`${field} must be an integer from 0 to 100`);
  }
}

function validateBoolean(value, field) {
  if (typeof value !== 'boolean') {
    throw validationError(`${field} must be true or false`);
  }
}

function validateMode(value) {
  if (value !== 'light' && value !== 'dark') {
    throw validationError('mode must be light or dark');
  }
}

function validateTerminalFont(value) {
  if (!findTerminalFont(value)) {
    throw validationError('font must be one of the available terminal fonts');
  }
}

function validateTerminalColorScheme(value) {
  if (!findTerminalColorScheme(value)) {
    throw validationError('colorScheme must be one of the available light and dark terminal color schemes');
  }
}

function createTerminalStatus(preferences, implementation) {
  return {
    available: true,
    implementation,
    font: preferences.font,
    colorScheme: preferences.colorScheme,
    fonts: terminalFontChoices.map(({ id, label }) => ({ id, label })),
    colorSchemes: terminalColorSchemeChoices.map(({ id, label }) => ({ id, label })),
  };
}

function applyTerminalCommand(preferences, command) {
  requireObject(command);
  if (command.font !== undefined) {
    validateTerminalFont(command.font);
    preferences.font = command.font;
  }
  if (command.colorScheme !== undefined) {
    validateTerminalColorScheme(command.colorScheme);
    preferences.colorScheme = command.colorScheme;
  }
}

function parsePactlPercent(stdout) {
  const match = stdout.match(/(\d+)%/);
  return match ? Number.parseInt(match[1], 10) : null;
}

function parsePactlMute(stdout) {
  if (stdout.includes('yes')) {
    return true;
  }
  if (stdout.includes('no')) {
    return false;
  }
  return null;
}

function parseFirefoxVersion(stdout) {
  const match = stdout.match(/Firefox\s+(.+)/i);
  return match ? match[1].trim() : null;
}

async function safeExecFile(command, args, options = {}) {
  try {
    return await execFileAsync(command, args, { timeout: 2000, ...options });
  } catch {
    return null;
  }
}

export function createFakeSystemAdapter(initialStatus = createDefaultSystemStatus()) {
  let state = clone(initialStatus);

  return {
    async getStatus() {
      return clone(state);
    },

    async network(command) {
      requireObject(command);
      if (!state.network.available) {
        throw unavailableError('network control is unavailable');
      }
      if (command.selected !== undefined) {
        if (!state.network.choices.some(choice => choice.id === command.selected)) {
          throw validationError('selected network choice is not available');
        }
        state.network.selected = command.selected;
        state.network.connected = command.selected !== 'offline';
        state.network.kind = command.selected === 'offline'
          ? null
          : command.selected.startsWith('wifi-') ? 'wifi' : 'ethernet';
        state.network.ssid = command.selected.startsWith('wifi-')
          ? state.network.choices.find(choice => choice.id === command.selected)?.label ?? null
          : null;
        state.network.address = command.selected === 'offline' ? null : '10.0.2.15';
      }
      return clone(state);
    },

    async volume(command) {
      requireObject(command);
      if (!state.volume.available) {
        throw unavailableError('volume control is unavailable');
      }
      if (command.percent !== undefined) {
        validatePercent(command.percent);
        state.volume.percent = command.percent;
      }
      if (command.muted !== undefined) {
        validateBoolean(command.muted, 'muted');
        state.volume.muted = command.muted;
      }
      return clone(state);
    },

    async brightness(command) {
      requireObject(command);
      if (!state.brightness.available) {
        throw unavailableError('brightness control is unavailable');
      }
      validatePercent(command.percent);
      state.brightness.percent = command.percent;
      return clone(state);
    },

    async appearance(command) {
      requireObject(command);
      validateMode(command.mode);
      state.appearance.mode = command.mode;
      return clone(state);
    },

    async terminal(command) {
      applyTerminalCommand(state.terminal, command);
      return clone(state);
    },

    async bluetooth(command) {
      requireObject(command);
      if (!state.bluetooth.available) {
        throw unavailableError('bluetooth control is unavailable');
      }
      validateBoolean(command.enabled, 'enabled');
      state.bluetooth.enabled = command.enabled;
      state.bluetooth.discovering = false;
      return clone(state);
    },
  };
}

export function createRealSystemAdapter(options = {}) {
  const pactl = options.pactl ?? process.env.OLC_PACTL ?? 'pactl';
  const firefoxVersion = options.firefoxVersion ?? process.env.OLC_FIREFOX_VERSION;
  const firefox = options.firefox ?? process.env.OLC_FIREFOX ?? '/run/current-system/sw/bin/firefox';
  const commandEnv = { ...process.env };
  const pulseServer = options.pulseServer ?? process.env.OLC_PULSE_SERVER;
  if (pulseServer) {
    commandEnv.PULSE_SERVER = pulseServer;
  }
  let appearanceMode = 'light';
  const terminalPreferences = { ...defaultTerminalPreferences };

  async function readNetwork() {
    const nets = networkInterfaces();
    const names = Object.keys(nets).filter(name => name !== 'lo');
    const connected = names.find(name => {
      const entries = nets[name] ?? [];
      return entries.some(entry => !entry.internal && entry.family === 'IPv4');
    });
    const address = connected
      ? (nets[connected] ?? []).find(entry => !entry.internal && entry.family === 'IPv4')?.address ?? null
      : null;

    return {
      available: names.length > 0,
      connected: Boolean(connected),
      implementation: 'Real guest adapter: reads non-loopback VM interface state; picker refreshes status.',
      kind: connected ? 'ethernet' : null,
      ssid: null,
      address,
      choices: [
        { id: 'refresh', label: 'Refresh' },
      ],
      selected: connected ? 'refresh' : null,
    };
  }

  async function readPower() {
    try {
      const supplies = await readdir('/sys/class/power_supply');
      const battery = supplies.find(name => name.startsWith('BAT'));
      if (!battery) {
        return {
          available: false,
          charging: null,
          implementation: 'Real guest adapter: checks /sys/class/power_supply; no battery is exposed in this VM.',
          percent: null,
          timeRemainingSeconds: null,
        };
      }

      const [capacity, status] = await Promise.all([
        readFile(`/sys/class/power_supply/${battery}/capacity`, 'utf8').catch(() => null),
        readFile(`/sys/class/power_supply/${battery}/status`, 'utf8').catch(() => null),
      ]);

      return {
        available: true,
        charging: status ? status.trim().toLowerCase() === 'charging' : null,
        implementation: 'Real guest adapter: reads battery state from /sys/class/power_supply; read-only.',
        percent: capacity ? Number.parseInt(capacity.trim(), 10) : null,
        timeRemainingSeconds: null,
      };
    } catch {
      return {
        available: false,
        charging: null,
        implementation: 'Real guest adapter: power status path is unavailable.',
        percent: null,
        timeRemainingSeconds: null,
      };
    }
  }

  async function readVolume() {
    const volume = await safeExecFile(pactl, [ 'get-sink-volume', '@DEFAULT_SINK@' ], { env: commandEnv });
    const mute = await safeExecFile(pactl, [ 'get-sink-mute', '@DEFAULT_SINK@' ], { env: commandEnv });

    if (!volume || !mute) {
      return {
        available: false,
        implementation: 'Real guest adapter: PipeWire/Pulse is configured, but no default sink is available.',
        muted: null,
        percent: null,
      };
    }

    return {
      available: true,
      implementation: 'Real guest adapter: controls the default PipeWire/Pulse sink with pactl.',
      muted: parsePactlMute(mute.stdout),
      percent: parsePactlPercent(volume.stdout),
    };
  }

  async function readBrightness() {
    return {
      available: false,
      implementation: 'Real guest adapter: brightness control is not implemented for the QEMU display yet.',
      percent: null,
    };
  }

  async function readBluetooth() {
    return {
      available: false,
      enabled: null,
      implementation: 'Real guest adapter: Bluetooth hardware is not exposed by the VM wrapper yet.',
      discovering: null,
    };
  }

  async function readBrowser() {
    if (firefoxVersion) {
      return {
        firefoxVersion,
        implementation: 'Real guest adapter: Firefox version is supplied by the packaged system service environment.',
      };
    }

    const version = await safeExecFile(firefox, [ '--version' ], { env: commandEnv });
    return {
      firefoxVersion: version ? parseFirefoxVersion(version.stdout) ?? 'unknown' : 'unknown',
      implementation: 'Real guest adapter: Firefox version is read from the installed Firefox binary.',
    };
  }

  async function getStatus() {
    const [network, power, volume, brightness, bluetooth, browser] = await Promise.all([
      readNetwork(),
      readPower(),
      readVolume(),
      readBrightness(),
      readBluetooth(),
      readBrowser(),
    ]);

    return {
      network,
      power,
      volume,
      brightness,
      appearance: {
        available: true,
        implementation: 'Real guest adapter: appearance is process-local and applied to this page.',
        mode: appearanceMode,
      },
      bluetooth,
      browser,
      terminal: createTerminalStatus(
        terminalPreferences,
        'Real guest adapter: terminal preferences are process-local and applied to new and live terminal pages.',
      ),
    };
  }

  return {
    getStatus,

    async network(command) {
      requireObject(command);
      if (command.selected !== undefined && command.selected !== 'refresh') {
        throw validationError('selected network choice is not available');
      }
      return getStatus();
    },

    async volume(command) {
      requireObject(command);
      const current = await readVolume();
      if (!current.available) {
        throw unavailableError('volume control is unavailable');
      }
      if (command.percent !== undefined) {
        validatePercent(command.percent);
        await execFileAsync(pactl, [ 'set-sink-volume', '@DEFAULT_SINK@', `${command.percent}%` ], { env: commandEnv, timeout: 2000 });
      }
      if (command.muted !== undefined) {
        validateBoolean(command.muted, 'muted');
        await execFileAsync(pactl, [ 'set-sink-mute', '@DEFAULT_SINK@', command.muted ? '1' : '0' ], { env: commandEnv, timeout: 2000 });
      }
      return getStatus();
    },

    async brightness(command) {
      requireObject(command);
      throw unavailableError('brightness control is unavailable');
    },

    async appearance(command) {
      requireObject(command);
      validateMode(command.mode);
      appearanceMode = command.mode;
      return getStatus();
    },

    async terminal(command) {
      applyTerminalCommand(terminalPreferences, command);
      return getStatus();
    },

    async bluetooth(command) {
      requireObject(command);
      throw unavailableError('bluetooth control is unavailable');
    },
  };
}

export function createSystemControls(adapter, options = {}) {
  const clients = new Set();
  const pollIntervalMs = options.pollIntervalMs ?? 2000;
  let lastPublishedStatusJson = null;

  function rememberStatus(status) {
    lastPublishedStatusJson = JSON.stringify(status);
  }

  async function getStatus() {
    const status = await adapter.getStatus();
    rememberStatus(status);
    return status;
  }

  function publish(status) {
    rememberStatus(status);
    for (const client of clients) {
      client(status);
    }
  }

  async function command(area, body) {
    if (typeof adapter[area] !== 'function') {
      throw validationError('unknown system control');
    }

    const status = await adapter[area](body);
    publish(status);
    return status;
  }

  function subscribe(client) {
    clients.add(client);
    return () => {
      clients.delete(client);
    };
  }

  let pollTimer = null;
  if (pollIntervalMs > 0) {
    pollTimer = setInterval(async () => {
      if (clients.size === 0) {
        return;
      }

      try {
        const status = await adapter.getStatus();
        const statusJson = JSON.stringify(status);
        if (statusJson !== lastPublishedStatusJson) {
          publish(status);
        }
      } catch {
        // Transient system read failures should not close live browser streams.
      }
    }, pollIntervalMs);
    pollTimer.unref?.();
  }

  function close() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
    clients.clear();
  }

  return {
    close,
    command,
    getStatus,
    subscribe,
  };
}

export function createSelectedSystemControls(backendName = process.env.OLC_SYSTEM_CONTROLS_BACKEND) {
  const adapter = backendName === 'fake'
    ? createFakeSystemAdapter(createDefaultSystemStatus(process.env.OLC_HARDWARE_TEST))
    : createRealSystemAdapter();

  return createSystemControls(adapter);
}
