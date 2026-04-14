import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { createSessionLifecycle } from './session-lifecycle.mjs';

const OUTPUT = '0';
const SET_WINDOW_TITLE = '1';
const SET_PREFERENCES = '2';
const INPUT = '0';
const RESIZE_TERMINAL = '1';

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const fallbackTitle = 'OL-C Terminal';
const appConfig = window.OLC_TERMINAL_CONFIG;

const terminalNode = document.getElementById('terminal');
const statusNode = document.getElementById('terminal-status');
const terminal = new Terminal({
  allowProposedApi: true,
  cursorBlink: true,
  fontFamily: 'Consolas, "Liberation Mono", Menlo, Courier, monospace',
  fontSize: 13,
  theme: {
    background: '#050814',
    foreground: '#dbe4f0',
    cursor: '#93c5fd',
  },
});
const fitAddon = new FitAddon();
const sessionLifecycle = createSessionLifecycle({
  windowRef: window,
  terminalNode,
  onCloseBlocked: () => {
    showStatus(
      'The terminal session ended. This browser blocked closing the tab. <a href="/terminal">Open a fresh terminal</a>',
      { sticky: true, html: true }
    );
  },
});

let socket = null;
let reconnectTimer = null;
let terminated = false;
let closeSignalSent = false;
let pageTitle = fallbackTitle;
let reconnectDelayMs = 1000;

terminal.loadAddon(fitAddon);
terminal.open(terminalNode);
fitAddon.fit();
terminal.focus();
document.title = fallbackTitle;

function showStatus(message, { sticky = false, html = false } = {}) {
  statusNode.dataset.visible = 'true';
  if (html) {
    statusNode.innerHTML = message;
  } else {
    statusNode.textContent = message;
  }

  if (!sticky) {
    window.setTimeout(() => {
      if (statusNode.textContent === message || statusNode.innerHTML === message) {
        hideStatus();
      }
    }, 1200);
  }
}

function hideStatus() {
  statusNode.dataset.visible = 'false';
}

function setDocumentTitle(nextTitle) {
  if (nextTitle && nextTitle.trim() !== '') {
    pageTitle = nextTitle.trim();
    document.title = pageTitle;
    return;
  }

  document.title = pageTitle || fallbackTitle;
}

function encodeClientMessage(command, payload) {
  const payloadBytes = typeof payload === 'string'
    ? encoder.encode(payload)
    : payload;
  const frame = new Uint8Array(payloadBytes.length + 1);
  frame[0] = command.charCodeAt(0);
  frame.set(payloadBytes, 1);
  return frame;
}

async function fetchBackendToken() {
  const response = await fetch(appConfig.tokenUrl, {
    cache: 'no-store',
    credentials: 'same-origin',
  });

  if (!response.ok) {
    throw new Error(`token endpoint returned ${response.status}`);
  }

  const body = await response.json();
  if (!Object.prototype.hasOwnProperty.call(body, 'token')) {
    throw new Error('token endpoint did not return a token');
  }

  return body.token;
}

function sendResize() {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    return;
  }

  const payload = JSON.stringify({
    columns: terminal.cols,
    rows: terminal.rows,
  });
  socket.send(encodeClientMessage(RESIZE_TERMINAL, payload));
}

function applyPreferences(preferences) {
  if (preferences.titleFixed) {
    setDocumentTitle(preferences.titleFixed);
  }

  for (const [key, value] of Object.entries(preferences)) {
    if (key in terminal.options) {
      terminal.options[key] = value;
    }
  }

  fitAddon.fit();
  sendResize();
}

function scheduleReconnect() {
  if (terminated || reconnectTimer !== null) {
    return;
  }

  showStatus('Reconnecting...', { sticky: true });
  reconnectTimer = window.setTimeout(() => {
    reconnectTimer = null;
    void connect();
  }, reconnectDelayMs);
  reconnectDelayMs = Math.min(reconnectDelayMs * 2, 5000);
}

function endSession(message) {
  terminated = true;
  if (socket) {
    socket.onclose = null;
    socket.close();
    socket = null;
  }
  if (reconnectTimer !== null) {
    window.clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  showStatus(
    `${message} <a href="/terminal">Open a fresh terminal</a>`,
    { sticky: true, html: true }
  );
}

function sendCloseSignal() {
  if (closeSignalSent || !appConfig.closeUrl) {
    return;
  }
  closeSignalSent = true;

  if (navigator.sendBeacon) {
    const sent = navigator.sendBeacon(appConfig.closeUrl, new Blob([], { type: 'text/plain' }));
    if (sent) {
      return;
    }
  }

  void fetch(appConfig.closeUrl, {
    method: 'POST',
    cache: 'no-store',
    credentials: 'same-origin',
    keepalive: true,
  }).catch(() => {});
}

function closeRootSession() {
  terminated = true;
  if (socket) {
    socket.onclose = null;
    socket.close();
    socket = null;
  }
  if (reconnectTimer !== null) {
    window.clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  sessionLifecycle.closeRootSessionTab();
}

async function connect() {
  try {
    const authToken = await fetchBackendToken();
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}${appConfig.wsPath}`;
    const ws = new WebSocket(wsUrl, ['tty']);
    socket = ws;
    ws.binaryType = 'arraybuffer';

    ws.onopen = () => {
      reconnectDelayMs = 1000;
      hideStatus();
      ws.send(encoder.encode(JSON.stringify({
        AuthToken: authToken,
        columns: terminal.cols,
        rows: terminal.rows,
      })));
      terminal.focus();
    };

    ws.onmessage = event => {
      const bytes = new Uint8Array(event.data);
      const command = String.fromCharCode(bytes[0]);
      const payload = bytes.slice(1);

      switch (command) {
        case OUTPUT:
          terminal.write(payload);
          break;
        case SET_WINDOW_TITLE:
          setDocumentTitle(decoder.decode(payload));
          break;
        case SET_PREFERENCES:
          applyPreferences(JSON.parse(decoder.decode(payload)));
          break;
        default:
          console.warn('unknown ttyd command', command);
      }
    };

    ws.onclose = event => {
      socket = null;
      if (terminated) {
        return;
      }

      if (event.code === 1000 || event.code === 1001) {
        closeRootSession();
        return;
      }

      scheduleReconnect();
    };

    ws.onerror = () => {
      if (socket === ws) {
        socket.close();
      }
    };
  } catch (error) {
    endSession(`Unable to reconnect: ${error.message}.`);
  }
}

terminal.onData(data => {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    return;
  }

  socket.send(encodeClientMessage(INPUT, data));
});

terminal.onBinary(data => {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    return;
  }

  socket.send(encodeClientMessage(INPUT, Uint8Array.from(data, value => value.charCodeAt(0))));
});

terminal.onTitleChange(title => {
  if (title) {
    setDocumentTitle(title);
  }
});

window.addEventListener('resize', () => {
  fitAddon.fit();
  sendResize();
});

window.addEventListener('pagehide', () => {
  sendCloseSignal();
});

void connect();
