import { execFile } from 'node:child_process';
import { readdir, readFile } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export function createDefaultSystemStatus() {
  return {
    network: {
      available: true,
      connected: true,
      implementation: 'Fake backend: selectable wired or offline state for deterministic tests.',
      kind: 'ethernet',
      ssid: null,
      address: '10.0.2.15',
      choices: [
        { id: 'wired', label: 'Wired' },
        { id: 'offline', label: 'Offline' },
      ],
      selected: 'wired',
    },
    power: {
      available: false,
      charging: null,
      implementation: 'Fake backend: no battery is exposed in the default test state.',
      percent: null,
      timeRemainingSeconds: null,
    },
    volume: {
      available: true,
      implementation: 'Fake backend: volume and mute changes are stored in memory.',
      muted: false,
      percent: 40,
    },
    brightness: {
      available: true,
      implementation: 'Fake backend: brightness changes are stored in memory.',
      percent: 70,
    },
    appearance: {
      available: true,
      implementation: 'Fake backend: mode changes are stored in memory and applied to this page.',
      mode: 'light',
    },
    bluetooth: {
      available: true,
      enabled: false,
      implementation: 'Fake backend: Bluetooth power state is stored in memory.',
      discovering: false,
    },
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
      if (command.selected !== undefined) {
        if (!state.network.choices.some(choice => choice.id === command.selected)) {
          throw validationError('selected network choice is not available');
        }
        state.network.selected = command.selected;
        state.network.connected = command.selected !== 'offline';
        state.network.kind = command.selected === 'offline' ? null : 'ethernet';
        state.network.address = command.selected === 'offline' ? null : '10.0.2.15';
      }
      return clone(state);
    },

    async volume(command) {
      requireObject(command);
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

    async bluetooth(command) {
      requireObject(command);
      validateBoolean(command.enabled, 'enabled');
      state.bluetooth.enabled = command.enabled;
      state.bluetooth.discovering = false;
      return clone(state);
    },
  };
}

export function createRealSystemAdapter(options = {}) {
  const pactl = options.pactl ?? process.env.OLC_PACTL ?? 'pactl';
  const commandEnv = { ...process.env };
  const pulseServer = options.pulseServer ?? process.env.OLC_PULSE_SERVER;
  if (pulseServer) {
    commandEnv.PULSE_SERVER = pulseServer;
  }
  let appearanceMode = 'light';

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

  async function getStatus() {
    const [network, power, volume, brightness, bluetooth] = await Promise.all([
      readNetwork(),
      readPower(),
      readVolume(),
      readBrightness(),
      readBluetooth(),
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
    ? createFakeSystemAdapter()
    : createRealSystemAdapter();

  return createSystemControls(adapter);
}
