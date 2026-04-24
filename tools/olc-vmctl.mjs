#!/usr/bin/env node

import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import net from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function usage() {
  console.log(`Usage: olc-vmctl [--qmp PATH] [--runtime-dir DIR] <command> [args]

Commands:
  key <name>              Send a key or key chord such as enter or ctrl+alt+delete.
  type <text>             Type ASCII text with common punctuation support.
  move <x> <y>            Move the absolute pointer to screenshot pixel coordinates.
  click <button>          Click a button: 1, 2, 3, left, middle, right.
  mouse-press <button>    Press and hold a pointer button.
  mouse-release <button>  Release a pointer button.
  screenshot <path>       Save a PPM screenshot through QMP screendump.
  wait <seconds>          Sleep without talking to the VM.
  raw <json>              Send raw QMP JSON and print the raw response.

Options:
  --qmp PATH              QMP unix socket path.
  --runtime-dir DIR       Directory containing vm.json metadata.
  --help                  Show this help text.
`);
}

function parseArgs(argv) {
  let qmpSocket = process.env.OLC_VM_QMP_SOCKET || '';
  let runtimeDir = process.env.OLC_VM_RUNTIME_DIR || '/var/lib/ol-c/vms/current';
  const positional = [];

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help') {
      usage();
      process.exit(0);
    }
    if (arg === '--qmp') {
      qmpSocket = argv[index + 1] || '';
      index += 1;
      continue;
    }
    if (arg === '--runtime-dir') {
      runtimeDir = argv[index + 1] || '';
      index += 1;
      continue;
    }
    positional.push(arg);
  }

  return { qmpSocket, runtimeDir, positional };
}

function resolveTarget(qmpSocket, runtimeDir) {
  if (qmpSocket) {
    return qmpSocket;
  }

  try {
    const metadata = JSON.parse(readFileSync(join(runtimeDir, 'vm.json'), 'utf8'));
    if (metadata?.qmpSocket) {
      return metadata.qmpSocket;
    }
  } catch {
    // fall through
  }

  fail(`unable to resolve a QMP socket. Set --qmp PATH or provide vm metadata in ${join(runtimeDir, 'vm.json')}`);
}

class QmpClient {
  constructor(socketPath) {
    this.socketPath = socketPath;
    this.socket = null;
    this.buffer = '';
    this.pending = new Map();
    this.nextId = 1;
    this.greetingPromise = null;
    this.resolveGreeting = null;
  }

  async connect() {
    this.greetingPromise = new Promise(resolve => {
      this.resolveGreeting = resolve;
    });

    await new Promise((resolve, reject) => {
      this.socket = net.createConnection(this.socketPath);
      this.socket.setEncoding('utf8');
      this.socket.on('data', chunk => this.onData(chunk));
      this.socket.on('error', reject);
      this.socket.on('connect', resolve);
    });

    const greeting = await this.greetingPromise;
    if (!greeting?.QMP) {
      fail(`unexpected QMP greeting from ${this.socketPath}`);
    }
    await this.execute('qmp_capabilities');
  }

  onData(chunk) {
    this.buffer += chunk;
    while (true) {
      const newlineIndex = this.buffer.indexOf('\n');
      if (newlineIndex === -1) {
        break;
      }

      const line = this.buffer.slice(0, newlineIndex).trim();
      this.buffer = this.buffer.slice(newlineIndex + 1);
      if (!line) {
        continue;
      }

      let message;
      try {
        message = JSON.parse(line);
      } catch {
        continue;
      }

      if (message.QMP) {
        this.resolveGreeting?.(message);
        this.resolveGreeting = null;
        continue;
      }

      if (!Object.prototype.hasOwnProperty.call(message, 'id')) {
        continue;
      }

      const pending = this.pending.get(message.id);
      if (!pending) {
        continue;
      }

      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(new Error(message.error.desc || JSON.stringify(message.error)));
      } else {
        pending.resolve(message);
      }
    }
  }

  execute(command, args = undefined) {
    const id = this.nextId++;
    const payload = { execute: command, id };
    if (args !== undefined) {
      payload.arguments = args;
    }

    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.write(`${JSON.stringify(payload)}\n`);
    });
  }

  close() {
    if (this.socket) {
      this.socket.end();
      this.socket.destroy();
      this.socket = null;
    }
  }
}

