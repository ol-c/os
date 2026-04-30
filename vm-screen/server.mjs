import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, normalize, resolve, sep } from 'node:path';

const listenHost = process.env.OLC_VM_SCREEN_HOST || '127.0.0.1';
const listenPort = Number.parseInt(process.env.OLC_VM_SCREEN_PORT || '0', 10);
const vncHost = process.env.OLC_VM_SCREEN_VNC_HOST || '127.0.0.1';
const vncWebsocketPort = process.env.OLC_VM_SCREEN_VNC_WS_PORT || '';
const noVncDir = process.env.OLC_NOVNC_DIR || '';
const audioEnabled = process.env.OLC_VM_SCREEN_AUDIO_ENABLED === '1';
const audioBin = process.env.OLC_VM_SCREEN_AUDIO_BIN || '';
const audioArgsJson = process.env.OLC_VM_SCREEN_AUDIO_ARGS_JSON || '[]';
const audioSampleRate = Number.parseInt(process.env.OLC_VM_SCREEN_AUDIO_SAMPLE_RATE || '48000', 10);
const audioChannels = Number.parseInt(process.env.OLC_VM_SCREEN_AUDIO_CHANNELS || '2', 10);
const audioFormat = process.env.OLC_VM_SCREEN_AUDIO_FORMAT || 's16le';
const audioPathname = '/audio-stream';

let audioArgs = [];
let audioProcess = null;
let audioRestartTimer = null;
let audioShuttingDown = false;
const audioClients = new Set();

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function contentType(pathname) {
  switch (extname(pathname)) {
    case '.css':
      return 'text/css; charset=utf-8';
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
    case '.mjs':
      return 'text/javascript; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.png':
      return 'image/png';
    case '.wasm':
      return 'application/wasm';
    default:
      return 'application/octet-stream';
  }
}

function isLocalhostTarget(host) {
  return host === '127.0.0.1' || host === 'localhost' || host === '::1';
}

function safeNovncPath(pathname) {
  const relative = pathname.replace(/^\/novnc\/?/, '');
  const normalized = normalize(relative);
  if (normalized.startsWith('..') || normalized.includes(`${sep}..${sep}`)) {
    return null;
  }

  const root = resolve(noVncDir);
  const resolved = resolve(root, normalized);
  if (resolved !== root && !resolved.startsWith(`${root}${sep}`)) {
    return null;
  }

  return resolved;
}

function send(res, status, body, type = 'text/plain; charset=utf-8') {
  res.writeHead(status, {
    'content-type': type,
    'cache-control': 'no-store',
  });
  res.end(body);
}

function audioConfig() {
  if (!audioEnabled) {
    return { enabled: false };
  }

  return {
    enabled: true,
    path: audioPathname,
    sampleRate: audioSampleRate,
    channels: audioChannels,
    format: audioFormat,
  };
}

function indexHtml() {
  const config = JSON.stringify({
    host: vncHost,
    port: Number.parseInt(vncWebsocketPort, 10),
    audio: audioConfig(),
  });

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ol-c VM</title>
  <style>
    html, body {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #101418;
      color: #f4f7f8;
      font-family: "Noto Sans", "Noto Sans CJK SC", "Noto Sans CJK TC", "Noto Sans CJK HK", "Noto Sans CJK JP", "Noto Sans CJK KR", "Noto Color Emoji", sans-serif;
    }

    #screen {
      width: 100vw;
      height: 100vh;
    }

    #viewer-message[hidden] {
      display: none;
    }

    #viewer-message {
      position: fixed;
      right: 10px;
      bottom: 10px;
      z-index: 2;
      max-width: min(28rem, calc(100vw - 20px));
      padding: 6px 8px;
      border-radius: 6px;
      background: rgba(16, 20, 24, 0.78);
      color: #f4f7f8;
      font-size: 13px;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <div id="screen"></div>
  <div id="viewer-message" role="status" aria-live="polite" hidden></div>
  <script>window.OLC_VM_SCREEN = ${config};</script>
  <script type="module" src="/screen.js"></script>
</body>
</html>`;
}

function screenJs() {
  return `import RFB from '/novnc/core/rfb.js';

