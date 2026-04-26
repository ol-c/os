#!/usr/bin/env node

import { execFile } from 'node:child_process';
import { mkdir, readdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const operatorRoot = process.env.OLC_VM_OPERATOR_ROOT || '/source/.olc-debug/operator/current';
const requestsDir = join(operatorRoot, 'requests');
const runningDir = join(operatorRoot, 'running');
const resultsDir = join(operatorRoot, 'results');
const machineIdPath = process.env.OLC_VM_LINEAGE_ENV || '/run/olc-vm-lineage.env';
const loginctlBin = process.env.OLC_LOGINCTL || 'loginctl';
const getentBin = process.env.OLC_GETENT || 'getent';
const runuserBin = process.env.OLC_RUNUSER || 'runuser';
const nodeBin = process.env.OLC_NODE || 'node';
const envBin = process.env.OLC_ENV || 'env';
const sourceRoot = process.env.OLC_SOURCE_ROOT || '/source';
const bidiScript = process.env.OLC_FIREFOX_BIDI_SCRIPT || join(sourceRoot, 'tools', 'olc-firefox-bidi.mjs');
const bidiUrlHelper = process.env.OLC_FIREFOX_BIDI_URL_HELPER || '/run/current-system/sw/bin/olc-firefox-bidi-url';

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function parseEnvFile(input) {
  const map = {};
  for (const line of String(input).split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || !trimmed.includes('=')) {
      continue;
    }
    const separator = trimmed.indexOf('=');
    map[trimmed.slice(0, separator)] = trimmed.slice(separator + 1);
  }
  return map;
}

async function execCapture(command, args) {
  return new Promise((resolve, reject) => {
    const child = execFile(command, args, { encoding: 'utf8' }, (error, stdout, stderr) => {
      if (error) {
        const message = String(stderr || stdout || error.message).trim();
        reject(new Error(message || `command failed: ${command}`));
        return;
      }
      resolve(String(stdout).trim());
    });
    child.stdin?.end();
  });
}

async function activeSessionUser() {
  const activeSession = await execCapture(loginctlBin, [ 'show-seat', 'seat0', '--property=ActiveSession', '--value' ]);
  if (!activeSession) {
    throw new Error('no active seat0 session');
  }

  const sessionInfo = await execCapture(loginctlBin, [
    'show-session',
    activeSession,
    '--property=Name',
    '--property=User',
    '--property=Remote',
    '--property=State',
  ]);
  const properties = parseEnvFile(sessionInfo);
  if (properties.Remote === 'yes') {
    throw new Error(`active session ${activeSession} is remote`);
  }
  if (properties.State && properties.State !== 'active') {
    throw new Error(`active session ${activeSession} is not active`);
  }
  const sessionName = properties.Name || properties.User || '';
  if (!sessionName) {
    throw new Error(`active session ${activeSession} does not expose a user name`);
  }

  const passwdEntry = await execCapture(getentBin, [ 'passwd', sessionName ]);
  const fields = passwdEntry.split(':');
  if (fields.length < 7) {
    throw new Error(`unable to resolve passwd entry for ${sessionName}`);
  }

  return {
    name: sessionName,
    uid: fields[2],
    home: fields[5],
  };
}

async function currentMachineId() {
  const lineage = parseEnvFile(await readFile(machineIdPath, 'utf8'));
  return lineage.OLC_VM_MACHINE_ID || '';
}

async function executeRequest(request, requestPath) {
  const session = await activeSessionUser();
  const args = [];

  if (request.contextUrlPrefix) {
    args.push('--context-url-prefix', request.contextUrlPrefix);
  }
  args.push(request.action, request.argument);

  const stdout = await execCapture(runuserBin, [
    '-u',
    session.name,
    '--',
    envBin,
    `OLC_FIREFOX_BIDI_URL_HELPER=${bidiUrlHelper}`,
    `OLC_SOURCE_ROOT=${sourceRoot}`,
    nodeBin,
    bidiScript,
    ...args,
  ]);

  return {
    ok: true,
    action: request.action,
    argument: request.argument,
    requestPath,
    machineId: await currentMachineId(),
    user: session.name,
    stdout,
  };
}

async function handleRequestFile(name) {
  const requestPath = join(requestsDir, name);
  const runningPath = join(runningDir, name);
  const resultPath = join(resultsDir, name);
  const localMachineId = await currentMachineId();
  let queuedRequest;

  try {
    queuedRequest = JSON.parse(await readFile(requestPath, 'utf8'));
  } catch {
    return;
  }

  if (queuedRequest.targetMachineId && queuedRequest.targetMachineId !== localMachineId) {
    return;
  }

  try {
    await rename(requestPath, runningPath);
  } catch {
    return;
  }

  let request;
  try {
    request = JSON.parse(await readFile(runningPath, 'utf8'));
    if (request.targetMachineId && request.targetMachineId !== localMachineId) {
      throw new Error(`claimed request targets ${request.targetMachineId}, not ${localMachineId}`);
    }

    console.log(`olc-vm-operator claim id=${request.id || name} action=${request.action} target=${request.targetMachineId || ''}`);
    const result = await executeRequest(request, runningPath);
    await writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`);
    console.log(`olc-vm-operator complete id=${request.id || name}`);
  } catch (error) {
    const failure = {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
      machineId: await currentMachineId(),
    };
    await writeFile(resultPath, `${JSON.stringify(failure, null, 2)}\n`);
    console.error(`olc-vm-operator failed file=${name}: ${failure.error}`);
  } finally {
    await rm(runningPath, { force: true });
  }
}

async function ensureDirs() {
  for (const dir of [ operatorRoot, requestsDir, runningDir, resultsDir ]) {
    await mkdir(dir, { recursive: true });
  }
}

async function listRequestNames() {
  try {
    const directory = await readdir(requestsDir);
    return directory.filter(name => name.endsWith('.json')).sort();
  } catch {
    return [];
  }
}

async function main() {
  await ensureDirs();
  while (true) {
    const names = await listRequestNames();
    for (const name of names) {
      await handleRequestFile(name);
    }
    await sleep(200);
  }
}

await main();
