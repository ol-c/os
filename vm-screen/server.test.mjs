import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

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
