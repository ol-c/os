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
      </section>

      <section aria-labelledby="power-heading">
        <h2 id="power-heading">Power</h2>
        <p id="power-status">Power status is loading.</p>
      </section>

      <section aria-labelledby="sound-heading">
        <h2 id="sound-heading">Sound</h2>
        <p>
          Volume is
          <span class="interactor">
            <label class="proof" for="volume-control">Volume</label>
            <input id="volume-control" type="range" min="0" max="100" step="1" disabled />
            <span id="volume-value">unknown</span>
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
      </section>

      <section aria-labelledby="display-heading">
        <h2 id="display-heading">Display</h2>
        <p id="brightness-status">
          Brightness is
          <span class="interactor">
            <label class="proof" for="brightness-control">Brightness</label>
            <input id="brightness-control" type="range" min="0" max="100" step="1" disabled />
            <span id="brightness-value">unknown</span>
          </span>.
          <span id="brightness-error" class="error" role="status"></span>
        </p>
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
      </section>

      <p><a href="/terminal" onclick="window.open('/terminal', '_blank'); return false;">Open terminal</a></p>
      <p id="proof" class="proof">${marker}</p>
    </main>

    <script>
      const controls = {
        summary: document.getElementById('summary'),
        networkStatus: document.getElementById('network-status'),
        network: document.getElementById('network-control'),
        networkError: document.getElementById('network-error'),
        networkAddress: document.getElementById('network-address'),
        powerStatus: document.getElementById('power-status'),
        volume: document.getElementById('volume-control'),
        volumeValue: document.getElementById('volume-value'),
        mute: document.getElementById('mute-control'),
        volumeError: document.getElementById('volume-error'),
        brightnessStatus: document.getElementById('brightness-status'),
        brightness: document.getElementById('brightness-control'),
        brightnessValue: document.getElementById('brightness-value'),
        brightnessError: document.getElementById('brightness-error'),
        appearance: document.getElementById('appearance-control'),
        appearanceError: document.getElementById('appearance-error'),
        bluetoothStatus: document.getElementById('bluetooth-status'),
        bluetooth: document.getElementById('bluetooth-control'),
        bluetoothError: document.getElementById('bluetooth-error'),
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

        if (status.power.available) {
          controls.powerStatus.textContent = 'Battery is at ' + percentText(status.power.percent) + ' and is ' + boolText(status.power.charging, 'charging', 'not charging') + '.';
        } else {
          controls.powerStatus.textContent = 'Battery is unavailable in this VM.';
        }

        setControlEnabled(controls.volume, status.volume.available);
        setControlEnabled(controls.mute, status.volume.available);
        controls.volume.value = Number.isInteger(status.volume.percent) ? String(status.volume.percent) : '0';
        controls.volumeValue.textContent = percentText(status.volume.percent);
        controls.mute.value = status.volume.muted ? 'true' : 'false';

        setControlEnabled(controls.brightness, status.brightness.available);
        controls.brightness.value = Number.isInteger(status.brightness.percent) ? String(status.brightness.percent) : '0';
        controls.brightnessValue.textContent = status.brightness.available ? percentText(status.brightness.percent) : 'unavailable';

        setControlEnabled(controls.appearance, status.appearance.available);
        controls.appearance.value = status.appearance.mode;

        setControlEnabled(controls.bluetooth, status.bluetooth.available);
        controls.bluetooth.value = status.bluetooth.enabled ? 'true' : 'false';
        if (!status.bluetooth.available) {
          controls.bluetoothStatus.firstChild.textContent = 'Bluetooth is unavailable in this VM.';
          controls.bluetooth.style.display = 'none';
        } else {
          controls.bluetoothStatus.firstChild.textContent = 'Bluetooth is ';
          controls.bluetooth.style.display = '';
        }
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
        } catch (error) {
          errorElement.textContent = ' ' + error.message;
          control.disabled = wasDisabled;
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
        postCommand('/api/system/appearance', { mode: controls.appearance.value }, controls.appearanceError, controls.appearance);
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
    </script>
  </body>
</html>`;
}
