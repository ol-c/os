export const terminalFontChoices = Object.freeze([
  Object.freeze({
    id: 'dejavu-sans-mono',
    label: 'DejaVu Sans Mono',
    cssFamily: '"DejaVu Sans Mono", "DejaVu Sans Mono Book", monospace',
  }),
  Object.freeze({
    id: 'inconsolata',
    label: 'Inconsolata',
    cssFamily: 'Inconsolata, "DejaVu Sans Mono", monospace',
  }),
]);

export const terminalColorSchemeChoices = Object.freeze([
  Object.freeze({
    id: 'solarized',
    label: 'Solarized',
    variants: Object.freeze([ 'light', 'dark' ]),
  }),
  Object.freeze({
    id: 'tango',
    label: 'Tango',
    variants: Object.freeze([ 'light', 'dark' ]),
  }),
]);

export const defaultTerminalPreferences = Object.freeze({
  font: 'dejavu-sans-mono',
  colorScheme: 'solarized',
});

export function findTerminalFont(id) {
  return terminalFontChoices.find(choice => choice.id === id) ?? null;
}

export function findTerminalColorScheme(id) {
  const scheme = terminalColorSchemeChoices.find(choice => choice.id === id) ?? null;
  if (!scheme) {
    return null;
  }

  return scheme.variants.includes('light') && scheme.variants.includes('dark')
    ? scheme
    : null;
}
