# WebDriver BiDi Investigation for `https://localhost/*`

## Question

Can ol-c use Firefox WebDriver BiDi as a fast page-level automation path for the signed-in `https://localhost/*` browser UI?

## Short Answer

Yes.

Firefox 149.0.2 in the current ol-c VM already exposes the needed command-line surface:

- `--remote-debugging-port [<port>]`
- `--remote-allow-hosts <hosts>`
- `--remote-allow-origins <origins>`
- `--remote-allow-system-access`

The official Firefox docs describe WebDriver BiDi as a WebSocket-based remote automation protocol, launched in Firefox with `--remote-debugging-port`, with the client connecting at `ws://127.0.0.1:PORT/session`.

## What Was Proved

A clean second Firefox instance was launched inside the current ol-c VM with:

```sh
firefox \
  --new-instance \
  --no-remote \
  --profile /tmp/... \
  --remote-debugging-port 0 \
  --new-window https://localhost
```

The browser reported:

```text
WebDriver BiDi listening on ws://127.0.0.1:42741
```

Using a plain Node WebSocket client against `ws://127.0.0.1:42741/session`, the prototype successfully:

1. created a BiDi session with `session.new`
2. enumerated tabs with `browsingContext.getTree`
3. found the `https://localhost/` context
4. ran `script.evaluate` in page context

The returned values confirmed direct page access:

- `document.title = "System"`
- `location.href = "https://localhost/"`
- `document.querySelector("h1")?.textContent = "System"`

## Why This Matters

This is a much better control path for localhost pages than QMP input injection:

- no screenshot polling
- no guessing focus
- direct DOM reads
- direct JS execution
- deterministic waits on page state
- access to console, network, and page lifecycle events through BiDi modules

QMP remains useful for:

- pre-login flows
- first-boot setup
- broken browser states
- full-VM control outside Firefox page content

BiDi is the better path once Firefox is up and we want to automate `https://localhost/*`.

## Current Integrated State

The normal ol-c graphical Firefox session now launches with `--remote-debugging-port 0` by default.

At runtime it records BiDi metadata in:

```text
/run/user/$UID/ol-c-firefox/bidi.env
```

and the guest development profile now includes:

```sh
olc-firefox-bidi-url
olc-firefox-bidi-url --base
```

so the active signed-in user's BiDi endpoint can be resolved directly without scraping logs.

## Important Constraints

- Firefox allows only one active BiDi session per browser instance. The prototype hit `session not created: Maximum number of active sessions` when trying to create a second session without fully ending the first.
- If we expose BiDi on the main browser, we should keep it local-only and explicit. `127.0.0.1` is the correct binding, and any host/origin allowlist should stay narrow.
- `--remote-allow-system-access` exists but should not be enabled by default for this use case. Our current need is page automation for `https://localhost/*`, not Firefox chrome-process control.

## Recommended Direction

Add an explicit opt-in localhost-page automation path for the main Firefox session:

1. keep launching Firefox with `--remote-debugging-port 0`
2. keep exposing the assigned BiDi WebSocket URL through the `olc-firefox-bidi-url` helper and journal-backed readiness flow
3. use the `olc-firefox-bidi-url` helper as the operator-facing lookup path
4. add a thin helper that:
   - opens a BiDi session
   - finds the target `https://localhost/*` tab
   - evaluates JS
   - subscribes to useful events when needed
5. keep QMP as the fallback path for login, setup, and recovery

## Suggested First Proof

The first integrated proof should be:

1. launch the normal browser with BiDi enabled
2. connect to the live signed-in `https://localhost/` tab
3. evaluate JS that reads page state and clicks or navigates deterministically
4. show that the page changes without keyboard/mouse injection

For example:

- read `document.title`
- click a localhost UI control by selector
- navigate to `https://localhost/terminal`
- wait for a known DOM marker

## Sources

- MDN: Create a WebDriver BiDi connection  
  https://developer.mozilla.org/en-US/docs/Web/WebDriver/How_to/Create_BiDi_connection
- MDN: WebDriver BiDi reference  
  https://developer.mozilla.org/en-US/docs/Web/WebDriver/Reference/BiDi
- Firefox Source Docs: Remote Protocols  
  https://firefox-source-docs.mozilla.org/remote/index.html
- Firefox Source Docs: Preferences  
  https://firefox-source-docs.mozilla.org/remote/Prefs.html
