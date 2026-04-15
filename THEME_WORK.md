# Firefox Theme Work Notes

## Live Findings

- Environment-variable and desktop-setting style approaches are not enough for the current OL-C guest.
- A temporary `xsettingsd` process with `Gtk/ApplicationPreferDarkTheme 1` did not affect the running Firefox session.
- With `xsettingsd` active, normal page content still reported:
  - `darkMedia: false`
  - `lightMedia: true`
  - `rootColorScheme: "light dark"`
- Firefox DBus remote only exposed `OpenURL`; it is not useful for reading or changing theme state.

## Proven Working Firefox Switch

The reliable live switch is Firefox's built-in theme activation through chrome code.

Browser Console command that switched the whole browser to dark, including tabs/chrome and web content color-scheme:

```js
const { AddonManager } = ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs");
(await AddonManager.getAddonByID("firefox-compact-dark@mozilla.org")).enable();
```

Observed state after enabling the built-in dark theme:

```js
{
  activeTheme: "firefox-compact-dark@mozilla.org",
  toolbarTheme: 0,
  contentTheme: 0,
  contentOverride: 0,
  chromeDarkMedia: true,
}
```

The page console then reported:

```js
{
  dark: true,
  light: false,
  colorScheme: "light dark",
}
```

Likely light-mode command:

```js
const { AddonManager } = ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs");
(await AddonManager.getAddonByID("firefox-compact-light@mozilla.org")).enable();
```

Useful Browser Console state probe:

```js
({
  activeTheme: Services.prefs.getStringPref("extensions.activeThemeID", ""),
  toolbarTheme: Services.prefs.getIntPref("browser.theme.toolbar-theme", -1),
  contentTheme: Services.prefs.getIntPref("browser.theme.content-theme", -1),
  contentOverride: Services.prefs.getIntPref("layout.css.prefers-color-scheme.content-override", -1),
  chromeDarkMedia: matchMedia("(prefers-color-scheme: dark)").matches,
})
```

Useful page console probe:

```js
({
  dark: matchMedia("(prefers-color-scheme: dark)").matches,
  light: matchMedia("(prefers-color-scheme: light)").matches,
  colorScheme: getComputedStyle(document.documentElement).colorScheme,
})
```

## Current Interpretation

- `browser.theme.toolbar-theme = 2`, `browser.theme.content-theme = 2`, and `layout.css.prefers-color-scheme.content-override = 2` mean Firefox is following its system/default behavior.
- In the current bare X11 + matchbox session, that system/default behavior resolves to light.
- Forcing only `layout.css.prefers-color-scheme.content-override = 0` makes web content report dark, but it does not make tabs/browser chrome dark.
- Activating the built-in dark theme updates both chrome and content.

## Implementation Direction

Use Firefox-native theme activation, not env vars or an OS theme daemon, for the first reliable browser-wide appearance control.

Recommended first implementation:

- Add a small Firefox chrome bridge restricted to `https://localhost`.
- Prefer Firefox's existing `WebChannel` mechanism because it is designed for trusted web-origin to browser-chrome messaging.
- The System page sends a message such as `{ command: "setAppearance", mode: "dark" | "light" }`.
- Chrome code handles the message by enabling:
  - dark: `firefox-compact-dark@mozilla.org`
  - light: `firefox-compact-light@mozilla.org`
- Keep `/api/system/appearance` for status and non-browser UI state, but make the visible browser-wide change through the Firefox bridge.

Acceptance target:

- Changing the System page Appearance picker changes Firefox tabs/chrome live.
- `matchMedia("(prefers-color-scheme: dark)")` changes live in web content.
- Firefox does not restart.
