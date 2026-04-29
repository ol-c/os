export function loginGreeterHtml() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Sign In</title>
    <style>
      :root {
        color-scheme: light dark;
        --bg-1: #efe6d5;
        --bg-2: #d7e7e1;
        --panel: rgba(255, 251, 244, 0.84);
        --line: rgba(78, 82, 70, 0.22);
        --text: #17201a;
        --muted: #5e655e;
        --accent: #0f6a57;
        --accent-2: #0b4e40;
        --error: #9a2f24;
        --focus: rgba(15, 106, 87, 0.18);
        font-family: "Iowan Old Style", "Palatino Linotype", "Book Antiqua", Georgia, serif;
        background:
          radial-gradient(circle at 20% 15%, rgba(15, 106, 87, 0.18), transparent 28%),
          radial-gradient(circle at 80% 10%, rgba(207, 124, 54, 0.14), transparent 24%),
          linear-gradient(135deg, var(--bg-1), var(--bg-2));
        color: var(--text);
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 1.5rem;
      }

      main {
        width: min(32rem, 100%);
        padding: 1.5rem;
        border-radius: 20px;
        border: 1px solid var(--line);
        background: var(--panel);
        backdrop-filter: blur(18px);
        box-shadow: 0 25px 70px rgba(31, 40, 33, 0.18);
      }

      h1, p {
        margin: 0;
      }

      h1 {
        font-size: 2rem;
        line-height: 1.04;
      }

      .lede {
        margin-top: 0.8rem;
        color: var(--muted);
        line-height: 1.5;
      }

      form {
        display: grid;
        gap: 0.95rem;
        margin-top: 1.5rem;
      }

      .account-picker {
        display: grid;
        gap: 0.7rem;
      }

      .picker-label {
        color: var(--muted);
        font-size: 0.95rem;
      }

      .account-list {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
        gap: 0.65rem;
      }

      label {
        display: grid;
        gap: 0.35rem;
        font-size: 0.95rem;
      }

      input, button {
        min-height: 2.8rem;
        border-radius: 12px;
        border: 1px solid var(--line);
        font: inherit;
      }

      input {
        padding: 0 0.85rem;
        color: var(--text);
        background: rgba(255, 255, 255, 0.72);
      }

      input:focus {
        outline: 2px solid var(--focus);
        border-color: var(--accent);
      }

      button {
        padding: 0 1rem;
        border: 0;
        color: #fffdf9;
        background: linear-gradient(180deg, var(--accent), var(--accent-2));
        font-weight: 600;
        cursor: pointer;
      }

      .account-button {
        min-height: 3.4rem;
        padding: 0.65rem 0.85rem;
        color: var(--text);
        background: rgba(255, 255, 255, 0.48);
        border: 1px solid var(--line);
        text-align: left;
      }

      .account-button[aria-pressed="true"] {
        border-color: var(--accent);
        box-shadow: 0 0 0 3px var(--focus);
      }

      button:disabled {
        cursor: progress;
        opacity: 0.72;
      }

      .secondary {
        background: transparent;
        color: var(--muted);
        border: 1px solid var(--line);
      }

      .row {
        display: flex;
        gap: 0.75rem;
      }

      .row > * {
        flex: 1 1 auto;
      }

      .hidden {
        display: none !important;
      }

      .status {
        min-height: 1.3rem;
        color: var(--muted);
        line-height: 1.4;
      }

      .status.error {
        color: var(--error);
      }

      .notice-list {
        display: grid;
        gap: 0.45rem;
        margin-top: 0.5rem;
        color: var(--muted);
        font-size: 0.93rem;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>Welcome Back</h1>
      <p class="lede">Sign in to open your browser session. Authentication is handled by the system login stack before your desktop starts.</p>

      <form id="login-form">
        <section id="account-picker" class="account-picker hidden" aria-label="Available accounts">
          <p class="picker-label">Choose an account</p>
          <div id="account-list" class="account-list"></div>
          <button id="manual-account" class="secondary" type="button">Use Another Account</button>
        </section>

        <label id="username-label">
          Username
          <input id="username" name="username" type="text" autocomplete="username" autocapitalize="none" spellcheck="false" />
        </label>

        <label id="password-label">
          Password
          <input id="password" name="password" type="password" autocomplete="current-password" required />
        </label>

        <label id="prompt-label" class="hidden">
          <span id="prompt-message">Additional verification</span>
          <input id="prompt-response" name="prompt-response" type="password" autocomplete="off" />
        </label>

        <div class="row">
          <button id="submit" type="submit">Sign In</button>
          <button id="cancel" class="secondary hidden" type="button">Start Over</button>
        </div>

        <p id="status" class="status" role="status" aria-live="polite"></p>
        <div id="notices" class="notice-list"></div>
      </form>
    </main>
    <script>
      const form = document.getElementById('login-form');
      const accountPicker = document.getElementById('account-picker');
      const accountList = document.getElementById('account-list');
      const manualAccount = document.getElementById('manual-account');
      const usernameLabel = document.getElementById('username-label');
      const username = document.getElementById('username');
      const password = document.getElementById('password');
      const promptLabel = document.getElementById('prompt-label');
      const promptMessage = document.getElementById('prompt-message');
      const promptResponse = document.getElementById('prompt-response');
      const submit = document.getElementById('submit');
      const cancel = document.getElementById('cancel');
      const status = document.getElementById('status');
      const notices = document.getElementById('notices');
      let hasAccountChoices = false;
      let promptActive = false;

      function setStatus(message, kind = '') {
        status.textContent = message || '';
        status.className = kind ? \`status \${kind}\` : 'status';
      }

      function renderNotices(items = []) {
        notices.innerHTML = '';
        for (const item of items) {
          const line = document.createElement('div');
          line.textContent = item.text || '';
          notices.appendChild(line);
        }
      }

      function setBusy(value) {
        submit.disabled = value;
        cancel.disabled = value;
        manualAccount.disabled = value;
        for (const button of accountList.querySelectorAll('button')) {
          button.disabled = value;
        }
      }

      function setUsernameVisible(value) {
        usernameLabel.classList.toggle('hidden', !value);
      }

      function clearSelectedAccount() {
        for (const button of accountList.querySelectorAll('button')) {
          button.setAttribute('aria-pressed', 'false');
        }
      }

      function selectAccount(accountName, button) {
        username.value = accountName;
        clearSelectedAccount();
        button.setAttribute('aria-pressed', 'true');
        setUsernameVisible(false);
        setStatus('');
        password.focus();
      }

      function showManualAccount() {
        username.value = '';
        clearSelectedAccount();
        setUsernameVisible(true);
        setStatus('');
        username.focus();
      }

      function renderAccounts(users = []) {
        accountList.innerHTML = '';
        if (!users.length) {
          hasAccountChoices = false;
          accountPicker.classList.add('hidden');
          setUsernameVisible(true);
          return;
        }

        hasAccountChoices = true;
        accountPicker.classList.remove('hidden');
        setUsernameVisible(false);
        for (const accountName of users) {
          const button = document.createElement('button');
          button.className = 'account-button';
          button.type = 'button';
          button.textContent = accountName;
          button.setAttribute('aria-pressed', 'false');
          button.addEventListener('click', () => selectAccount(accountName, button));
          accountList.appendChild(button);
        }

        const firstAccount = accountList.querySelector('button');
        if (firstAccount) {
          selectAccount(users[0], firstAccount);
        }
      }

      async function loadAccounts() {
        try {
          const response = await fetch('/api/login/users', {
            cache: 'no-store',
          });
          const payload = await response.json();
          if (response.ok && Array.isArray(payload.users)) {
            renderAccounts(payload.users.filter(user => typeof user === 'string' && user));
          }
        } catch {
          renderAccounts([]);
        }
      }

      function showPrompt(prompt) {
        promptActive = true;
        promptLabel.classList.remove('hidden');
        cancel.classList.remove('hidden');
        promptMessage.textContent = prompt.message || 'Additional verification';
        promptResponse.type = prompt.type === 'visible' ? 'text' : 'password';
        promptResponse.value = '';
        password.closest('label').classList.add('hidden');
        username.readOnly = true;
        submit.textContent = 'Continue';
        promptResponse.focus();
      }

      function resetPromptUi() {
        promptActive = false;
        promptLabel.classList.add('hidden');
        cancel.classList.add('hidden');
        promptResponse.value = '';
        username.readOnly = false;
        password.closest('label').classList.remove('hidden');
        submit.textContent = 'Sign In';
      }

      async function request(path, body) {
        const response = await fetch(path, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(body || {}),
        });
        const payload = await response.json();
        if (!response.ok) {
          throw new Error(payload.error || 'Request failed.');
        }
        return payload;
      }

      async function handleResult(result) {
        renderNotices(result.notices || []);
        if (result.status === 'prompt' && result.prompt) {
          setStatus('');
          showPrompt(result.prompt);
          return;
        }

        if (result.status === 'starting') {
          setStatus('Starting your session…');
          resetPromptUi();
          username.blur();
          password.blur();
          promptResponse.blur();
          return;
        }

        setStatus('');
      }

      form.addEventListener('submit', async event => {
        event.preventDefault();
        setBusy(true);
        setStatus('');

        try {
          if (!promptActive && !username.value.trim()) {
            setStatus(hasAccountChoices ? 'Choose an account or use another account.' : 'Username is required.', 'error');
            if (!hasAccountChoices) {
              username.focus();
            }
            return;
          }

          const result = promptActive
            ? await request('/api/respond', { response: promptResponse.value })
            : await request('/api/login', {
              username: username.value.trim(),
              password: password.value,
            });
          await handleResult(result);
        } catch (error) {
          setStatus(error.message, 'error');
          if (!promptActive) {
            password.value = '';
            password.focus();
          } else {
            promptResponse.value = '';
            promptResponse.focus();
          }
        } finally {
          setBusy(false);
        }
      });

      cancel.addEventListener('click', async () => {
        setBusy(true);
        try {
          await request('/api/cancel', {});
        } catch {
          // Ignore local reset failures.
        } finally {
          resetPromptUi();
          renderNotices([]);
          setStatus('');
          password.value = '';
          setBusy(false);
          if (hasAccountChoices) {
            password.focus();
          } else {
            username.focus();
          }
        }
      });

      manualAccount.addEventListener('click', showManualAccount);

      loadAccounts().then(() => {
        if (!hasAccountChoices) {
          username.focus();
        }
      });
    </script>
  </body>
</html>`;
}