function normalizeKeyName(name) {
  const normalized = String(name).trim().toLowerCase();
  const aliases = new Map([
    ['control', 'ctrl'],
    ['return', 'ret'],
    ['enter', 'ret'],
    ['escape', 'esc'],
    ['space', 'spc'],
    [' ', 'spc'],
    ['pageup', 'pgup'],
    ['pagedown', 'pgdn'],
    ['super', 'meta_l'],
    ['meta', 'meta_l'],
    ['win', 'meta_l'],
  ]);

  if (aliases.has(normalized)) {
    return aliases.get(normalized);
  }

  if (/^f([1-9]|1[0-2])$/.test(normalized)) {
    return normalized;
  }

  return normalized;
}

const directCharMap = new Map([
  [' ', 'spc'],
  ['\n', 'ret'],
  ['\t', 'tab'],
  ['-', 'minus'],
  ['=', 'equal'],
  ['[', 'bracket_left'],
  [']', 'bracket_right'],
  ['\\', 'backslash'],
  [';', 'semicolon'],
  ['\'', 'apostrophe'],
  [',', 'comma'],
  ['.', 'dot'],
  ['/', 'slash'],
  ['`', 'grave_accent'],
]);

const shiftCharMap = new Map([
  ['!', '1'],
  ['@', '2'],
  ['#', '3'],
  ['$', '4'],
  ['%', '5'],
  ['^', '6'],
  ['&', '7'],
  ['*', '8'],
  ['(', '9'],
  [')', '0'],
  ['_', 'minus'],
  ['+', 'equal'],
  ['{', 'bracket_left'],
  ['}', 'bracket_right'],
  ['|', 'backslash'],
  [':', 'semicolon'],
  ['"', 'apostrophe'],
  ['<', 'comma'],
  ['>', 'dot'],
  ['?', 'slash'],
  ['~', 'grave_accent'],
]);

const buttonMap = new Map([
  ['1', 'left'],
  ['2', 'middle'],
  ['3', 'right'],
  ['left', 'left'],
  ['middle', 'middle'],
  ['right', 'right'],
  ['wheel-up', 'wheel-up'],
  ['wheel-down', 'wheel-down'],
  ['wheel-left', 'wheel-left'],
  ['wheel-right', 'wheel-right'],
]);

function keySpecForChar(char) {
  const shifted = shiftCharMap.get(char);
  if (shifted) {
    return [ 'shift', shifted ];
  }
  if (char >= 'a' && char <= 'z') {
    return [ char ];
  }
  if (char >= 'A' && char <= 'Z') {
    return [ 'shift', char.toLowerCase() ];
  }
  if (char >= '0' && char <= '9') {
    return [ char ];
  }
  const direct = directCharMap.get(char);
  if (direct) {
    return [ direct ];
  }
  return null;
}

async function ensureAbsolutePointer(client) {
  const response = await client.execute('query-mice');
  const mice = response.return || [];
  const current = mice.find(mouse => mouse.current) || mice[0];
  if (!current) {
    fail('QMP did not report an active mouse device');
  }
  if (!current.absolute) {
    fail(`active mouse device is not absolute: ${current.name}`);
  }
}

async function screenshotSize(client) {
  const dir = mkdtempSync(join(tmpdir(), 'olc-vmctl.'));
  const path = join(dir, 'screen.ppm');
  try {
    await client.execute('screendump', { filename: path });
    const buffer = readFileSync(path);
    const header = buffer.slice(0, 128).toString('ascii');
    const match = header.match(/^P6\s+(\d+)\s+(\d+)\s+255\s/s);
    if (!match) {
      fail(`unable to parse screendump header from ${path}`);
    }
    return {
      width: Number.parseInt(match[1], 10),
      height: Number.parseInt(match[2], 10),
    };
  } finally {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      // ignore cleanup failure
    }
  }
}

