import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
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

async function drainMicrotasks(ticks = 8) {
  for (let tick = 0; tick < ticks; tick += 1) {
    await Promise.resolve();
  }
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
    assert.match(html, /Noto Sans/);
    assert.match(html, /Noto Color Emoji/);
    assert.doesNotMatch(html, /https?:\/\/(?!127\.0\.0\.1)/);

    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    assert.match(script, /import RFB from '\/novnc\/core\/rfb\.js'/);
    assert.match(script, /rfb\.clipboardPasteFrom\(text\)/);
    assert.match(script, /const guestPasteDelayMs = 100/);
    assert.match(script, /rfb\.sendKey\(XK_Control_L, 'ControlLeft', true\)/);
    assert.match(script, /rfb\.sendKey\(XK_Super_L, 'MetaLeft', false\)/);
    assert.match(script, /rfb\.sendKey\(XK_v, 'KeyV', true\)/);
    assert.match(script, /addEventListener\('clipboard'/);
    assert.match(script, /navigator\.clipboard\?\.writeText/);
    assert.match(script, /navigator\.clipboard\?\.readText/);
    assert.match(script, /window\.addEventListener\('paste'/);
    assert.match(script, /event\.clipboardData\?\.getData\('text\/plain'\)/);
    assert.match(script, /window\.addEventListener\('keydown'/);
    assert.match(script, /window\.addEventListener\('keydown', event => \{[\s\S]*\}, \{ capture: true \}\);/);
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

    assert.match(html, /id="viewer-message"[^>]*hidden/);
    assert.doesNotMatch(html, /id="status"/);
    assert.doesNotMatch(html, /id="clipboard-hint"/);
    assert.doesNotMatch(html, /id="audio-hint"/);
    assert.doesNotMatch(html, /Connecting/);
    assert.doesNotMatch(html, /Clipboard ready/);
    assert.doesNotMatch(html, /Click VM to enable audio/);
    assert.doesNotMatch(html, /Paste to VM/);
    assert.doesNotMatch(html, /Copy from VM/);

    const rfb = await fetch(new URL('/novnc/core/rfb.js', url)).then(response => response.text());
    assert.equal(rfb, 'export default class RFB {}\n');
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
  }
});

test('serves lifecycle state and accepts local power-on requests', async () => {
  const noVncDir = await fakeNoVncTree();
  const lifecycleDir = await mkdtemp(join(tmpdir(), 'ol-c-lifecycle-test.'));
  const stateFile = join(lifecycleDir, 'state.json');
  const commandDir = join(lifecycleDir, 'commands');
  await mkdir(commandDir, { recursive: true });
  await writeFile(stateFile, JSON.stringify({
    state: 'powered-off',
    lastAction: 'shutdown',
    message: 'The guest is powered off.',
  }));
  const { child, url } = await startServer({
    OLC_NOVNC_DIR: noVncDir,
    OLC_VM_SCREEN_STATE_FILE: stateFile,
    OLC_VM_SCREEN_COMMAND_DIR: commandDir,
  });

  try {
    const html = await fetch(url).then(response => response.text());
    assert.match(html, /id="power-panel"[^>]*hidden/);
    assert.match(html, /id="power-on-button"/);
    assert.match(html, /"lifecycle":\{"enabled":true\}/);

    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    assert.match(script, /fetch\('\/api\/vm\/state'/);
    assert.match(script, /fetch\('\/api\/vm\/power-on', \{ method: 'POST' \}\)/);
    assert.match(script, /VM powered off/);

    const state = await fetch(new URL('/api/vm/state', url)).then(response => response.json());
    assert.equal(state.state, 'powered-off');
    assert.equal(state.lastAction, 'shutdown');

    const response = await fetch(new URL('/api/vm/power-on', url), { method: 'POST' });
    assert.equal(response.status, 202);
    const commands = await readdir(commandDir);
    assert.equal(commands.length, 1);
    const command = JSON.parse(await readFile(join(commandDir, commands[0]), 'utf8'));
    assert.equal(command.command, 'power-on');
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
    await rm(lifecycleDir, { recursive: true, force: true });
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
    assert.match(html, /id="viewer-message"[^>]*hidden/);
    assert.doesNotMatch(html, /id="audio-hint"/);
    assert.doesNotMatch(html, /Click VM to enable audio/);
    assert.match(html, /"audio":\{"enabled":true,"path":"\/audio-stream","sampleRate":48000,"channels":2,"format":"s16le"\}/);

    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    assert.match(script, /window\.AudioContext \|\| window\.webkitAudioContext/);
    assert.match(script, /fetch\(config\.audio\.path, \{ cache: 'no-store' \}\)/);
    assert.match(script, /createScriptProcessor\(audioProcessorFrameCount, 0, config\.audio\.channels\)/);
    assert.match(script, /ensureAudioBridge\(\);/);
    assert.match(script, /window\.addEventListener\('pointerdown'/);
    assert.doesNotMatch(script, /Click VM to enable audio/);

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

test('viewer keeps routine connection and clipboard events out of the viewport chrome', async () => {
  const noVncDir = await fakeNoVncTree();
  const { child, url } = await startServer({ OLC_NOVNC_DIR: noVncDir });

  try {
    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    const rfbHandlers = new Map();
    const windowHandlers = new Map();
    const screen = {
      focus() {},
      addEventListener() {},
    };
    const viewerMessage = { textContent: '', hidden: true };
    const document = {
      title: 'ol-c VM',
      getElementById(id) {
        return { screen, 'viewer-message': viewerMessage }[id];
      },
    };
    let hostClipboardText = '';
    let pastedText = '';
    let pastePrevented = false;
    let pasteStopped = false;
    let rfbFocusCalls = 0;
    const timers = [];
    const keyEvents = [];

    class FakeRFB {
      constructor() {
        this._rfbConnectionState = 'connected';
        this._viewOnly = false;
      }

      addEventListener(type, handler) {
        rfbHandlers.set(type, handler);
      }

      clipboardPasteFrom(text) {
        pastedText = text;
      }

      focus() {
        rfbFocusCalls += 1;
      }

      sendKey(keysym, code, down) {
        keyEvents.push({ keysym, code, down });
      }
    }

    const context = {
      FakeRFB,
      document,
      navigator: {
        clipboard: {
          async writeText(text) {
            hostClipboardText = text;
          },
        },
      },
      window: {
        OLC_VM_SCREEN: { host: '127.0.0.1', port: 5720, audio: { enabled: false } },
        location: { protocol: 'http:' },
        addEventListener(type, handler) {
          windowHandlers.set(type, handler);
        },
        clearTimeout() {},
        setTimeout(callback, delayMs) {
          timers.push({ callback, delayMs });
          return timers.length;
        },
      },
    };

    vm.runInNewContext(
      script.replace("import RFB from '/novnc/core/rfb.js';", 'const RFB = FakeRFB;'),
      context,
    );

    rfbHandlers.get('connect')();
    assert.equal(document.title, 'ol-c VM');
    assert.equal(viewerMessage.hidden, true);
    assert.equal(viewerMessage.textContent, '');

    rfbHandlers.get('clipboard')({ detail: { text: 'from guest' } });
    await Promise.resolve();
    assert.equal(hostClipboardText, 'from guest');
    assert.equal(viewerMessage.hidden, true);
    assert.equal(viewerMessage.textContent, '');

    windowHandlers.get('paste')({
      clipboardData: {
        getData(type) {
          assert.equal(type, 'text/plain');
          return 'from host';
        },
      },
      stopPropagation() {
        pasteStopped = true;
      },
      preventDefault() {
        pastePrevented = true;
      },
    });
    assert.equal(pastedText, 'from host');
    assert.equal(pastePrevented, true);
    assert.equal(pasteStopped, true);
    assert.equal(rfbFocusCalls, 1);
    assert.equal(timers[0].delayMs, 100);
    timers.shift().callback();
    await Promise.resolve();
    assert.deepEqual(keyEvents, [
      { keysym: 0xffe3, code: 'ControlLeft', down: true },
      { keysym: 0x0076, code: 'KeyV', down: true },
      { keysym: 0x0076, code: 'KeyV', down: false },
      { keysym: 0xffe3, code: 'ControlLeft', down: false },
    ]);
    assert.equal(viewerMessage.hidden, true);
    assert.equal(viewerMessage.textContent, '');

    rfbHandlers.get('disconnect')({ detail: { clean: false } });
    assert.equal(document.title, 'ol-c VM - Disconnected unexpectedly');
    assert.equal(viewerMessage.hidden, false);
    assert.equal(viewerMessage.textContent, 'Disconnected unexpectedly');
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
  }
});

test('viewer intercepts keyboard paste shortcuts and sends guest paste keys', async () => {
  const noVncDir = await fakeNoVncTree();
  const { child, url } = await startServer({ OLC_NOVNC_DIR: noVncDir });

  try {
    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    const windowHandlers = new Map();
    const timers = [];
    const operations = [];
    const keyEvents = [];
    let hostClipboardText = 'from ctrl';
    let readCalls = 0;
    let prevented = 0;
    let stopped = 0;
    const screen = {
      focus() {},
      addEventListener() {},
    };
    const viewerMessage = { textContent: '', hidden: true };

    class FakeRFB {
      constructor() {
        this._rfbConnectionState = 'connected';
        this._viewOnly = false;
      }

      addEventListener() {}

      clipboardPasteFrom(text) {
        operations.push({ type: 'clipboard', text });
      }

      focus() {
        operations.push({ type: 'focus' });
      }

      sendKey(keysym, code, down) {
        keyEvents.push({ keysym, code, down });
      }
    }

    const context = {
      FakeRFB,
      document: {
        getElementById(id) {
          return { screen, 'viewer-message': viewerMessage }[id];
        },
      },
      navigator: {
        clipboard: {
          async readText() {
            readCalls += 1;
            return hostClipboardText;
          },
        },
      },
      window: {
        OLC_VM_SCREEN: { host: '127.0.0.1', port: 5720, audio: { enabled: false } },
        location: { protocol: 'http:' },
        addEventListener(type, handler, options) {
          windowHandlers.set(type, { handler, options });
        },
        clearTimeout() {},
        setTimeout(callback, delayMs) {
          timers.push({ callback, delayMs });
          return timers.length;
        },
      },
    };

    vm.runInNewContext(
      script.replace("import RFB from '/novnc/core/rfb.js';", 'const RFB = FakeRFB;'),
      context,
    );

    const keydown = windowHandlers.get('keydown');
    assert.equal(typeof keydown.handler, 'function');
    assert.equal(keydown.options.capture, true);

    function pasteKeyEvent(overrides = {}) {
      return {
        code: 'KeyV',
        ctrlKey: true,
        metaKey: false,
        altKey: false,
        repeat: false,
        preventDefault() {
          prevented += 1;
        },
        stopPropagation() {
          stopped += 1;
        },
        ...overrides,
      };
    }

    keydown.handler(pasteKeyEvent());
    await drainMicrotasks();
    assert.equal(readCalls, 1);
    assert.deepEqual(operations, [
      { type: 'clipboard', text: 'from ctrl' },
      { type: 'focus' },
    ]);
    assert.equal(keyEvents.length, 0);
    assert.equal(timers[0].delayMs, 100);
    timers.shift().callback();
    await drainMicrotasks();
    assert.deepEqual(keyEvents, [
      { keysym: 0xffe3, code: 'ControlLeft', down: true },
      { keysym: 0x0076, code: 'KeyV', down: true },
      { keysym: 0x0076, code: 'KeyV', down: false },
      { keysym: 0xffe3, code: 'ControlLeft', down: false },
    ]);

    hostClipboardText = 'from meta';
    operations.length = 0;
    keyEvents.length = 0;
    keydown.handler(pasteKeyEvent({ ctrlKey: false, metaKey: true }));
    await drainMicrotasks();
    assert.equal(readCalls, 2);
    assert.deepEqual(operations, [
      { type: 'clipboard', text: 'from meta' },
      { type: 'focus' },
    ]);
    timers.shift().callback();
    await drainMicrotasks();
    assert.deepEqual(keyEvents, [
      { keysym: 0xffeb, code: 'MetaLeft', down: false },
      { keysym: 0xffec, code: 'MetaRight', down: false },
      { keysym: 0xffe3, code: 'ControlLeft', down: true },
      { keysym: 0x0076, code: 'KeyV', down: true },
      { keysym: 0x0076, code: 'KeyV', down: false },
      { keysym: 0xffe3, code: 'ControlLeft', down: false },
    ]);

    operations.length = 0;
    keyEvents.length = 0;
    keydown.handler(pasteKeyEvent({ repeat: true }));
    await drainMicrotasks();
    assert.equal(readCalls, 2);
    assert.deepEqual(operations, []);
    assert.deepEqual(keyEvents, []);
    assert.equal(timers.length, 0);
    assert.equal(prevented, 3);
    assert.equal(stopped, 3);
    assert.equal(viewerMessage.hidden, true);
    assert.equal(viewerMessage.textContent, '');
  } finally {
    await stopServer(child);
    await rm(noVncDir, { recursive: true, force: true });
  }
});

test('viewer reports keyboard paste clipboard failures without touching VM', async () => {
  const noVncDir = await fakeNoVncTree();
  const { child, url } = await startServer({ OLC_NOVNC_DIR: noVncDir });

  try {
    const script = await fetch(new URL('/screen.js', url)).then(response => response.text());
    const windowHandlers = new Map();
    const timers = [];
    const operations = [];
    const screen = {
      focus() {},
      addEventListener() {},
    };
    const viewerMessage = { textContent: '', hidden: true };

    class FakeRFB {
      constructor() {
        this._rfbConnectionState = 'connected';
        this._viewOnly = false;
      }

      addEventListener() {}

      clipboardPasteFrom(text) {
        operations.push({ type: 'clipboard', text });
      }

      focus() {
        operations.push({ type: 'focus' });
      }

      sendKey(keysym, code, down) {
        operations.push({ type: 'key', keysym, code, down });
      }
    }

    const context = {
      FakeRFB,
      document: {
        getElementById(id) {
          return { screen, 'viewer-message': viewerMessage }[id];
        },
      },
      navigator: {},
      window: {
        OLC_VM_SCREEN: { host: '127.0.0.1', port: 5720, audio: { enabled: false } },
        location: { protocol: 'http:' },
        addEventListener(type, handler, options) {
          windowHandlers.set(type, { handler, options });
        },
        clearTimeout() {},
        setTimeout(callback, delayMs) {
          timers.push({ callback, delayMs });
          return timers.length;
        },
      },
    };

    vm.runInNewContext(
      script.replace("import RFB from '/novnc/core/rfb.js';", 'const RFB = FakeRFB;'),
      context,
    );

    const keydown = windowHandlers.get('keydown').handler;
    function pasteKeyEvent() {
      return {
        code: 'KeyV',
        ctrlKey: true,
        metaKey: false,
        altKey: false,
        repeat: false,
        preventDefault() {},
        stopPropagation() {},
      };
    }

    async function assertPasteFailure(clipboard, expectedMessage) {
      context.navigator.clipboard = clipboard;
      viewerMessage.hidden = true;
      viewerMessage.textContent = '';
      keydown(pasteKeyEvent());
      await drainMicrotasks();
      assert.equal(viewerMessage.hidden, false);
      assert.equal(viewerMessage.textContent, expectedMessage);
      assert.deepEqual(operations, []);
    }

    await assertPasteFailure(undefined, 'Host clipboard unavailable');
    await assertPasteFailure({
      async readText() {
        throw new Error('denied');
      },
    }, 'Host clipboard read denied');
    await assertPasteFailure({
      async readText() {
        return '';
      },
    }, 'Host clipboard has no text');
    assert.equal(timers.length, 3);
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
    const viewerMessage = { textContent: '', hidden: true };
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
            'viewer-message': viewerMessage,
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
    assert.equal(viewerMessage.hidden, true);
    assert.equal(viewerMessage.textContent, '');
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
    const viewerMessage = { textContent: '', hidden: true };
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
            'viewer-message': viewerMessage,
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
    assert.equal(viewerMessage.hidden, true);
    assert.equal(viewerMessage.textContent, '');
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
    const viewerMessage = { textContent: '', hidden: true };
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
          return { screen, 'viewer-message': viewerMessage }[id];
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
