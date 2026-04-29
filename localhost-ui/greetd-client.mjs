import net from 'node:net';

function validationError(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function protocolError(message) {
  const error = new Error(message);
  error.statusCode = 502;
  return error;
}

function authError(message) {
  const error = new Error(message || 'Authentication failed.');
  error.statusCode = 401;
  error.code = 'auth_error';
  return error;
}

function writeMessage(socket, payload) {
  return new Promise((resolve, reject) => {
    const body = Buffer.from(JSON.stringify(payload), 'utf8');
    const header = Buffer.allocUnsafe(4);
    header.writeUInt32LE(body.length, 0);
    socket.write(Buffer.concat([ header, body ]), error => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}

function takeMessage(buffer) {
  if (buffer.length < 4) {
    return null;
  }

  const bodyLength = buffer.readUInt32LE(0);
  if (buffer.length < 4 + bodyLength) {
    return null;
  }

  const body = buffer.subarray(4, 4 + bodyLength);
  return {
    message: JSON.parse(body.toString('utf8')),
    rest: buffer.subarray(4 + bodyLength),
  };
}

function mapPromptType(type) {
  if (type === 'secret' || type === 'visible') {
    return type;
  }
  return 'visible';
}

export class GreetdClient {
  #socketPath;
  #sessionCommand;
  #sessionEnv;
  #socket = null;
  #buffer = Buffer.alloc(0);
  #reader = null;

  constructor(options = {}) {
    const socketPath = options.socketPath ?? process.env.GREETD_SOCK;
    const sessionCommand = options.sessionCommand ?? process.env.OLC_GREETD_LOGIN_CMD;

    if (!socketPath) {
      throw new Error('GREETD_SOCK is required for the browser greeter');
    }
    if (!sessionCommand) {
      throw new Error('OLC_GREETD_LOGIN_CMD is required for the browser greeter');
    }

    this.#socketPath = socketPath;
    this.#sessionCommand = sessionCommand;
    this.#sessionEnv = Array.isArray(options.sessionEnv)
      ? options.sessionEnv
      : String(options.sessionEnv ?? '').split('\n').map(line => line.trim()).filter(Boolean);
  }

  async authenticate(body) {
    const username = String(body?.username || '').trim();
    const password = String(body?.password || '');

    if (!username) {
      throw validationError('username is required');
    }

    if (!password) {
      throw validationError('password is required');
    }

    await this.cancel();
    await this.#connect();
    await this.#send({
      type: 'create_session',
      username,
    });
    return await this.#advance({ queuedAnswer: password });
  }

  async respond(body) {
    if (!this.#socket) {
      throw validationError('no login prompt is active', 409);
    }

    await this.#send({
      type: 'post_auth_message_response',
      response: body?.response == null ? null : String(body.response),
    });
    return await this.#advance();
  }

  async cancel() {
    if (!this.#socket) {
      return { ok: true, cancelled: true };
    }

    try {
      await this.#send({ type: 'cancel_session' });
      await this.#readResponse();
    } catch {
      // Ignore cancellation failures and tear down local state.
    } finally {
      this.#destroySocket();
    }

    return { ok: true, cancelled: true };
  }

  async #connect() {
    if (this.#socket) {
      return;
    }

    const socket = await new Promise((resolve, reject) => {
      const client = net.createConnection(this.#socketPath, () => resolve(client));
      client.on('error', reject);
    });
    socket.setNoDelay(true);
    this.#socket = socket;
    this.#buffer = Buffer.alloc(0);
    this.#reader = null;
  }

  #destroySocket() {
    this.#reader?.reject?.(protocolError('greetd socket closed'));
    this.#reader = null;
    if (this.#socket) {
      this.#socket.destroy();
    }
    this.#socket = null;
    this.#buffer = Buffer.alloc(0);
  }

  async #send(message) {
    if (!this.#socket) {
      throw protocolError('greetd socket is not connected');
    }

    await writeMessage(this.#socket, message);
  }

  async #readResponse() {
    if (!this.#socket) {
      throw protocolError('greetd socket is not connected');
    }

    const parsed = takeMessage(this.#buffer);
    if (parsed) {
      this.#buffer = parsed.rest;
      return parsed.message;
    }

    return await new Promise((resolve, reject) => {
      const socket = this.#socket;
      const cleanup = () => {
        socket.off('data', onData);
        socket.off('error', onError);
        socket.off('close', onClose);
      };
      const settle = fn => value => {
        cleanup();
        this.#reader = null;
        fn(value);
      };
      const onError = settle(reject);
      const onClose = settle(() => reject(protocolError('greetd socket closed')));
      const onData = chunk => {
        this.#buffer = Buffer.concat([ this.#buffer, chunk ]);
        const next = takeMessage(this.#buffer);
        if (!next) {
          return;
        }

        this.#buffer = next.rest;
        settle(resolve)(next.message);
      };

      this.#reader = {
        reject: settle(reject),
      };

      socket.on('data', onData);
      socket.on('error', onError);
      socket.on('close', onClose);
    });
  }

  async #advance(options = {}) {
    let queuedAnswer = Object.prototype.hasOwnProperty.call(options, 'queuedAnswer')
      ? options.queuedAnswer
      : undefined;
    const notices = [];

    for (;;) {
      const response = await this.#readResponse();

      if (response?.type === 'auth_message') {
        if (response.auth_message_type === 'info' || response.auth_message_type === 'error') {
          notices.push({
            level: response.auth_message_type,
            text: String(response.auth_message || ''),
          });
          await this.#send({
            type: 'post_auth_message_response',
            response: null,
          });
          continue;
        }

        if (queuedAnswer !== undefined) {
          const answer = queuedAnswer;
          queuedAnswer = undefined;
          await this.#send({
            type: 'post_auth_message_response',
            response: answer,
          });
          continue;
        }

        return {
          ok: true,
          status: 'prompt',
          prompt: {
            type: mapPromptType(response.auth_message_type),
            message: String(response.auth_message || ''),
          },
          notices,
        };
      }

      if (response?.type === 'success') {
        await this.#send({
          type: 'start_session',
          cmd: [ this.#sessionCommand ],
          env: this.#sessionEnv,
        });
        const startResponse = await this.#readResponse();
        if (startResponse?.type !== 'success') {
          this.#destroySocket();
          throw protocolError('greetd rejected session start');
        }

        this.#destroySocket();
        return {
          ok: true,
          status: 'starting',
          notices,
        };
      }

      if (response?.type === 'error') {
        const description = String(response.description || '').trim();
        const errorType = String(response.error_type || 'error');
        this.#destroySocket();
        if (errorType === 'auth_error') {
          throw authError(description || 'Authentication failed.');
        }
        throw protocolError(description || 'greetd rejected the login request');
      }

      this.#destroySocket();
      throw protocolError('unexpected greetd response');
    }
  }
}
