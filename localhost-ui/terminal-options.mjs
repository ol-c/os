export const terminalFontChoices = Object.freeze([
  Object.freeze({
    id: 'noto-sans-mono',
    label: 'Noto Sans Mono',
    cssFamily: '"Noto Sans Mono", "Noto Sans CJK SC", "Noto Sans CJK TC", "Noto Sans CJK HK", "Noto Sans CJK JP", "Noto Sans CJK KR", "Noto Color Emoji", monospace',
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
  font: 'noto-sans-mono',
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
