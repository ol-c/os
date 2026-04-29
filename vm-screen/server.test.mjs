import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import vm from 'node:vm';

async function fakeNoVncTree() {
  const root = await mkdtemp(join(tmpdir(), 'ol-c-novnc-test.'));
  await mkdir(join(root, 'core'), { recursive: true });
  await writeFile(join(root, 'core', 'rfb.js'), 'export default class RFB {}\n');
  return root;
}

function waitForUrl(child) {
  return new Promise((resolve, reject) => {
    let stdout = '';
    let stderr = '';

    child.stdout.on('data', chunk => {
      stdout += chunk;
      const match = stdout.match(/^OLC_VM_SCREEN_URL (.+)$/m);
      if (match) {
        resolve(match[1]);
      }
    });

    child.stderr.on('data', chunk => {
      stderr += chunk;
    });

    child.on('exit', code => {
      reject(new Error(`server exited with ${code}: ${stderr}`));
    });
  });
}

async function startServer(env) {
  const child = spawn(process.execPath, [ new URL('./server.mjs', import.meta.url).pathname ], {
    env: {
      ...process.env,
      OLC_VM_SCREEN_PORT: '0',
      OLC_VM_SCREEN_VNC_HOST: '127.0.0.1',
      OLC_VM_SCREEN_VNC_WS_PORT: '5720',
      ...env,
    },
    stdio: [ 'ignore', 'pipe', 'pipe' ],
  });

  const url = await waitForUrl(child);
  return { child, url };
}

async function stopServer(child) {
  if (child.exitCode !== null) {
    return;
  }

  child.kill('SIGTERM');
  await new Promise(resolve => child.once('exit', resolve));
}