const screen = document.getElementById('screen');
const viewerMessage = document.getElementById('viewer-message');
const config = window.OLC_VM_SCREEN;
const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
const url = protocol + '//' + config.host + ':' + config.port + '/';
let latestVmClipboardText = '';
let viewerMessageTimer = 0;
let persistentViewerMessage = false;
const wheelState = { x: 0, y: 0 };
const wheelStep = 50;
const wheelLineHeight = 19;
let audioContext = null;
let audioProcessor = null;
let audioStreaming = false;
let audioBridgeReady = false;
let audioPrimed = false;
let queuedAudioFrames = 0;
let pendingAudioBytes = new Uint8Array(0);
const audioQueue = [];
const audioProcessorFrameCount = 1024;

function setViewerMessage(message, { persist = false } = {}) {
  if (!viewerMessage) {
    return;
  }
  if (persistentViewerMessage && !persist) {
    return;
  }

  persistentViewerMessage = persist;
  viewerMessage.textContent = message;
  viewerMessage.hidden = false;
  window.clearTimeout(viewerMessageTimer);
  if (!persist) {
    viewerMessageTimer = window.setTimeout(() => {
      viewerMessage.hidden = true;
      viewerMessage.textContent = '';
    }, 3500);
  }
}

function clearViewerMessage() {
  if (!viewerMessage) {
    return;
  }

  window.clearTimeout(viewerMessageTimer);
  persistentViewerMessage = false;
  viewerMessage.hidden = true;
  viewerMessage.textContent = '';
}

function setStatus(message, { visible = false } = {}) {
  document.title = message === 'Connected' ? 'ol-c VM' : 'ol-c VM - ' + message;
  if (visible) {
    setViewerMessage(message, { persist: true });
  } else if (message === 'Connected') {
    clearViewerMessage();
  }
}

function setAudioProblem(message) {
  setViewerMessage(message);
}

function setAudioHint(message) {
  if (message === 'Browser audio unsupported' || message === 'Audio unavailable') {
    setAudioProblem(message);
  }
}

function pointerPosition(event, element) {
  const bounds = element.getBoundingClientRect();
  return {
    x: Math.max(0, Math.min(bounds.width - 1, event.clientX - bounds.left)),
    y: Math.max(0, Math.min(bounds.height - 1, event.clientY - bounds.top)),
  };
}

function buttonMaskFromMouseButtons(buttons) {
  let mask = 0;
  if (buttons & 1) mask |= 1;
  if (buttons & 2) mask |= 4;
  if (buttons & 4) mask |= 2;
  if (buttons & 8) mask |= 128;
  if (buttons & 16) mask |= 256;
  return mask;
}

function normalizeWheelDelta(event) {
  let scale = 1;
  if (event.deltaMode !== WheelEvent.DOM_DELTA_PIXEL) {
    scale = wheelLineHeight;
  }

  return {
    x: event.deltaX * scale,
    y: event.deltaY * scale,
  };
}

function emitWheelButton(pos, baseMask, wheelMask) {
  rfb._handleMouseButton(pos.x, pos.y, baseMask | wheelMask);
  rfb._handleMouseButton(pos.x, pos.y, baseMask);
}

function drainWheelAxis(pos, baseMask, axis, negativeMask, positiveMask) {
  const steps = Math.trunc(wheelState[axis] / wheelStep);
  if (steps === 0) {
    return;
  }

  const wheelMask = steps < 0 ? negativeMask : positiveMask;
  for (let step = 0; step < Math.abs(steps); step += 1) {
    emitWheelButton(pos, baseMask, wheelMask);
  }
  wheelState[axis] -= steps * wheelStep;
}

async function copyLatestVmClipboardToHost({ notify = false } = {}) {
  if (latestVmClipboardText.length === 0) {
    if (notify) {
      setViewerMessage('No VM clipboard text');
    }
    return false;
  }

  if (!navigator.clipboard?.writeText) {
    if (notify) {
      setViewerMessage('Host clipboard unavailable');
    }
    return false;
  }

  try {
    await navigator.clipboard.writeText(latestVmClipboardText);
    return true;
  } catch {
    if (notify) {
      setViewerMessage('Press Ctrl+Shift+C to copy from VM');
    }
    return false;
  }
}

