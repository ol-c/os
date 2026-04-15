# Milestone 3 System Controls Proof

Milestone 3 proves that the browser can act as the basic control panel for the guest OS. The proof surface should stay small, deterministic, and end-to-end: Firefox loads `https://localhost/`, the page shows current system state, user actions call the local service, and the guest-side backend reflects the requested changes through observable state.

This document defines the first proof surface and test strategy. It intentionally does not lock in the long-term settings information architecture, persistence model, hardware policy model, or future browser internals.

## Proof Surface

Use `https://localhost/` as the Milestone 3 system controls dashboard.

Keep `https://localhost/terminal` as the existing terminal proof surface. The terminal remains useful for development and manual validation, but the controls dashboard is the primary Milestone 3 user-facing proof.

Style the dashboard as a live Markdown-like status document with inline interactors. The detailed style contract lives in `docs/milestone-3-status-page-style.md`.

The initial dashboard should show one compact status/control area for each core utility:

- Network
- Power
- Volume
- Brightness
- Appearance
- Bluetooth

The page should favor live state and obvious controls over final visual polish. Each section should expose enough detail to prove that state is being read from the backend, not hard-coded into the page.

## Initial Capability Contract

The first implementation should use one local HTTPS service contract owned by `localhost-ui/server.mjs`.

Recommended endpoints:

- `GET /api/system/events`
- `POST /api/system/network`
- `POST /api/system/volume`
- `POST /api/system/brightness`
- `POST /api/system/appearance`
- `POST /api/system/bluetooth`

`GET /api/system/events` opens a server-sent event stream. The server immediately sends a `status` event containing the complete state needed to render the dashboard, then sends another complete `status` event whenever observed or controlled state changes. The first implementation can observe non-command state changes by polling the selected system adapter and publishing a new event when the full status snapshot changes.

Mutating endpoints accept a small JSON request, apply or record the requested change, publish the updated state to connected event-stream clients, and return the updated complete status document. Returning full state snapshots keeps the browser simple and makes tests deterministic.

The first status document should use explicit unavailable states instead of omitting hardware-dependent fields:

```json
{
  "network": {
    "available": true,
    "connected": true,
    "kind": "ethernet",
    "ssid": null,
    "address": "10.0.2.15"
  },
  "power": {
    "available": false,
    "charging": null,
    "percent": null,
    "timeRemainingSeconds": null
  },
  "volume": {
    "available": true,
    "muted": false,
    "percent": 40
  },
  "brightness": {
    "available": false,
    "percent": null
  },
  "appearance": {
    "available": true,
    "mode": "light"
  },
  "bluetooth": {
    "available": false,
    "enabled": null,
    "discovering": null
  }
}
```

Fields can be extended as the implementation learns more from real guest hardware and VM devices, but the first contract should avoid ambiguous missing values.

## Backend Shape

Keep the service split into two layers:

- HTTP/browser contract layer
- system adapter layer

The HTTP layer validates requests, normalizes responses, and serves the dashboard. The system adapter owns reads and writes against guest state.

The first adapter set should include:

- A deterministic fake adapter for automated tests and development without device hardware.
- A real guest adapter for available VM-backed system state.

The fake adapter is not a mock hidden inside tests. It should be a real selectable backend mode so local development, contract tests, and future VM smoke tests can all drive the same behavior.

Suggested selector:

- default: real adapter
- `OLC_SYSTEM_CONTROLS_BACKEND=fake`: deterministic fake adapter

The fake adapter should maintain in-memory state for mutable controls. It should start from a known default state, update state through the same mutation paths as the real adapter, and return the same status shape.

Fake hardware capabilities are composed with `OLC_HARDWARE_TEST` instead of fixed scenario names. Supported tokens are:

- `network`
- `wifi`
- `battery`
- `audio`
- `brightness`
- `appearance`
- `bluetooth`

Convenience tokens are:

- `none`
- `desktop`
- `laptop`
- `all`