test('serves the VM screen without external assets', async () => {
  const noVncDir = await fakeNoVncTree();
  const { child, url } = await startServer({ OLC_NOVNC_DIR: noVncDir });

  try {
    const html = await fetch(url).then(response => response.text());
    assert.match(html, /window\.OLC_VM_SCREEN/);
    assert.match(html, /"host":"127\.0\.0\.1"/);
    assert.match(html, /"port":5720/);
    assert.match(html, /src="\/screen\.js"/);
    assert.doesNotMatch(html, /https?:\/\/(?!127\.0\.0\.1)/);

    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    assert.match(script, /import RFB from '\/novnc\/core\/rfb\.js'/);
    assert.match(script, /rfb\.clipboardPasteFrom\(text\)/);
    assert.match(script, /rfb\.addEventListener\('clipboard'/);
    assert.match(script, /navigator\.clipboard\?\.writeText/);
    assert.match(script, /window\.addEventListener\('paste'/);
    assert.match(script, /event\.clipboardData\?\.getData\('text\/plain'\)/);
    assert.match(script, /window\.addEventListener\('keydown'/);
    assert.match(script, /event\.ctrlKey && event\.shiftKey && event\.code === 'KeyC'/);
    assert.match(script, /const wheelState = \{ x: 0, y: 0 \}/);
    assert.match(script, /const wheelStep = 50/);
    assert.match(script, /screen\.addEventListener\('wheel'/);
    assert.match(script, /\{ capture: true, passive: false \}/);
    assert.match(script, /event\.stopPropagation\(\)/);
    assert.match(script, /event\.preventDefault\(\)/);
    assert.match(script, /Math\.trunc\(wheelState\[axis\] \/ wheelStep\)/);
    assert.match(script, /wheelState\[axis\] -= steps \* wheelStep/);
    assert.match(script, /for \(let step = 0; step < Math\.abs\(steps\); step \+= 1\)/);
    assert.match(script, /drainWheelAxis\(pos, baseMask, 'x', 1 << 5, 1 << 6\)/);
    assert.match(script, /drainWheelAxis\(pos, baseMask, 'y', 1 << 3, 1 << 4\)/);
    assert.doesNotMatch(script, /https?:\/\/(?!127\.0\.0\.1)/);

    assert.match(html, /id="clipboard-hint"/);
    assert.match(html, /Clipboard ready/);
    assert.doesNotMatch(html, /Paste to VM/);
    assert.doesNotMatch(html, /Copy from VM/);

    const rfb = await fetch(new URL('/novnc/core/rfb.js', url)).then(response => response.text());
    assert.equal(rfb, 'export default class RFB {}\n');
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
  }
});

test('serves embedded VM audio bridge metadata and PCM stream when enabled', async () => {
  const noVncDir = await fakeNoVncTree();
  const { child, url } = await startServer({
    OLC_NOVNC_DIR: noVncDir,
    OLC_VM_SCREEN_AUDIO_ENABLED: '1',
    OLC_VM_SCREEN_AUDIO_BIN: process.execPath,
    OLC_VM_SCREEN_AUDIO_ARGS_JSON: JSON.stringify([
      '-e',
      'process.stdout.write(Buffer.from([0, 0, 255, 127])); setTimeout(() => {}, 1000);',
    ]),
    OLC_VM_SCREEN_AUDIO_SAMPLE_RATE: '48000',
    OLC_VM_SCREEN_AUDIO_CHANNELS: '2',
    OLC_VM_SCREEN_AUDIO_FORMAT: 's16le',
  });

  try {
    const html = await fetch(url).then(response => response.text());
    assert.match(html, /id="audio-hint"/);
    assert.match(html, /Click VM to enable audio/);
    assert.match(html, /"audio":\{"enabled":true,"path":"\/audio-stream","sampleRate":48000,"channels":2,"format":"s16le"\}/);

    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    assert.match(script, /window\.AudioContext \|\| window\.webkitAudioContext/);
    assert.match(script, /fetch\(config\.audio\.path, \{ cache: 'no-store' \}\)/);
    assert.match(script, /createScriptProcessor\(audioProcessorFrameCount, 0, config\.audio\.channels\)/);
    assert.match(script, /ensureAudioBridge\(\);/);
    assert.match(script, /window\.addEventListener\('pointerdown'/);

    const response = await fetch(new URL('/audio-stream', url));
    assert.equal(response.status, 200);
    const reader = response.body.getReader();
    const { value } = await reader.read();
    assert.deepEqual(Array.from(value.slice(0, 4)), [ 0, 0, 255, 127 ]);
    await reader.cancel();
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
  }
});

test('viewer starts audio fetch before gesture and retries audio context creation on pointerdown', async () => {
  const noVncDir = await fakeNoVncTree();
  const { child, url } = await startServer({
    OLC_NOVNC_DIR: noVncDir,
    OLC_VM_SCREEN_AUDIO_ENABLED: '1',
    OLC_VM_SCREEN_AUDIO_BIN: process.execPath,
    OLC_VM_SCREEN_AUDIO_ARGS_JSON: JSON.stringify([ '-e', 'setTimeout(() => {}, 1000);' ]),
  });

  try {
    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    const fetchCalls = [];
    const windowHandlers = new Map();
    const screen = {
      focusCalls: 0,
      focus() {
        this.focusCalls += 1;
      },
      addEventListener() {},
    };
    const status = { textContent: '' };
    const clipboardHint = { textContent: '' };
    const audioHint = { textContent: '' };
    let audioContextInstances = 0;
    let audioResumeCalls = 0;

    class FakeRFB {
      constructor() {
        this._rfbConnectionState = 'connected';
        this._viewOnly = false;
      }

      addEventListener() {}

      clipboardPasteFrom() {}

      focus() {}
    }

    const context = {
      FakeRFB,
      fetch(urlPath) {
        fetchCalls.push(urlPath);
        return new Promise(() => {});
      },
      document: {
        getElementById(id) {
          return {
            screen,
            status,
            'clipboard-hint': clipboardHint,
            'audio-hint': audioHint,
          }[id];
        },
      },
      navigator: {},
      window: {
        OLC_VM_SCREEN: {
          host: '127.0.0.1',
          port: 5720,
          audio: {
            enabled: true,
            path: '/audio-stream',
            sampleRate: 48000,
            channels: 2,
            format: 's16le',
          },
        },
        location: { protocol: 'http:' },
        AudioContext: class FailingAudioContext {
          constructor() {
            throw new Error('gesture required');
          }
        },
        addEventListener(type, handler) {
          windowHandlers.set(type, handler);
        },
        clearTimeout() {},
        setTimeout() {
          return 1;
        },
      },
    };

    vm.runInNewContext(
      script.replace("import RFB from '/novnc/core/rfb.js';", 'const RFB = FakeRFB;'),
      context,
    );

    assert.deepEqual(fetchCalls, [ '/audio-stream' ]);
    assert.equal(audioHint.textContent, 'Click VM to enable audio');
    assert.equal(screen.focusCalls, 1);

    context.window.AudioContext = class WorkingAudioContext {
      constructor() {
        audioContextInstances += 1;
        this.state = 'suspended';
        this.destination = {};
      }

      createScriptProcessor() {
        return {
          connect() {},
          onaudioprocess: null,
        };
      }

      async resume() {
        audioResumeCalls += 1;
        this.state = 'running';
      }
    };

    const pointerdown = windowHandlers.get('pointerdown');
    assert.equal(typeof pointerdown, 'function');
    pointerdown();
    await Promise.resolve();
    await Promise.resolve();

    assert.equal(audioContextInstances, 1);
    assert.equal(audioResumeCalls, 1);
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
  }
});

test('viewer trims stale pre-gesture audio to keep playback near live', async () => {
  const noVncDir = await fakeNoVncTree();
  const { child, url } = await startServer({
    OLC_NOVNC_DIR: noVncDir,
    OLC_VM_SCREEN_AUDIO_ENABLED: '1',
    OLC_VM_SCREEN_AUDIO_BIN: process.execPath,
    OLC_VM_SCREEN_AUDIO_ARGS_JSON: JSON.stringify([ '-e', 'setTimeout(() => {}, 1000);' ]),
  });

  try {
    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    const windowHandlers = new Map();
    const screen = {
      focus() {},
      addEventListener() {},
    };
    const status = { textContent: '' };
    const clipboardHint = { textContent: '' };
    const audioHint = { textContent: '' };
    const oldSample = 1000;
    const liveSample = 20000;
    const sampleRate = 48000;
    const channels = 2;
    const preGestureAudio = Buffer.alloc(sampleRate * channels * 2);
    let processor = null;

    for (let frame = 0; frame < sampleRate; frame += 1) {
      const sample = frame < sampleRate - 5000 ? oldSample : liveSample;
      for (let channel = 0; channel < channels; channel += 1) {
        preGestureAudio.writeInt16LE(sample, (frame * channels + channel) * 2);
      }
    }

    class FakeRFB {
      constructor() {
        this._rfbConnectionState = 'connected';
        this._viewOnly = false;
      }

      addEventListener() {}

      clipboardPasteFrom() {}

      focus() {}
    }

    const context = {
      FakeRFB,
      fetch() {
        let sent = false;
        return Promise.resolve({
          ok: true,
          body: {
            getReader() {
              return {
                read() {
                  if (sent) {
                    return new Promise(() => {});
                  }
                  sent = true;
                  return Promise.resolve({
                    done: false,
                    value: new Uint8Array(preGestureAudio),
                  });
                },
              };
            },
          },
        });
      },
      document: {
        getElementById(id) {
          return {
            screen,
            status,
            'clipboard-hint': clipboardHint,
            'audio-hint': audioHint,
          }[id];
        },
      },
      navigator: {},
      window: {
        OLC_VM_SCREEN: {
          host: '127.0.0.1',
          port: 5720,
          audio: {
            enabled: true,
            path: '/audio-stream',
            sampleRate,
            channels,
            format: 's16le',
          },
        },
        location: { protocol: 'http:' },
        AudioContext: class WorkingAudioContext {
          constructor() {
            this.state = 'suspended';
            this.destination = {};
          }

          createScriptProcessor(frameCount) {
            processor = {
              frameCount,
              connect() {},
              onaudioprocess: null,
            };
            return processor;
          }

          async resume() {
            this.state = 'running';
          }
        },
        addEventListener(type, handler) {
          windowHandlers.set(type, handler);
        },
        clearTimeout() {},
        setTimeout() {
          return 1;
        },
      },
    };

    vm.runInNewContext(
      script.replace("import RFB from '/novnc/core/rfb.js';", 'const RFB = FakeRFB;'),
      context,
    );

    for (let tick = 0; tick < 10; tick += 1) {
      await Promise.resolve();
    }

    const pointerdown = windowHandlers.get('pointerdown');
    pointerdown();
    for (let tick = 0; tick < 3; tick += 1) {
      await Promise.resolve();
    }

    assert.equal(processor.frameCount, 1024);
    const left = new Float32Array(processor.frameCount);
    const right = new Float32Array(processor.frameCount);
    processor.onaudioprocess({
      outputBuffer: {
        getChannelData(channel) {
          return channel === 0 ? left : right;
        },
      },
    });

    assert.ok(left[0] > 0.5, `expected live audio tail, got ${left[0]}`);
    assert.ok(right[0] > 0.5, `expected live audio tail, got ${right[0]}`);
    assert.notEqual(audioHint.textContent, 'Audio buffering');
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
  }
});

test('viewer wheel capture drains repeated steps and preserves remainder', async () => {
  const noVncDir = await fakeNoVncTree();
  const { child, url } = await startServer({ OLC_NOVNC_DIR: noVncDir });

  try {
    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    const wheelEvents = [];
    const sentButtons = [];
    const screen = {
      focus() {},
      addEventListener(type, handler, options) {
        if (type === 'wheel') {
          wheelEvents.push({ handler, options });
        }
      },
    };
    const status = { textContent: '' };
    const clipboardHint = { textContent: '' };
    const canvas = {
      getBoundingClientRect() {
        return {
          left: 10,
          top: 20,
          right: 810,
          bottom: 620,
          width: 800,
          height: 600,
        };
      },
    };

    class FakeRFB {
      constructor() {
        this._rfbConnectionState = 'connected';
        this._viewOnly = false;
        this._canvas = canvas;
      }

      addEventListener() {}

      clipboardPasteFrom() {}

      focus() {}

      _handleMouseButton(x, y, mask) {
        sentButtons.push({ x, y, mask });
      }
    }

    const context = {
      FakeRFB,
      WheelEvent: {
        DOM_DELTA_PIXEL: 0,
      },
      document: {
        getElementById(id) {
          return { screen, status, 'clipboard-hint': clipboardHint }[id];
        },
      },
      navigator: {},
      window: {
        OLC_VM_SCREEN: { host: '127.0.0.1', port: 5720 },
        location: { protocol: 'http:' },
        addEventListener() {},
        clearTimeout() {},
        setTimeout() {
          return 1;
        },
      },
    };

    vm.runInNewContext(
      script.replace("import RFB from '/novnc/core/rfb.js';", 'const RFB = FakeRFB;'),
      context,
    );

    assert.equal(wheelEvents.length, 1);
    assert.equal(wheelEvents[0].options.capture, true);
    assert.equal(wheelEvents[0].options.passive, false);

    const eventState = { stopped: 0, prevented: 0 };
    function wheelEvent(deltaX, deltaY) {
      return {
        deltaX,
        deltaY,
        deltaMode: 0,
        buttons: 0,
        clientX: 110,
        clientY: 220,
        target: canvas,
        stopPropagation() {
          eventState.stopped += 1;
        },
        preventDefault() {
          eventState.prevented += 1;
        },
      };
    }

    wheelEvents[0].handler(wheelEvent(120, -55));
    assert.deepEqual(sentButtons.map(event => event.mask), [ 0x40, 0, 0x40, 0, 0x08, 0 ]);

    wheelEvents[0].handler(wheelEvent(29, 54));
    assert.deepEqual(sentButtons.map(event => event.mask), [ 0x40, 0, 0x40, 0, 0x08, 0 ]);

    wheelEvents[0].handler(wheelEvent(1, 1));
    assert.deepEqual(sentButtons.map(event => event.mask), [
      0x40, 0, 0x40, 0, 0x08, 0,
      0x40, 0, 0x10, 0,
    ]);
    assert.deepEqual(sentButtons.map(event => [ event.x, event.y ]), [
      [ 100, 200 ], [ 100, 200 ], [ 100, 200 ], [ 100, 200 ], [ 100, 200 ],
      [ 100, 200 ], [ 100, 200 ], [ 100, 200 ], [ 100, 200 ], [ 100, 200 ],
    ]);
    assert.deepEqual(eventState, { stopped: 3, prevented: 3 });
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
  }
});

test('rejects non-local VNC targets by default', async () => {
  const noVncDir = await fakeNoVncTree();
  const child = spawn(process.execPath, [ new URL('./server.mjs', import.meta.url).pathname ], {
    env: {
      ...process.env,
      OLC_NOVNC_DIR: noVncDir,
      OLC_VM_SCREEN_VNC_HOST: '192.0.2.1',
      OLC_VM_SCREEN_VNC_WS_PORT: '5720',
    },
    stdio: [ 'ignore', 'ignore', 'pipe' ],
  });

  const stderr = await new Promise(resolve => {
    let output = '';
    child.stderr.on('data', chunk => {
      output += chunk;
    });
    child.on('exit', () => resolve(output));
  });

  assert.match(stderr, /refusing to serve a non-local VNC target/);
  await rm(noVncDir, { recursive: true, force: true });
});