function scaleAbsolute(value, maxPixel) {
  if (!Number.isInteger(value)) {
    fail('pointer coordinates must be integers');
  }
  if (value < 0 || value >= maxPixel) {
    fail(`pointer coordinate ${value} is outside the screenshot bounds 0..${Math.max(0, maxPixel - 1)}`);
  }
  if (maxPixel <= 1) {
    return 0;
  }
  return Math.round((value / (maxPixel - 1)) * 0x7fff);
}

async function sendKeyCommand(client, arg) {
  const chord = String(arg).split('+').map(normalizeKeyName).filter(Boolean);
  if (chord.length === 0) {
    fail('key requires a name');
  }
  await client.execute('send-key', {
    keys: chord.map(key => ({ type: 'qcode', data: key })),
  });
}

async function sendTypeCommand(client, text) {
  for (const char of text) {
    const keys = keySpecForChar(char);
    if (!keys) {
      fail(`unsupported character for type: ${JSON.stringify(char)}`);
    }
    await client.execute('send-key', {
      keys: keys.map(key => ({ type: 'qcode', data: key })),
    });
  }
}

async function sendMoveCommand(client, x, y) {
  await ensureAbsolutePointer(client);
  const size = await screenshotSize(client);
  await client.execute('input-send-event', {
    events: [
      { type: 'abs', data: { axis: 'x', value: scaleAbsolute(x, size.width) } },
      { type: 'abs', data: { axis: 'y', value: scaleAbsolute(y, size.height) } },
    ],
  });
}

async function sendButtonCommand(client, rawButton, down) {
  const button = buttonMap.get(String(rawButton).toLowerCase());
  if (!button) {
    fail(`unsupported mouse button: ${rawButton}`);
  }
  await client.execute('input-send-event', {
    events: [
      { type: 'btn', data: { button, down } },
    ],
  });
}

async function main() {
  const { qmpSocket, runtimeDir, positional } = parseArgs(process.argv.slice(2));
  const [ command, ...args ] = positional;
  if (!command) {
    usage();
    process.exit(1);
  }

  if (command === 'wait') {
    const seconds = Number.parseFloat(args[0] || '');
    if (!Number.isFinite(seconds) || seconds < 0) {
      fail('wait requires a non-negative number of seconds');
    }
    await new Promise(resolve => setTimeout(resolve, seconds * 1000));
    return;
  }

  const client = new QmpClient(resolveTarget(qmpSocket, runtimeDir));
  await client.connect();

  try {
    if (command === 'key') {
      await sendKeyCommand(client, args[0] || '');
      return;
    }
    if (command === 'type') {
      await sendTypeCommand(client, args.join(' '));
      return;
    }
    if (command === 'move') {
      await sendMoveCommand(
        client,
        Number.parseInt(args[0] || '', 10),
        Number.parseInt(args[1] || '', 10),
      );
      return;
    }
    if (command === 'click') {
      await sendButtonCommand(client, args[0] || '', true);
      await sendButtonCommand(client, args[0] || '', false);
      return;
    }
    if (command === 'mouse-press') {
      await sendButtonCommand(client, args[0] || '', true);
      return;
    }
    if (command === 'mouse-release') {
      await sendButtonCommand(client, args[0] || '', false);
      return;
    }
    if (command === 'screenshot') {
      const path = args[0];
      if (!path) {
        fail('screenshot requires a destination path');
      }
      await client.execute('screendump', { filename: path });
      console.log(path);
      return;
    }
    if (command === 'raw') {
      const payloadText = args.join(' ').trim();
      if (!payloadText) {
        fail('raw requires a JSON payload');
      }
      let payload;
      try {
        payload = JSON.parse(payloadText);
      } catch (error) {
        fail(`raw payload is not valid JSON: ${error.message}`);
      }
      if (!payload.execute) {
        fail('raw payload must contain an execute field');
      }
      const response = await client.execute(payload.execute, payload.arguments);
      console.log(JSON.stringify(response));
      return;
    }
    fail(`unknown command: ${command}`);
  } finally {
    client.close();
  }
}

await main();
