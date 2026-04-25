import { EditorView } from '@codemirror/view';
import { syntaxHighlighting, HighlightStyle } from '@codemirror/language';
import { tags } from '@lezer/highlight';
import {
  defaultTerminalPreferences,
  findTerminalFont,
} from './terminal-options.mjs';

export const terminalThemes = Object.freeze({
  solarized: Object.freeze({
    light: Object.freeze({
      background: '#fdf6e3',
      foreground: '#657b83',
      panel: '#fbfbf8',
      panelForeground: '#181a1f',
      muted: '#586e75',
      line: '#eee8d5',
      accent: '#268bd2',
      selection: '#eee8d5',
      keyword: '#859900',
      string: '#2aa198',
      number: '#d33682',
      comment: '#93a1a1',
      variable: '#b58900',
      type: '#6c71c4',
      definition: '#cb4b16',
      operator: '#657b83',
      punctuation: '#657b83',
      heading: '#268bd2',
      property: '#268bd2',
      atom: '#d33682',
      error: '#dc322f',
    }),
    dark: Object.freeze({
      background: '#002b36',
      foreground: '#839496',
      panel: '#073642',
      panelForeground: '#93a1a1',
      muted: '#586e75',
      line: '#073642',
      accent: '#268bd2',
      selection: '#073642',
      keyword: '#859900',
      string: '#2aa198',
      number: '#d33682',
      comment: '#586e75',
      variable: '#b58900',
      type: '#6c71c4',
      definition: '#cb4b16',
      operator: '#93a1a1',
      punctuation: '#93a1a1',
      heading: '#268bd2',
      property: '#268bd2',
      atom: '#d33682',
      error: '#dc322f',
    }),
  }),
  tango: Object.freeze({
    light: Object.freeze({
      background: '#ffffff',
      foreground: '#2e3436',
      panel: '#eeeeec',
      panelForeground: '#2e3436',
      muted: '#555753',
      line: '#d3d7cf',
      accent: '#3465a4',
      selection: '#d3d7cf',
      keyword: '#4e9a06',
      string: '#06989a',
      number: '#75507b',
      comment: '#888a85',
      variable: '#c4a000',
      type: '#5c3566',
      definition: '#ce5c00',
      operator: '#2e3436',
      punctuation: '#555753',
      heading: '#3465a4',
      property: '#204a87',
      atom: '#75507b',
      error: '#cc0000',
    }),
    dark: Object.freeze({
      background: '#2e3436',
      foreground: '#d3d7cf',
      panel: '#343a3b',
      panelForeground: '#eeeeec',
      muted: '#babdb6',
      line: '#555753',
      accent: '#729fcf',
      selection: '#555753',
      keyword: '#8ae234',
      string: '#34e2e2',
      number: '#ad7fa8',
      comment: '#888a85',
      variable: '#fce94f',
      type: '#c17d11',
      definition: '#fcaf3e',
      operator: '#eeeeec',
      punctuation: '#d3d7cf',
      heading: '#729fcf',
      property: '#8cc4ff',
      atom: '#ad7fa8',
      error: '#ef2929',
    }),
  }),
});

export function resolveEditorTheme(editorPreferences, appearanceMode) {
  return terminalThemes[editorPreferences.colorScheme]?.[appearanceMode]
    ?? terminalThemes[defaultTerminalPreferences.colorScheme][appearanceMode];
}

export function resolveEditorFontFamily(editorPreferences) {
  return findTerminalFont(editorPreferences.font)?.cssFamily
    ?? findTerminalFont(defaultTerminalPreferences.font).cssFamily;
}

export function createThemeExtension(theme, appearanceMode, fontFamily) {
  return [
    EditorView.theme({
      '&': {
        height: '100%',
        maxHeight: '100%',
        color: theme.foreground,
        backgroundColor: theme.background,
        fontFamily,
        overflow: 'hidden',
      },
      '.cm-scroller': {
        fontFamily,
        lineHeight: '1.45',
        overflow: 'auto',
      },
      '.cm-gutter, .cm-content': {
        minHeight: '100%',
      },
      '.cm-content': {
        caretColor: theme.accent,
      },
      '.cm-cursor': {
        borderLeftColor: theme.accent,
      },
      '.cm-selectionBackground, ::selection': {
        backgroundColor: `${theme.selection} !important`,
      },
      '.cm-gutters': {
        backgroundColor: theme.panel,
        color: theme.muted,
        borderRightColor: theme.line,
      },
      '.cm-activeLine, .cm-activeLineGutter': {
        backgroundColor: theme.panel,
      },
      '.cm-focused': {
        outline: 'none',
      },
    }, { dark: appearanceMode === 'dark' }),
    syntaxHighlighting(HighlightStyle.define([
      { tag: [ tags.keyword, tags.modifier, tags.controlKeyword ], color: theme.keyword },
      { tag: [ tags.string, tags.special(tags.string) ], color: theme.string },
      { tag: [ tags.number, tags.integer, tags.float ], color: theme.number },
      { tag: tags.comment, color: theme.comment, fontStyle: 'italic' },
      { tag: [ tags.variableName, tags.attributeName ], color: theme.variable },
      { tag: [ tags.typeName, tags.className ], color: theme.type },
      { tag: [ tags.definition(tags.variableName), tags.definition(tags.propertyName) ], color: theme.definition },
      { tag: [ tags.operator, tags.derefOperator ], color: theme.operator },
      { tag: [ tags.punctuation, tags.separator, tags.bracket ], color: theme.punctuation },
      { tag: [ tags.heading, tags.url ], color: theme.heading, fontWeight: '600' },
      { tag: [ tags.propertyName, tags.labelName ], color: theme.property },
      { tag: [ tags.atom, tags.null, tags.bool ], color: theme.atom },
      { tag: tags.invalid, color: theme.error },
    ])),
  ];
}
