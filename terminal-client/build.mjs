import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';
import { build } from 'esbuild';

const outdir = join(process.cwd(), 'dist');
const require = createRequire(import.meta.url);

mkdirSync(outdir, { recursive: true });

await build({
  entryPoints: [join(process.cwd(), 'src/index.js')],
  bundle: true,
  format: 'iife',
  target: 'es2022',
  platform: 'browser',
  outfile: join(outdir, 'terminal.js'),
  minify: false,
  sourcemap: false,
});

const xtermCssPath = dirname(require.resolve('@xterm/xterm/package.json'));
const xtermCss = readFileSync(join(xtermCssPath, 'css/xterm.css'), 'utf8');
const appCss = `
html,
body {
  width: 100%;
  height: 100%;
  margin: 0;
}

body {
  overflow: hidden;
  background:
    radial-gradient(circle at top, rgba(94, 234, 212, 0.1), transparent 28%),
    linear-gradient(180deg, #09111f, #050814);
  color: #e2e8f0;
}

#app {
  position: relative;
  width: 100%;
  height: 100%;
}

#terminal {
  width: 100%;
  height: 100%;
  padding: 12px;
  box-sizing: border-box;
}

.terminal-status {
  position: absolute;
  top: 16px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 10;
  padding: 10px 14px;
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.22);
  background: rgba(15, 23, 42, 0.9);
  color: #e2e8f0;
  font: 13px/1.2 sans-serif;
  opacity: 0;
  pointer-events: none;
  transition: opacity 120ms ease;
}

.terminal-status[data-visible="true"] {
  opacity: 1;
}

.terminal-status a {
  color: #93c5fd;
}
`;

writeFileSync(join(outdir, 'terminal.css'), `${xtermCss}\n${appCss}`);