Commas and colons are both accepted separators, so `OLC_HARDWARE_TEST=wifi,bluetooth` and `OLC_HARDWARE_TEST=wifi:bluetooth` are equivalent. This is a development harness for real-hardware capability contracts, not a claim that QEMU emulates all of those devices. Later real-hardware probe reports should map into this same capability model, and deeper fidelity tests can use tools such as `umockdev` or `python-dbusmock` when we need to replay sysfs, udev, or D-Bus service behavior.

## Control Semantics

Use conservative first semantics for each utility.

Network:
- First proof may show general network state even if Wi-Fi-specific control is unavailable in QEMU.
- Mutating endpoint can initially support a harmless refresh or fake connect/disconnect in fake mode.
- Real Wi-Fi network selection can wait until the guest has a meaningful wireless device path.

Power:
- Show battery availability, charging state, and percent when available.
- In normal QEMU development, absence of a battery is a valid state and should be visible as unavailable.
- Mutations are not required for the first power proof.

Volume:
- Show mute state and volume percent.
- Support setting mute and percent when the guest audio stack exposes a stable command path.
- Fake mode must support both.

Brightness:
- Show brightness availability and percent when a backlight path exists.
- Fake mode must support setting percent.
- Real mode may report unavailable in QEMU until a reliable guest display brightness path exists.

Appearance:
- Show light or dark mode.
- Support toggling the recorded appearance mode.
- First implementation may apply the mode to the dashboard itself before system-wide theme propagation exists.

Bluetooth:
- Show adapter availability and enabled state.
- Fake mode must support enabling and disabling.
- Real mode may report unavailable in QEMU when no Bluetooth adapter exists.

## Test Strategy

The milestone needs deterministic automated coverage for the browser-to-system control contract. Hardware-specific real adapter behavior can have narrower tests, but the main contract should not depend on host devices, VM devices, battery presence, Bluetooth presence, or Wi-Fi availability.

Minimum automated coverage:

- HTTP/SSE contract tests for `GET /api/system/events`.
- HTTP contract tests for every mutating endpoint using the fake adapter.
- Validation tests for malformed JSON, unknown actions, out-of-range percentages, and unsupported controls.
- Browser-level tests that load the dashboard against the fake adapter, verify initial event-stream state, trigger at least one control update, and verify the rendered state updates.
- Packaging/build tests that ensure the dashboard assets and backend adapter files are included in the guest service.

The fake-adapter contract tests should be the main gate for Milestone 3 behavior. VM smoke tests should prove integration, not carry all edge cases.

Recommended test layers:

- Node unit tests for adapter state transitions and request validation.
- Node HTTP/SSE tests for the local service API.
- Browser tests, preferably Playwright, against the local service in fake mode.
- Existing shell tests for Nix build and launch contracts updated only where packaging changes require it.

## Acceptance Criteria For This Proof

The Milestone 3 system controls proof is complete when:

- `https://localhost/` opens a dashboard in the guest browser.
- The dashboard renders network, power, volume, brightness, appearance, and Bluetooth status from `GET /api/system/events`.
- The dashboard visibly distinguishes available, unavailable, enabled, disabled, and unknown states.
- At least volume, brightness, appearance, and Bluetooth have working browser-driven mutation flows in fake mode.
- Any real guest controls implemented for the VM are observable through the same API and dashboard paths as fake mode.
- Automated tests cover the API contract and at least one browser interaction path without relying on real hardware.
- The README documents how to run the relevant tests and how to launch the VM proof.

## Follow-On Decisions

Defer these until a later milestone or until the first proof exposes a real need:

- Long-term settings navigation and information architecture.
- Persistent user preferences.
- Policy boundaries for privileged system changes.
- Hardware-specific Wi-Fi onboarding.
- Full system-wide theme propagation.
- Browser-internal implementation of privileged controls.
- Remote or host-accessible control surfaces.
