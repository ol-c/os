# Milestone 3 Status Page Style

The Milestone 3 status page should feel like a live Markdown document, not a conventional settings app. It should read naturally from top to bottom, with controls embedded inline where a sentence needs interaction.

The page is still served as HTML at `https://localhost/`, but the visual and interaction model should follow this document-first style.

## Product Shape

The page is a single system status document. It should use normal document structure:

- Title
- Short status summary
- Sections with headings
- Sentences and short lists
- Inline values
- Inline interactors

Avoid dashboard grids, large cards, marketing panels, decorative backgrounds, and app-like navigation for the first proof. The page should be calm, dense enough to be useful, and easy to scan.

The first page title should be:

```text
System
```

The first summary should be one sentence derived from live state, for example:

```text
Network is connected, audio is at 40%, and Bluetooth is unavailable.
```

## Inline Interactors

An inline interactor is a small control embedded directly in prose or a list item.

Examples:

```text
Volume is [ 40 -------- ] and is [not muted v].
```

```text
Appearance is [light v].
```

```text
Network is connected through [Wired v].
```

```text
Bluetooth is [off v].
```

These examples describe the intended shape, not final copy. The implementation should use accessible native controls where practical:

- `input type="range"` for volume and brightness.
- `select` for mode choices such as appearance, network choice, and Bluetooth power state.
- `button` only for explicit commands such as refresh or retry.

Controls should sit on the same line as the label when there is room. On narrow screens, they may wrap to the next line, but they should remain visually tied to the sentence they affect.

## Document Layout

Use one constrained reading column.

Recommended structure:

```text
# System

Network is connected, audio is at 40%, and Bluetooth is unavailable.

## Network

Connected through [Wired v].
Address: 10.0.2.15

## Power

Battery is unavailable in this VM.

## Sound

Volume is [40 -------] and mute is [off v].

## Display

Brightness is unavailable in this VM.

## Appearance

Mode is [light v].

## Bluetooth

Bluetooth is unavailable in this VM.
```

The implementation should not render literal Markdown syntax like `#`. It should render semantic HTML that looks and behaves like a Markdown document.

## Visual Rules

The first implementation should use a simple document palette:

- Page background: white or near-white in light mode.
- Text: dark neutral.
- Links and active controls: one restrained accent color.
- Dark mode: dark neutral background with high-contrast text.

Do not use a dominant purple, blue-purple, beige, tan, dark-blue, slate, brown, orange, or espresso theme.

Use plain section separation:

- Headings
- Paragraph spacing
- Thin dividers only when they improve scanning

Do not use cards for each utility. Do not put the whole page in a card. The status document is the page.

Recommended type:

- System UI sans-serif font stack.
- Body text around 16px.
- Headings modestly larger than body text.
- No viewport-scaled font sizes.
- Letter spacing `0`.

Recommended control sizing:

- Inline controls should have stable width where possible.
- Sliders should not resize as their value changes.
- Select controls should have enough width for the longest option.
- Border radius should be `8px` or less.

## Interaction Rules

The page should update in place after every successful control change.

Flow:

1. User changes an inline control.
2. Browser sends the relevant `POST /api/system/...` request.
3. Backend returns the full updated status document.
4. Page re-renders all live values from that returned document.

During a pending update:

- Keep the control visible and stable.
- Disable only the control being updated when needed.
- Show a short inline pending state only if the action is not immediate.

On failure:

- Keep the previous known state visible.
- Show a short inline error next to the affected sentence.
- Do not replace the whole page with an error view unless the initial status load fails.

Unavailable hardware should be represented as normal document text, not as an error.

Examples:

```text
Battery is unavailable in this VM.
```

```text
Brightness is unavailable in this VM.
```

## Accessibility Contract

Inline interactors must still be accessible controls:

- Every control has a programmatic label.
- Current values are visible as text, not only as slider position or color.
- Keyboard interaction works for every control.
- Focus states are visible.
- Disabled and unavailable states are distinguishable without relying only on color.
- The page uses semantic headings in order.

When a control update changes nearby text, use a polite live region only for important status updates. Avoid noisy announcements for every slider movement; commit slider changes on `change` rather than every `input` event for the first proof.

## Test Implications

Browser tests should assert document behavior, not pixel-perfect layout.

Minimum checks:

- The page exposes a top-level `System` heading.
- Initial status text is derived from `GET /api/system/status`.
- Each utility section appears in heading order.
- Volume and appearance controls are reachable by label.
- Changing an inline control sends the expected API request.
- The returned status updates the visible sentence.
- Unavailable hardware is rendered as text, not as a failed control.

Visual smoke checks should cover:

- Desktop width.
- Narrow mobile width.
- Light appearance.
- Dark appearance.

The implementation should include enough stable labels and roles that tests can use accessible queries instead of CSS selectors.