function dropQueuedAudioFrames(frameCount) {
  let remaining = frameCount;

  while (remaining > 0 && audioQueue.length > 0) {
    const chunk = audioQueue[0];
    const available = chunk.frames - chunk.offset;
    const consumed = Math.min(available, remaining);
    chunk.offset += consumed;
    queuedAudioFrames -= consumed;
    remaining -= consumed;
    if (chunk.offset >= chunk.frames) {
      audioQueue.shift();
    }
  }
}

function trimQueuedAudio() {
  if (!config.audio?.enabled) {
    return;
  }

  const startupFrames = Math.max(audioProcessorFrameCount, Math.floor(config.audio.sampleRate * 0.05));
  const targetFrames = Math.max(startupFrames * 2, Math.floor(config.audio.sampleRate * 0.1));
  const maxFrames = Math.max(targetFrames + startupFrames, Math.floor(config.audio.sampleRate * 0.2));
  if (queuedAudioFrames <= maxFrames) {
    return;
  }

  dropQueuedAudioFrames(queuedAudioFrames - targetFrames);
}

function queueAudioChunk(value) {
  if (!config.audio?.enabled || config.audio.format !== 's16le') {
    return;
  }

  let chunk = value;
  if (pendingAudioBytes.length > 0) {
    const merged = new Uint8Array(pendingAudioBytes.length + value.length);
    merged.set(pendingAudioBytes);
    merged.set(value, pendingAudioBytes.length);
    chunk = merged;
    pendingAudioBytes = new Uint8Array(0);
  }

  const bytesPerFrame = config.audio.channels * 2;
  const alignedLength = chunk.length - (chunk.length % bytesPerFrame);
  if (alignedLength === 0) {
    pendingAudioBytes = chunk;
    return;
  }

  if (alignedLength !== chunk.length) {
    pendingAudioBytes = chunk.slice(alignedLength);
    chunk = chunk.slice(0, alignedLength);
  }

  const pcm = new Int16Array(chunk.buffer, chunk.byteOffset, chunk.byteLength / 2);
  const frameCount = pcm.length / config.audio.channels;
  const channelData = Array.from({ length: config.audio.channels }, () => new Float32Array(frameCount));

  let sampleIndex = 0;
  for (let frame = 0; frame < frameCount; frame += 1) {
    for (let channel = 0; channel < config.audio.channels; channel += 1) {
      channelData[channel][frame] = pcm[sampleIndex] / 32768;
      sampleIndex += 1;
    }
  }

  audioQueue.push({
    channels: channelData,
    frames: frameCount,
    offset: 0,
  });
  queuedAudioFrames += frameCount;
  trimQueuedAudio();
}

function drainAudioInto(outputChannels) {
  const frameCount = outputChannels[0]?.length || 0;
  for (const channel of outputChannels) {
    channel.fill(0);
  }

  if (frameCount === 0 || audioQueue.length === 0) {
    audioPrimed = false;
    return;
  }

  const startupFrames = Math.max(audioProcessorFrameCount, Math.floor(config.audio.sampleRate * 0.05));
  if (!audioPrimed) {
    if (queuedAudioFrames < startupFrames) {
      return;
    }
    audioPrimed = true;
  }

  let written = 0;
  while (written < frameCount && audioQueue.length > 0) {
    const chunk = audioQueue[0];
    const available = chunk.frames - chunk.offset;
    const consumed = Math.min(available, frameCount - written);

    for (let channel = 0; channel < config.audio.channels; channel += 1) {
      outputChannels[channel].set(
        chunk.channels[channel].subarray(chunk.offset, chunk.offset + consumed),
        written,
      );
    }

    chunk.offset += consumed;
    queuedAudioFrames -= consumed;
    written += consumed;

    if (chunk.offset >= chunk.frames) {
      audioQueue.shift();
    }
  }

  if (written < frameCount) {
    audioPrimed = false;
  }
}

