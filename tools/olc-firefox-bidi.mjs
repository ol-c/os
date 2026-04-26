#!/usr/bin/env node

import { execFileSync } from 'node:child_process';

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function usage() {
  console.log(`Usage: olc-firefox-bidi [--ws-url URL] [--context-url-prefix PREFIX] <command> [args]

Commands:
  eval <expression>       Evaluate JavaScript in the matching localhost page context.
  navigate <url>          Navigate the matching top-level context to a URL.
  click <selector>        Click the first DOM element matching the CSS selector.
  text <selector>         Print textContent for the first DOM element matching the selector.
`);
}

export function resolveBidiWsUrl(options = {}) {
  if (options.wsUrl) {
    return options.wsUrl;
  }

  const helper = options.helperPath
    || process.env.OLC_FIREFOX_BIDI_URL_HELPER
    || '/run/current-system/sw/bin/olc-firefox-bidi-url';
  try {
    return execFileSync(helper, [], {
      encoding: 'utf8',
      stdio: [ 'ignore', 'pipe', 'pipe' ],
    }).trim();
  } catch (error) {
    const stderr = error?.stderr ? String(error.stderr).trim() : '';
    fail(stderr || `unable to resolve Firefox BiDi URL with ${helper}`);
  }
}

export class BidiConnection {
  constructor(url, webSocketFactory = target => new WebSocket(target)) {
    this.url = url;
    this.webSocketFactory = webSocketFactory;
    this.socket = null;
    this.nextId = 1;
    this.pending = new Map();
  }

  async connect() {
    this.socket = this.webSocketFactory(this.url);

    await new Promise((resolve, reject) => {
      const onOpen = () => {
        cleanup();
        resolve();
      };
      const onError = event => {
        cleanup();
        reject(event?.error || new Error('WebSocket connection failed'));
      };
      const cleanup = () => {
        this.socket.removeEventListener?.('open', onOpen);
        this.socket.removeEventListener?.('error', onError);
      };

      this.socket.addEventListener('open', onOpen);
      this.socket.addEventListener('error', onError);
    });

    this.socket.addEventListener('message', event => this.onMessage(event.data));
    this.socket.addEventListener('close', () => {
      for (const { reject } of this.pending.values()) {
        reject(new Error('BiDi socket closed'));
      }
      this.pending.clear();
    });
  }

  onMessage(raw) {
    let message;
    try {
      message = JSON.parse(String(raw));
    } catch {
      return;
    }

    if (!Object.prototype.hasOwnProperty.call(message, 'id')) {
      return;
    }

    const pending = this.pending.get(message.id);
    if (!pending) {
      return;
    }

    this.pending.delete(message.id);
    if (message.error) {
      pending.reject(new Error(message.message || message.error));
      return;
    }

    pending.resolve(message.result);
  }

  sendCommand(method, params = {}) {
    const id = this.nextId++;
    const payload = { id, method, params };

    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify(payload));
    });
  }

  close() {
    this.socket?.close();
    this.socket = null;
  }
}

export async function withBidiSession(options, callback) {
  const connection = options.connection || new BidiConnection(resolveBidiWsUrl(options), options.webSocketFactory);
  const ownsConnection = !options.connection;

  if (ownsConnection) {
    await connection.connect();
  }

  let createdSession = false;
  try {
    await connection.sendCommand('session.new', {
      capabilities: {
        alwaysMatch: {
          acceptInsecureCerts: true,
        },
      },
    });
    createdSession = true;

    return await callback(connection);
  } finally {
    if (createdSession) {
      try {
        await connection.sendCommand('session.end', {});
      } catch {
        // ignore teardown failure
      }
    }
    if (ownsConnection) {
      connection.close();
    }
  }
}

export function pickContext(tree, prefix) {
  const queue = Array.isArray(tree) ? [ ...tree ] : [];

  while (queue.length > 0) {
    const context = queue.shift();
    const url = String(context?.url || '');
    if (!prefix || url.startsWith(prefix)) {
      return context;
    }
    for (const child of context?.children || []) {
      queue.push(child);
    }
  }

  return null;
}

export async function runBidiCommand(options) {
  const contextUrlPrefix = options.contextUrlPrefix || 'https://localhost/';

  return withBidiSession(options, async connection => {
    const tree = await connection.sendCommand('browsingContext.getTree', {});
    const context = pickContext(tree.contexts, contextUrlPrefix);
    if (!context?.context) {
      throw new Error(`unable to find a Firefox browsing context for ${contextUrlPrefix}`);
    }

    switch (options.command) {
      case 'eval': {
        const result = await connection.sendCommand('script.evaluate', {
          target: { context: context.context },
          expression: options.argument,
          awaitPromise: true,
          resultOwnership: 'none',
        });
        return result?.result?.value ?? result;
      }
      case 'navigate': {
        return connection.sendCommand('browsingContext.navigate', {
          context: context.context,
          url: options.argument,
          wait: 'complete',
        });
      }
      case 'click': {
        return connection.sendCommand('script.evaluate', {
          target: { context: context.context },
          awaitPromise: true,
          resultOwnership: 'none',
          expression: `
            (() => {
              const node = document.querySelector(${JSON.stringify(options.argument)});
              if (!node) {
                throw new Error('selector not found: ${String(options.argument).replaceAll("'", "\\'")}');
              }
              node.click();
              return true;
            })()
          `,
        });
      }
      case 'text': {
        const result = await connection.sendCommand('script.evaluate', {
          target: { context: context.context },
          awaitPromise: true,
          resultOwnership: 'none',
          expression: `
            (() => {
              const node = document.querySelector(${JSON.stringify(options.argument)});
              if (!node) {
                throw new Error('selector not found: ${String(options.argument).replaceAll("'", "\\'")}');
              }
              return node.textContent ?? '';
            })()
          `,
        });
        return result?.result?.value ?? '';
      }
      default:
        throw new Error(`unsupported command: ${options.command}`);
    }
  });
}

function parseArgs(argv) {
  const options = {
    wsUrl: '',
    contextUrlPrefix: 'https://localhost/',
  };
  const positional = [];

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help') {
      usage();
      process.exit(0);
    }
    if (arg === '--ws-url') {
      options.wsUrl = argv[index + 1] || '';
      index += 1;
      continue;
    }
    if (arg === '--context-url-prefix') {
      options.contextUrlPrefix = argv[index + 1] || '';
      index += 1;
      continue;
    }
    positional.push(arg);
  }

  options.command = positional[0] || '';
  options.argument = positional[1] || '';
  return options;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.command || !options.argument) {
    usage();
    process.exit(options.command ? 1 : 0);
  }

  try {
    const result = await runBidiCommand(options);
    if (typeof result === 'string') {
      console.log(result);
    } else if (result !== undefined) {
      console.log(JSON.stringify(result));
    }
  } catch (error) {
    fail(error instanceof Error ? error.message : String(error));
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
