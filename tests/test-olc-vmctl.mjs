import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import net from 'node:net';
import { spawn } from 'node:child_process';
import test from 'node:test';

const rootDir = new URL('..', import.meta.url).pathname;
const vmctlPath = join(rootDir, 'tools', 'olc-vmctl.mjs');

function startFakeQmpServer(script = {}) {
  const events = [];
  const socketPath = join(tmpdir(), `olc-qmp-test-${process.pid}-${Math.random().toString(16).slice(2)}.sock`);
  const server = net.createServer(socket => {
    socket.setEncoding('utf8');
    socket.write(`${JSON.stringify({ QMP: { version: { qemu: { major: 9, minor: 2, micro: 0 } }, capabilities: [] } })}\n`);
    let buffer = '';
    socket.on('data', chunk => {
      buffer += chunk;
      while (true) {
        const newlineIndex = buffer.indexOf('\n');
        if (newlineIndex === -1) {
          break;
        }

        const line = buffer.slice(0, newlineIndex).trim();
        buffer = buffer.slice(newlineIndex + 1);
        if (!line) {
          continue;
        }

        const message = JSON.parse(line);
        events.push(message);
        const id = message.id;

        if (message.execute === 'qmp_capabilities') {
          socket.write(`${JSON.stringify({ return: {}, id })}\n`);
          continue;
        }

        if (message.execute === 'query-mice') {
          socket.write(`${JSON.stringify({
            return: [ { name: 'QEMU USB Tablet', index: 0, current: true, absolute: true } ],
            id,
          })}\n`);
          continue;
        }

        if (message.execute === 'screendump') {
          const filename = message.arguments.filename;
          void writeFile(filename, Buffer.concat([
            Buffer.from('P6\n640 480\n255\n', 'ascii'),
            Buffer.alloc(640 * 480 * 3),
          ])).then(() => {
            socket.write(`${JSON.stringify({ return: {}, id })}\n`);
          });
          continue;
        }

        socket.write(`${JSON.stringify({
          return: Object.prototype.hasOwnProperty.call(script, message.execute) ? script[message.execute] : {},
          id,
        })}\n`);
      }
    });
  });

  return new Promise((resolve, reject) => {
    server.listen(socketPath, () => {
      resolve({
        events,
        path: socketPath,
        close: () => new Promise(done => server.close(done)),
      });
    });
    server.on('error', reject);
  });
}

async function runVmctl(args, env = {}) {
  const child = spawn(process.execPath, [ vmctlPath, ...args ], {
    env: {
      ...process.env,
      ...env,
    },
    stdio: [ 'ignore', 'pipe', 'pipe' ],
  });

  let stdout = '';
  let stderr = '';
  child.stdout.on('data', chunk => {
    stdout += chunk;
  });
  child.stderr.on('data', chunk => {
    stderr += chunk;
  });

  const exitCode = await new Promise(resolve => child.on('exit', resolve));
  return { exitCode, stdout, stderr };
}

test('key emits send-key through QMP', async () => {
  const server = await startFakeQmpServer();
  try {
    const result = await runVmctl([ '--qmp', server.path, 'key', 'ctrl+alt+delete' ]);
    assert.equal(result.exitCode, 0, result.stderr);
    assert.equal(server.events[1].execute, 'send-key');
    assert.deepEqual(server.events[1].arguments.keys.map(key => key.data), [ 'ctrl', 'alt', 'delete' ]);
  } finally {
    await server.close();
  }
});

test('type emits shifted and direct ASCII keys', async () => {
  const server = await startFakeQmpServer();
  try {
    const result = await runVmctl([ '--qmp', server.path, 'type', 'Az!' ]);
    assert.equal(result.exitCode, 0, result.stderr);
    assert.equal(server.events.filter(event => event.execute === 'send-key').length, 3);
    assert.deepEqual(server.events[1].arguments.keys.map(key => key.data), [ 'shift', 'a' ]);
    assert.deepEqual(server.events[2].arguments.keys.map(key => key.data), [ 'z' ]);
    assert.deepEqual(server.events[3].arguments.keys.map(key => key.data), [ 'shift', '1' ]);
  } finally {
    await server.close();
  }
});

test('move scales screenshot coordinates into absolute pointer events', async () => {
  const server = await startFakeQmpServer();
  try {
    const result = await runVmctl([ '--qmp', server.path, 'move', '320', '240' ]);
    assert.equal(result.exitCode, 0, result.stderr);
    assert.equal(server.events[1].execute, 'query-mice');
    assert.equal(server.events[2].execute, 'screendump');
    assert.equal(server.events[3].execute, 'input-send-event');
    const [ xEvent, yEvent ] = server.events[3].arguments.events;
    assert.equal(xEvent.type, 'abs');
    assert.equal(yEvent.type, 'abs');
    assert.ok(xEvent.data.value >= 16350 && xEvent.data.value <= 16450);
    assert.ok(yEvent.data.value >= 16350 && yEvent.data.value <= 16450);
  } finally {
    await server.close();
  }
});

test('runtime metadata resolves default target', async () => {
  const server = await startFakeQmpServer();
  const runtimeDir = await mkdtemp(join(tmpdir(), 'olc-vmctl-runtime.'));
  try {
    await writeFile(join(runtimeDir, 'vm.json'), JSON.stringify({ qmpSocket: server.path }));
    const result = await runVmctl([ '--runtime-dir', runtimeDir, 'click', '1' ]);
    assert.equal(result.exitCode, 0, result.stderr);
    assert.equal(server.events[1].execute, 'input-send-event');
    assert.deepEqual(server.events[1].arguments.events[0].data, { button: 'left', down: true });
    assert.equal(server.events[2].execute, 'input-send-event');
    assert.deepEqual(server.events[2].arguments.events[0].data, { button: 'left', down: false });
  } finally {
    await server.close();
    await rm(runtimeDir, { recursive: true, force: true });
  }
});

test('raw prints the raw QMP response', async () => {
  const server = await startFakeQmpServer({
    'query-mice': [ { name: 'QEMU USB Tablet', index: 0, current: true, absolute: true } ],
  });
  try {
    const result = await runVmctl([ '--qmp', server.path, 'raw', '{"execute":"query-mice"}' ]);
    assert.equal(result.exitCode, 0, result.stderr);
    const response = JSON.parse(result.stdout.trim());
    assert.equal(response.id, 2);
    assert.equal(response.return[0].name, 'QEMU USB Tablet');
  } finally {
    await server.close();
  }
});
