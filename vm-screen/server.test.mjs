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