function ensureAudioBridge() {
  if (!config.audio?.enabled) {
    return false;
  }

  if (!audioStreaming) {
    void streamAudioToBrowser();
  }

  if (audioBridgeReady) {
    return true;
  }

  const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextCtor) {
    setAudioHint('Browser audio unsupported');
    return false;
  }

  try {
    audioContext = new AudioContextCtor({
      latencyHint: 'interactive',
      sampleRate: config.audio.sampleRate,
    });
  } catch {
    return false;
  }

  if (typeof audioContext.createScriptProcessor !== 'function') {
    setAudioHint('Browser audio unsupported');
    return false;
  }

  audioProcessor = audioContext.createScriptProcessor(audioProcessorFrameCount, 0, config.audio.channels);
  audioProcessor.onaudioprocess = event => {
    const outputs = [];
    for (let channel = 0; channel < config.audio.channels; channel += 1) {
      outputs.push(event.outputBuffer.getChannelData(channel));
    }
    drainAudioInto(outputs);
  };
  audioProcessor.connect(audioContext.destination);
  audioBridgeReady = true;

  return true;
}

async function resumeAudioPlayback() {
  if (!ensureAudioBridge() || !audioContext || audioContext.state === 'running') {
    return;
  }

  try {
    await audioContext.resume();
  } catch {
    return;
  }
}

async function streamAudioToBrowser() {
  if (!config.audio?.enabled || audioStreaming) {
    return;
  }
  audioStreaming = true;

  while (true) {
    try {
      const response = await fetch(config.audio.path, { cache: 'no-store' });
      if (!response.ok || !response.body) {
        setAudioHint('Audio unavailable');
        return;
      }

      const reader = response.body.getReader();
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }
        if (value) {
          queueAudioChunk(value);
        }
      }

    } catch {
      setAudioHint('Audio unavailable');
    }

    await new Promise(resolve => {
      window.setTimeout(resolve, 250);
    });
  }
}

const rfb = new RFB(screen, url, { credentials: {} });
rfb.scaleViewport = true;
rfb.resizeSession = false;
rfb.focusOnClick = true;

screen.addEventListener('wheel', event => {
  if (rfb._rfbConnectionState !== 'connected' || rfb._viewOnly) {
    return;
  }

  event.stopPropagation();
  event.preventDefault();

  const canvas = rfb._canvas || event.target;
  const pos = pointerPosition(event, canvas);
  const baseMask = buttonMaskFromMouseButtons(event.buttons);
  const delta = normalizeWheelDelta(event);
  wheelState.x += delta.x;
  wheelState.y += delta.y;

  drainWheelAxis(pos, baseMask, 'x', 1 << 5, 1 << 6);
  drainWheelAxis(pos, baseMask, 'y', 1 << 3, 1 << 4);
}, { capture: true, passive: false });

rfb.addEventListener('connect', () => setStatus('Connected'));
rfb.addEventListener('disconnect', event => {
  setStatus(event.detail.clean ? 'Disconnected' : 'Disconnected unexpectedly', { visible: true });
});
rfb.addEventListener('credentialsrequired', () => setStatus('Credentials required', { visible: true }));
rfb.addEventListener('securityfailure', () => setStatus('Security failure', { visible: true }));
rfb.addEventListener('clipboard', event => {
  latestVmClipboardText = event.detail?.text || '';
  if (latestVmClipboardText.length === 0) {
    return;
  }

  void copyLatestVmClipboardToHost();
});

window.addEventListener('paste', event => {
  const text = event.clipboardData?.getData('text/plain') || '';
  if (text.length === 0) {
    return;
  }

  event.preventDefault();
  rfb.clipboardPasteFrom(text);
  rfb.focus();
});

window.addEventListener('keydown', event => {
  void resumeAudioPlayback();
  if (event.ctrlKey && event.shiftKey && event.code === 'KeyC') {
    event.preventDefault();
    void copyLatestVmClipboardToHost({ notify: true });
  }
});

window.addEventListener('pointerdown', () => {
  void resumeAudioPlayback();
}, { capture: true });

