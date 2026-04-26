#!/usr/bin/env node

import { execFile } from 'node:child_process';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function usage() {
  console.log(`Usage: olc-vm-bidi [--journal-dir DIR|--journal-file PATH] [--parent-machine-id ID] [--context-url-prefix PREFIX] <command> [arg]

Commands:
  eval <expression>
  navigate <url>
  click <selector>
  text <selector>
`);
}

function parseJournalExport(output) {
  const entries = [];
  let current = {};
  for (const line of String(output).split('\n')) {
    if (!line.trim()) {
      if (Object.keys(current).length > 0) {
        entries.push(current);
        current = {};
      }
      continue;
    }
    const separator = line.indexOf('=');
    if (separator === -1) {
      continue;
    }
    current[line.slice(0, separator)] = line.slice(separator + 1);
  }
  if (Object.keys(current).length > 0) {
    entries.push(current);
  }
  return entries;
}

async function execCapture(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { encoding: 'utf8' }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(String(stderr || stdout || error.message).trim() || `command failed: ${command}`));
        return;
      }
      resolve(String(stdout));
    });
  });
}

async function resolveTargetMachineId(options) {
  const journalctlBin = process.env.OLC_JOURNALCTL || 'journalctl';
  const sourceRoot = process.env.OLC_SOURCE_ROOT || '/source';
  const journalPath = options.journalFile || options.journalPath || `${sourceRoot}/.olc-debug/journal`;
  const journalArg = options.journalFile
    ? `--file=${options.journalFile}`
    : `${options.journalIsFile ? '--file' : '--directory'}=${journalPath}`;

  const output = await execCapture(journalctlBin, [
    journalArg,
    '--no-pager',
    '--output=export',
    '--lines=200',
    'SYSLOG_IDENTIFIER=olc-vm-ready',
    'OLC_VM_READY=embedded-control-ready',
    ...(options.parentMachineId ? [ `OLC_VM_PARENT_MACHINE_ID=${options.parentMachineId}` ] : []),
  ]);
  const entries = parseJournalExport(output).filter(entry => entry.OLC_VM_MACHINE_ID);
  const match = entries.at(-1);
  if (!match?.OLC_VM_MACHINE_ID) {
    fail(`embedded VM ready marker not found in journal ${journalPath}`);
  }
  return match.OLC_VM_MACHINE_ID;
}

function parseArgs(argv) {
  const options = {
    contextUrlPrefix: 'https://localhost/',
    journalPath: process.env.OLC_VM_READY_JOURNAL || `${process.env.OLC_SOURCE_ROOT || '/source'}/.olc-debug/journal`,
    journalIsFile: false,
    parentMachineId: process.env.OLC_VM_PARENT_MACHINE_ID || '',
    journalFile: '',
  };
  const positional = [];

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help') {
      usage();
      process.exit(0);
    }
    if (arg === '--journal-dir') {
      options.journalPath = argv[index + 1] || '';
      options.journalIsFile = false;
      index += 1;
      continue;
    }
    if (arg === '--journal-file') {
      options.journalFile = argv[index + 1] || '';
      options.journalIsFile = true;
      index += 1;
      continue;
    }
    if (arg === '--parent-machine-id') {
      options.parentMachineId = argv[index + 1] || '';
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

async function waitForResult(path, timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const details = await stat(path);
      if (details.isFile()) {
        return JSON.parse(await readFile(path, 'utf8'));
      }
    } catch {
      // keep waiting
    }
    await sleep(100);
  }
  fail(`timed out waiting for VM BiDi result: ${path}`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.command || !options.argument) {
    usage();
    process.exit(options.command ? 1 : 0);
  }

  const targetMachineId = await resolveTargetMachineId(options);
  const operatorRoot = process.env.OLC_VM_OPERATOR_ROOT || '/source/.olc-debug/operator/current';
  const requestsDir = join(operatorRoot, 'requests');
  const resultsDir = join(operatorRoot, 'results');
  const requestId = `bidi-${Date.now()}-${process.pid}`;
  const requestPath = join(requestsDir, `${requestId}.json`);
  const resultPath = join(resultsDir, `${requestId}.json`);

  await mkdir(requestsDir, { recursive: true });
  await mkdir(resultsDir, { recursive: true });

  await writeFile(requestPath, `${JSON.stringify({
    id: requestId,
    action: options.command,
    argument: options.argument,
    contextUrlPrefix: options.contextUrlPrefix,
    targetMachineId,
  }, null, 2)}\n`);

  const result = await waitForResult(resultPath);
  if (!result?.ok) {
    fail(result?.error || 'embedded VM BiDi request failed');
  }

  if (typeof result.stdout === 'string' && result.stdout.length > 0) {
    console.log(result.stdout);
  } else {
    console.log(JSON.stringify(result));
  }
}

await main();
