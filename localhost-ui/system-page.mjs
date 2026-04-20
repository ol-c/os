export const marker = 'OLC_LOCALHOST_UI_OK';

export function rootHtml() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>System</title>
    <style>
      :root {
        color-scheme: light dark;
        --bg: #fbfbf8;
        --text: #181a1f;
        --muted: #5f6672;
        --line: #d8dce2;
        --accent: #0b6b57;
        --control-bg: #ffffff;
        --control-border: #9aa3af;
        font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        letter-spacing: 0;
        background: var(--bg);
        color: var(--text);
      }

      :root[data-appearance="dark"] {
        --bg: #161712;
        --text: #f1f3eb;
        --muted: #b8bdae;
        --line: #424738;
        --accent: #68d7b5;
        --control-bg: #202219;
        --control-border: #737a66;
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        min-height: 100vh;
        background: var(--bg);
        color: var(--text);
        font-size: 16px;
        line-height: 1.55;
      }

      main {
        width: min(42rem, calc(100vw - 2rem));
        margin: 0 auto;
        padding: 3rem 0 4rem;
      }

      h1, h2, p {
        margin: 0;
      }

      h1 {
        font-size: 2rem;
        line-height: 1.15;
        font-weight: 700;
      }

      h2 {
        margin-top: 2rem;
        padding-top: 1.2rem;
        border-top: 1px solid var(--line);
        font-size: 1.1rem;
        line-height: 1.25;
      }

      p {
        margin-top: 0.65rem;
      }

      a {
        color: var(--accent);
      }

      .summary {
        margin-top: 1rem;
        color: var(--muted);
      }

      .line {
        color: var(--muted);
      }

      .interactor {
        display: inline-flex;
        align-items: center;
        gap: 0.35rem;
        vertical-align: baseline;
      }

      .range-interactor {
        vertical-align: middle;
      }

      .interactor-value {
        display: inline-flex;
        align-items: center;
        min-width: 4.5ch;
        min-height: 2rem;
        line-height: 1;
      }

      input,
      select,
      button {
        min-height: 2rem;
        border: 1px solid var(--control-border);
        border-radius: 6px;
        background: var(--control-bg);
        color: var(--text);
        font: inherit;
      }

      input[type="range"] {
        width: 10rem;
        min-height: 2rem;
        height: 2rem;
        margin: 0 0.1rem;
        padding: 0;
        border: 0;
        border-radius: 0;
        background: transparent;
        accent-color: var(--accent);
        vertical-align: middle;
      }

      select {
        min-width: 7rem;
        padding: 0 0.35rem;
      }

      button {
        padding: 0 0.55rem;
      }

      input:focus-visible,
      select:focus-visible,
      button:focus-visible,
      a:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }

      input:disabled,
      select:disabled,
      button:disabled {
        opacity: 0.62;
      }

      .error {
        color: #a43d35;
      }

      .proof {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
      }

      @media (max-width: 34rem) {
        main {
          width: min(100% - 1rem, 42rem);
          padding-top: 1.5rem;
        }

        .interactor {
          display: inline-flex;
          margin-top: 0.25rem;
        }
      }
    </style>
  </head>
  <body>
    <main>
      <h1>System</h1>
      <p id="summary" class="summary" aria-live="polite">Loading system status.</p>

      <section aria-labelledby="network-heading">
        <h2 id="network-heading">Network</h2>
        <p id="network-status">
          Network is loading
          <span class="interactor">
            <label class="proof" for="network-control">Network</label>
            <select id="network-control" disabled></select>
          </span>.
          <span id="network-error" class="error" role="status"></span>
        </p>
        <p id="network-address" class="line"></p>
        <p id="network-implementation" class="line"></p>
      </section>

      <section aria-labelledby="power-heading">
        <h2 id="power-heading">Power</h2>
        <p id="power-status">Power status is loading.</p>
        <p id="power-implementation" class="line"></p>
      </section>

      <section aria-labelledby="sound-heading">
        <h2 id="sound-heading">Sound</h2>
        <p>
          Volume is
          <span class="interactor range-interactor">
            <label class="proof" for="volume-control">Volume</label>
            <input id="volume-control" type="range" min="0" max="100" step="1" disabled />
            <span id="volume-value" class="interactor-value">unknown</span>
          </span>
          and mute is
          <span class="interactor">
            <label class="proof" for="mute-control">Mute</label>
            <select id="mute-control" disabled>
              <option value="false">off</option>
              <option value="true">on</option>
            </select>
          </span>.
          <span id="volume-error" class="error" role="status"></span>
        </p>
        <p id="volume-implementation" class="line"></p>
      </section>

      <section aria-labelledby="display-heading">
        <h2 id="display-heading">Display</h2>
        <p id="brightness-status">
          Brightness is
          <span class="interactor range-interactor">
            <label class="proof" for="brightness-control">Brightness</label>
            <input id="brightness-control" type="range" min="0" max="100" step="1" disabled />
            <span id="brightness-value" class="interactor-value">unknown</span>
          </span>.
          <span id="brightness-error" class="error" role="status"></span>
        </p>
        <p id="brightness-implementation" class="line"></p>
      </section>

      <section aria-labelledby="appearance-heading">
        <h2 id="appearance-heading">Appearance</h2>
        <p>
          Mode is
          <span class="interactor">
            <label class="proof" for="appearance-control">Appearance</label>
            <select id="appearance-control" disabled>
              <option value="light">light</option>
              <option value="dark">dark</option>
            </select>
          </span>.
          <span id="appearance-error" class="error" role="status"></span>
        </p>
        <p id="appearance-implementation" class="line"></p>
      </section>

      <section aria-labelledby="terminal-heading">
        <h2 id="terminal-heading">Terminal</h2>
        <p>
          Font is
          <span class="interactor">
            <label class="proof" for="terminal-font-control">Terminal font</label>
            <select id="terminal-font-control" disabled></select>
          </span>
          and colors are
          <span class="interactor">
            <label class="proof" for="terminal-color-scheme-control">Terminal colors</label>
            <select id="terminal-color-scheme-control" disabled></select>
          </span>.
          <span id="terminal-error" class="error" role="status"></span>
        </p>
        <p>
          <button id="open-terminal-control" type="button">Open terminal</button>
        </p>
        <p id="terminal-implementation" class="line"></p>
      </section>

      <section aria-labelledby="bluetooth-heading">
        <h2 id="bluetooth-heading">Bluetooth</h2>
        <p id="bluetooth-status">
          Bluetooth is
          <span class="interactor">
            <label class="proof" for="bluetooth-control">Bluetooth</label>
            <select id="bluetooth-control" disabled>
              <option value="false">off</option>
              <option value="true">on</option>
            </select>
          </span>.
          <span id="bluetooth-error" class="error" role="status"></span>
        </p>
        <p id="bluetooth-implementation" class="line"></p>
      </section>

      <section aria-labelledby="browser-heading">
        <h2 id="browser-heading">Browser</h2>
        <p id="browser-status">Firefox version is loading.</p>
        <p id="browser-implementation" class="line"></p>
      </section>

      <p id="proof" class="proof">${marker}</p>
    </main>

    <script>
      const controls = {
        summary: document.getElementById('summary'),
        networkStatus: document.getElementById('network-status'),
        network: document.getElementById('network-control'),
        networkError: document.getElementById('network-error'),
        networkAddress: document.getElementById('network-address'),
        networkImplementation: document.getElementById('network-implementation'),
        powerStatus: document.getElementById('power-status'),
        powerImplementation: document.getElementById('power-implementation'),
        volume: document.getElementById('volume-control'),
        volumeValue: document.getElementById('volume-value'),
        mute: document.getElementById('mute-control'),
        volumeError: document.getElementById('volume-error'),
        volumeImplementation: document.getElementById('volume-implementation'),
        brightnessStatus: document.getElementById('brightness-status'),
        brightness: document.getElementById('brightness-control'),
        brightnessValue: document.getElementById('brightness-value'),
        brightnessError: document.getElementById('brightness-error'),
        brightnessImplementation: document.getElementById('brightness-implementation'),
        appearance: document.getElementById('appearance-control'),
        appearanceError: document.getElementById('appearance-error'),
        appearanceImplementation: document.getElementById('appearance-implementation'),
        terminalFont: document.getElementById('terminal-font-control'),
        terminalColorScheme: document.getElementById('terminal-color-scheme-control'),
        openTerminal: document.getElementById('open-terminal-control'),
        terminalError: document.getElementById('terminal-error'),
        terminalImplementation: document.getElementById('terminal-implementation'),
        bluetoothStatus: document.getElementById('bluetooth-status'),
        bluetooth: document.getElementById('bluetooth-control'),
        bluetoothError: document.getElementById('bluetooth-error'),
        bluetoothImplementation: document.getElementById('bluetooth-implementation'),
        browserStatus: document.getElementById('browser-status'),
        browserImplementation: document.getElementById('browser-implementation'),
      };

      function boolText(value, trueText, falseText, unknownText = 'unknown') {
        if (value === true) return trueText;
        if (value === false) return falseText;
        return unknownText;
      }

      function percentText(value) {
        return Number.isInteger(value) ? value + '%' : 'unknown';
      }

      function setControlEnabled(control, enabled) {
        control.disabled = !enabled;
      }

      const appearanceBridge = (() => {
        const channelId = 'olc-appearance';
        const pending = new Map();
        let nextMessageId = 1;

        window.addEventListener('WebChannelMessageToContent', event => {
          const detail = event.detail || {};
          if (detail.id !== channelId || !detail.message) {
            return;
          }

          const message = detail.message;
          const deferred = pending.get(message.messageId);
          if (!deferred) {
            return;
          }

          pending.delete(message.messageId);
          clearTimeout(deferred.timer);
          if (message.data && message.data.error) {
            deferred.reject(new Error(message.data.error));
            return;
          }
          deferred.resolve(message.data || {});
        });

        function send(command, data = {}) {
          if (typeof window.CustomEvent !== 'function') {
            return Promise.reject(new Error('appearance bridge is unavailable'));
          }

          const messageId = String(nextMessageId++);
          const payload = { id: channelId, message: { command, messageId, data } };
          return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
              pending.delete(messageId);
              reject(new Error('appearance bridge is unavailable'));
            }, 700);
            pending.set(messageId, { resolve, reject, timer });
            window.dispatchEvent(new CustomEvent('WebChannelMessageToChrome', {
              detail: JSON.stringify(payload),
            }));
          });
        }

        return {
          get() {
            return send('getAppearance');
          },
          set(mode) {
            return send('setAppearance', { mode });
          },
        };
      })();

      function renderStatus(status) {
        document.documentElement.dataset.appearance = status.appearance.mode;
        controls.summary.textContent = [
          status.network.connected ? 'Network is connected' : 'Network is disconnected',
          status.volume.available ? 'audio is at ' + percentText(status.volume.percent) : 'audio is unavailable',
          status.bluetooth.available ? 'Bluetooth is ' + boolText(status.bluetooth.enabled, 'on', 'off') : 'Bluetooth is unavailable',
        ].join(', ') + '.';

        if (status.network.available) {
          controls.networkStatus.firstChild.textContent = status.network.connected
            ? 'Connected through '
            : 'Network is disconnected. ';
          const choices = status.network.choices || [];
          controls.network.replaceChildren(...choices.map(choice => {
            const option = document.createElement('option');
            option.value = choice.id;
            option.textContent = choice.label;
            return option;
          }));
          controls.network.value = status.network.selected || choices[0]?.id || '';
          controls.network.style.display = '';
          setControlEnabled(controls.network, choices.length > 0);
          controls.networkAddress.textContent = status.network.address ? 'Address: ' + status.network.address : '';
        } else {
          controls.networkStatus.firstChild.textContent = 'Network is unavailable in this VM.';
          controls.network.replaceChildren();
          controls.network.style.display = 'none';
          controls.networkAddress.textContent = '';
        }
        controls.networkImplementation.textContent = 'Implementation: ' + status.network.implementation;

        if (status.power.available) {
          controls.powerStatus.textContent = 'Battery is at ' + percentText(status.power.percent) + ' and is ' + boolText(status.power.charging, 'charging', 'not charging') + '.';
        } else {
          controls.powerStatus.textContent = 'Battery is unavailable in this VM.';
        }
        controls.powerImplementation.textContent = 'Implementation: ' + status.power.implementation;

        setControlEnabled(controls.volume, status.volume.available);
        setControlEnabled(controls.mute, status.volume.available);
        controls.volume.value = Number.isInteger(status.volume.percent) ? String(status.volume.percent) : '0';
        controls.volumeValue.textContent = percentText(status.volume.percent);
        controls.mute.value = status.volume.muted ? 'true' : 'false';
        controls.volumeImplementation.textContent = 'Implementation: ' + status.volume.implementation;

        setControlEnabled(controls.brightness, status.brightness.available);
        controls.brightness.value = Number.isInteger(status.brightness.percent) ? String(status.brightness.percent) : '0';
        controls.brightnessValue.textContent = status.brightness.available ? percentText(status.brightness.percent) : 'unavailable';
        controls.brightnessImplementation.textContent = 'Implementation: ' + status.brightness.implementation;

        setControlEnabled(controls.appearance, status.appearance.available);
        controls.appearance.value = status.appearance.mode;
        controls.appearanceImplementation.textContent = 'Implementation: ' + status.appearance.implementation;

        setControlEnabled(controls.terminalFont, status.terminal.available);
        setControlEnabled(controls.terminalColorScheme, status.terminal.available);
        controls.terminalFont.replaceChildren(...(status.terminal.fonts || []).map(choice => {
          const option = document.createElement('option');
          option.value = choice.id;
          option.textContent = choice.label;
          return option;
        }));
        controls.terminalColorScheme.replaceChildren(...(status.terminal.colorSchemes || []).map(choice => {
          const option = document.createElement('option');
          option.value = choice.id;
          option.textContent = choice.label;
          return option;
        }));
        controls.terminalFont.value = status.terminal.font;
        controls.terminalColorScheme.value = status.terminal.colorScheme;
        controls.terminalImplementation.textContent = 'Implementation: ' + status.terminal.implementation;

        setControlEnabled(controls.bluetooth, status.bluetooth.available);
        controls.bluetooth.value = status.bluetooth.enabled ? 'true' : 'false';
        if (!status.bluetooth.available) {
          controls.bluetoothStatus.firstChild.textContent = 'Bluetooth is unavailable in this VM.';
          controls.bluetooth.style.display = 'none';
        } else {
          controls.bluetoothStatus.firstChild.textContent = 'Bluetooth is ';
          controls.bluetooth.style.display = '';
        }
        controls.bluetoothImplementation.textContent = 'Implementation: ' + status.bluetooth.implementation;

        controls.browserStatus.textContent = 'Firefox is version ' + (status.browser?.firefoxVersion || 'unknown') + '.';
        controls.browserImplementation.textContent = 'Implementation: ' + (status.browser?.implementation || 'unavailable');
      }

      async function postCommand(path, body, errorElement, control) {
        errorElement.textContent = '';
        const wasDisabled = control.disabled;
        control.disabled = true;
        try {
          const response = await fetch(path, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify(body),
          });
          const payload = await response.json();
          if (!response.ok) {
            throw new Error(payload.error || 'command failed');
          }
          renderStatus(payload);
          return payload;
        } catch (error) {
          errorElement.textContent = ' ' + error.message;
          control.disabled = wasDisabled;
          throw error;
        }
      }

      async function syncBrowserAppearanceStatus() {
        try {
          const result = await appearanceBridge.get();
          if (result.mode === 'light' || result.mode === 'dark') {
            document.documentElement.dataset.appearance = result.mode;
            controls.appearance.value = result.mode;
            await postCommand('/api/system/appearance', { mode: result.mode }, controls.appearanceError, controls.appearance);
          }
        } catch {
          // Non-Firefox localhost development keeps the existing API-only behavior.
        }
      }

      controls.volume.addEventListener('change', () => {
        postCommand('/api/system/volume', { percent: Number(controls.volume.value) }, controls.volumeError, controls.volume);
      });
      controls.network.addEventListener('change', () => {
        postCommand('/api/system/network', { selected: controls.network.value }, controls.networkError, controls.network);
      });
      controls.mute.addEventListener('change', () => {
        postCommand('/api/system/volume', { muted: controls.mute.value === 'true' }, controls.volumeError, controls.mute);
      });
      controls.brightness.addEventListener('change', () => {
        postCommand('/api/system/brightness', { percent: Number(controls.brightness.value) }, controls.brightnessError, controls.brightness);
      });
      controls.appearance.addEventListener('change', () => {
        const mode = controls.appearance.value;
        controls.appearanceError.textContent = '';
        controls.appearance.disabled = true;
        appearanceBridge.set(mode)
          .catch(() => ({ mode }))
          .then(result => {
            controls.appearance.disabled = false;
            return postCommand('/api/system/appearance', { mode: result.mode || mode }, controls.appearanceError, controls.appearance);
          })
          .catch(() => {
            controls.appearance.disabled = false;
          });
      });
      controls.terminalFont.addEventListener('change', () => {
        postCommand('/api/system/terminal', { font: controls.terminalFont.value }, controls.terminalError, controls.terminalFont);
      });
      controls.terminalColorScheme.addEventListener('change', () => {
        postCommand('/api/system/terminal', { colorScheme: controls.terminalColorScheme.value }, controls.terminalError, controls.terminalColorScheme);
      });
      controls.openTerminal.addEventListener('click', () => {
        window.open('/terminal', '_blank');
      });
      controls.bluetooth.addEventListener('change', () => {
        postCommand('/api/system/bluetooth', { enabled: controls.bluetooth.value === 'true' }, controls.bluetoothError, controls.bluetooth);
      });

      const events = new EventSource('/api/system/events');
      events.addEventListener('status', event => {
        renderStatus(JSON.parse(event.data));
      });
      events.addEventListener('error', () => {
        controls.summary.textContent = 'Live system status is reconnecting.';
      });
      syncBrowserAppearanceStatus();
    </script>
  </body>
</html>`;
}
