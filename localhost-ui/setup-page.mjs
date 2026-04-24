export function setupHtml() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>First Setup</title>
    <style>
      :root {
        color-scheme: light dark;
        --bg: #f7f4ec;
        --panel: rgba(255, 253, 247, 0.92);
        --panel-border: #c9c1ae;
        --text: #1d211b;
        --muted: #5f675f;
        --accent: #105d47;
        --error: #9f2e1b;
        font-family: "Iowan Old Style", "Palatino Linotype", "Book Antiqua", Georgia, serif;
        background:
          radial-gradient(circle at top left, rgba(16, 93, 71, 0.1), transparent 30%),
          linear-gradient(180deg, #f7f4ec 0%, #efe8d8 100%);
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
        padding: 1.25rem;
      }

      main {
        width: min(32rem, 100%);
        padding: 1.4rem;
        border: 1px solid var(--panel-border);
        border-radius: 18px;
        background: var(--panel);
        box-shadow: 0 22px 60px rgba(49, 45, 35, 0.12);
      }

      h1, p {
        margin: 0;
      }

      h1 {
        font-size: 2rem;
        line-height: 1.05;
      }

      p {
        margin-top: 0.75rem;
        line-height: 1.5;
      }

      form {
        display: grid;
        gap: 0.9rem;
        margin-top: 1.5rem;
      }

      label {
        display: grid;
        gap: 0.35rem;
        font-size: 0.95rem;
      }

      input, button {
        min-height: 2.5rem;
        border: 1px solid var(--panel-border);
        border-radius: 10px;
        font: inherit;
      }

      input {
        padding: 0 0.75rem;
        background: rgba(255, 255, 255, 0.9);
        color: var(--text);
      }

      button {
        padding: 0 0.95rem;
        background: var(--accent);
        color: #fffdf8;
        font-weight: 600;
        cursor: pointer;
      }

      button:disabled {
        cursor: progress;
        opacity: 0.7;
      }

      .muted {
        color: var(--muted);
        font-size: 0.92rem;
      }

      .error {
        color: var(--error);
        min-height: 1.25rem;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>Set Up This Machine</h1>
      <p>Create the first administrator account. This account becomes the machine's initial human owner and will be used for future sign-in.</p>
      <p class="muted">The home directory is created through systemd-homed with LUKS-backed storage so later encrypted-home work builds on the same account model.</p>

      <form id="setup-form">
        <label>
          Username
          <input id="username" name="username" type="text" autocomplete="username" autocapitalize="none" spellcheck="false" required />
        </label>
        <label>
          Password
          <input id="password" name="password" type="password" autocomplete="new-password" required />
        </label>
        <label>
          Confirm password
          <input id="confirm-password" name="confirm-password" type="password" autocomplete="new-password" required />
        </label>
        <button id="submit" type="submit">Create first admin</button>
        <p id="message" class="error" role="status" aria-live="polite"></p>
      </form>
    </main>
    <script>
      const form = document.getElementById('setup-form');
      const submit = document.getElementById('submit');
      const message = document.getElementById('message');

      form.addEventListener('submit', async event => {
        event.preventDefault();
        submit.disabled = true;
        message.textContent = '';

        const body = {
          username: document.getElementById('username').value.trim(),
          password: document.getElementById('password').value,
          confirmPassword: document.getElementById('confirm-password').value,
        };

        try {
          const response = await fetch('/api/setup/first-user', {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify(body),
          });
          const payload = await response.json();
          if (!response.ok) {
            throw new Error(payload.error || 'Setup failed.');
          }

          message.textContent = payload.message || 'Setup complete. Returning to the login prompt.';
        } catch (error) {
          message.textContent = error.message;
          submit.disabled = false;
        }
      });
    </script>
  </body>
</html>`;
}