ensureAudioBridge();
screen.focus();
`;
}

function startAudioCapture() {
  if (!audioEnabled || audioProcess) {
    return;
  }

  audioProcess = spawn(audioBin, audioArgs, {
    stdio: [ 'ignore', 'pipe', 'pipe' ],
  });
  audioProcess.stdout.on('data', chunk => {
    for (const res of audioClients) {
      if (res.destroyed || res.writableEnded) {
        audioClients.delete(res);
        continue;
      }
      res.write(chunk);
    }
  });
  audioProcess.on('exit', () => {
    audioProcess = null;
    if (!audioShuttingDown && audioClients.size > 0) {
      audioRestartTimer = setTimeout(() => {
        audioRestartTimer = null;
        startAudioCapture();
      }, 250);
      audioRestartTimer.unref();
    }
  });
}

function stopAudioCapture() {
  if (audioRestartTimer) {
    clearTimeout(audioRestartTimer);
    audioRestartTimer = null;
  }

  if (audioProcess) {
    audioProcess.kill('SIGTERM');
    audioProcess = null;
  }
}

if (!Number.isInteger(listenPort) || listenPort < 0 || listenPort > 65535) {
  fail('OLC_VM_SCREEN_PORT must be a TCP port number');
}

if (!Number.isInteger(Number.parseInt(vncWebsocketPort, 10))) {
  fail('OLC_VM_SCREEN_VNC_WS_PORT must be set to a TCP port number');
}

if (!isLocalhostTarget(vncHost) && process.env.OLC_VM_SCREEN_ALLOW_REMOTE_VNC !== '1') {
  fail('refusing to serve a non-local VNC target without OLC_VM_SCREEN_ALLOW_REMOTE_VNC=1');
}

if (!noVncDir || !existsSync(noVncDir) || !statSync(noVncDir).isDirectory()) {
  fail('OLC_NOVNC_DIR must point to a noVNC asset directory');
}

if (audioEnabled) {
  if (!audioBin) {
    fail('OLC_VM_SCREEN_AUDIO_BIN must be set when OLC_VM_SCREEN_AUDIO_ENABLED=1');
  }

  try {
    audioArgs = JSON.parse(audioArgsJson);
  } catch {
    fail('OLC_VM_SCREEN_AUDIO_ARGS_JSON must be valid JSON');
  }

  if (!Array.isArray(audioArgs) || audioArgs.some(arg => typeof arg !== 'string')) {
    fail('OLC_VM_SCREEN_AUDIO_ARGS_JSON must be a JSON array of strings');
  }

  if (!Number.isInteger(audioSampleRate) || audioSampleRate <= 0) {
    fail('OLC_VM_SCREEN_AUDIO_SAMPLE_RATE must be a positive integer');
  }

  if (!Number.isInteger(audioChannels) || audioChannels <= 0) {
    fail('OLC_VM_SCREEN_AUDIO_CHANNELS must be a positive integer');
  }

  if (audioFormat !== 's16le') {
    fail(`unsupported embedded VM audio format: ${audioFormat}`);
  }
}

const server = createServer((req, res) => {
  const url = new URL(req.url || '/', `http://${listenHost}`);

  if (url.pathname === '/') {
    send(res, 200, indexHtml(), 'text/html; charset=utf-8');
    return;
  }

  if (url.pathname === '/screen.js') {
    send(res, 200, screenJs(), 'text/javascript; charset=utf-8');
    return;
  }

  if (url.pathname === audioPathname) {
    if (!audioEnabled) {
      send(res, 404, 'not found');
      return;
    }

    res.writeHead(200, {
      'content-type': 'application/octet-stream',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    });
    res.socket?.setNoDelay(true);
    res.flushHeaders();

    audioClients.add(res);
    startAudioCapture();

    const cleanupClient = () => {
      audioClients.delete(res);
      if (audioClients.size === 0) {
        stopAudioCapture();
      }
    };

    req.on('close', cleanupClient);
    res.on('close', cleanupClient);
    return;
  }

  if (url.pathname.startsWith('/novnc/')) {
    const path = safeNovncPath(url.pathname);
    if (!path || !existsSync(path) || !statSync(path).isFile()) {
      send(res, 404, 'not found');
      return;
    }

    res.writeHead(200, {
      'content-type': contentType(path),
      'cache-control': 'no-store',
    });
    createReadStream(path).pipe(res);
    return;
  }

  send(res, 404, 'not found');
});

server.listen(listenPort, listenHost, () => {
  const address = server.address();
  console.log(`OLC_VM_SCREEN_URL http://${listenHost}:${address.port}/`);
});

function shutdown() {
  audioShuttingDown = true;
  stopAudioCapture();
  for (const res of audioClients) {
    if (!res.destroyed && !res.writableEnded) {
      res.end();
    }
  }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1000).unref();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
