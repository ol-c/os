import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';
import { build, context } from 'esbuild';

const outdir = join(process.cwd(), 'dist');
const require = createRequire(import.meta.url);
const watchMode = process.argv.includes('--watch');

mkdirSync(outdir, { recursive: true });

const buildOptions = {
  entryPoints: [join(process.cwd(), 'src/index.js')],
  bundle: true,
  format: 'iife',
  target: 'es2022',
  platform: 'browser',
  outfile: join(outdir, 'terminal.js'),
  minify: false,
  sourcemap: false,
};

if (watchMode) {
  const buildContext = await context(buildOptions);
  await buildContext.watch();
  console.log('watching terminal client source');
} else {
  await build(buildOptions);
}

const xtermCssPath = dirname(require.resolve('@xterm/xterm/package.json'));
const xtermCss = readFileSync(join(xtermCssPath, 'css/xterm.css'), 'utf8');
const appCss = `
:root {
  color-scheme: light dark;
  --terminal-bg: #fdf6e3;
  --terminal-fg: #657b83;
}

html,
body {
  width: 100%;
  height: 100%;
  margin: 0;
  padding: 0;
}

body {
  overflow: hidden;
  background: var(--terminal-bg);
  color: var(--terminal-fg);
}

#app {
  position: relative;
  width: 100%;
  height: 100%;
  background: var(--terminal-bg);
}

#terminal {
  width: 100%;
  height: 100%;
  box-sizing: border-box;
  background: var(--terminal-bg);
}

#terminal .xterm {
  background: var(--terminal-bg);
}

.terminal-status {
  position: absolute;
  top: 16px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 10;
  padding: 10px 14px;
  border-radius: 999px;
  border: 1px solid ButtonBorder;
  background: Canvas;
  color: CanvasText;
  font: 13px/1.2 "Noto Sans", "Noto Sans CJK SC", "Noto Sans CJK TC", "Noto Sans CJK HK", "Noto Sans CJK JP", "Noto Sans CJK KR", "Noto Color Emoji", sans-serif;
  opacity: 0;
  pointer-events: none;
  transition: opacity 120ms ease;
}

.terminal-status[data-visible="true"] {
  opacity: 1;
}

.terminal-status a {
  color: LinkText;
}
`;

writeFileSync(join(outdir, 'terminal.css'), `${xtermCss}\n${appCss}`);

if (watchMode) {
  await new Promise(() => {});
}
