#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { EXIT, fail, kaitoHome, only, parseArgs, run } from './kaito-ledger-lib.mjs';

const labelStem = 'com.kaito.tick';
const tick = fileURLToPath(new URL('./kaito-tick.mjs', import.meta.url));
const usage = `usage: kaito-schedule.mjs install|uninstall|status [--label ${labelStem}.test]`;

function launch(...args) {
  const result = spawnSync('/bin/launchctl', args, { encoding: 'utf8' });
  if (result.error) throw result.error;
  return result;
}

function checked(result) {
  if (result.status !== 0) fail(EXIT.error, result.stderr.trim() || 'launchctl failed');
  process.stdout.write(result.stdout);
}

const xml = (value) => value.replace(/[&<>"']/g, (char) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;',
})[char]);

function plist(label, home, logs) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${xml(process.execPath)}</string>
    <string>${xml(tick)}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>KAITO_HOME</key><string>${xml(home)}</string>
    <key>PATH</key><string>${xml(process.env.PATH || '/usr/bin:/bin:/usr/sbin:/sbin')}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>600</integer>
  <key>StandardOutPath</key><string>${xml(path.join(logs, `${label}.out.log`))}</string>
  <key>StandardErrorPath</key><string>${xml(path.join(logs, `${label}.err.log`))}</string>
</dict>
</plist>
`;
}

await run((argv) => {
  if (argv.length === 1 && argv[0] === '--help') { console.log(usage); return; }
  const args = parseArgs(argv);
  only(args, ['label']);
  const [command] = args._;
  const label = args.label ?? labelStem;
  if (args._.length !== 1 || !['install', 'uninstall', 'status'].includes(command) ||
      ![labelStem, `${labelStem}.test`].includes(label)) fail(EXIT.usage, usage);
  if (process.platform !== 'darwin') fail(EXIT.error, 'launchd scheduling requires macOS');

  const domain = `gui/${process.getuid()}`;
  const target = `${domain}/${label}`;
  const file = path.join(os.homedir(), 'Library', 'LaunchAgents', `${label}.plist`);
  const loaded = launch('print', target);
  if (loaded.status !== 0 && !/could not find service/i.test(loaded.stderr)) checked(loaded);
  if (command === 'status') {
    if (loaded.status !== 0) fail(EXIT.notFound, `${target} is not loaded`);
    checked(loaded);
    return;
  }
  if (command === 'uninstall') {
    if (loaded.status === 0) checked(launch('bootout', target));
    fs.rmSync(file, { force: true });
    console.log(`uninstalled=${label}`);
    return;
  }

  const home = path.resolve(kaitoHome());
  const logs = path.join(home, 'business', 'logs');
  fs.mkdirSync(logs, { recursive: true, mode: 0o700 });
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const contents = plist(label, home, logs);
  if (loaded.status === 0) {
    if (fs.existsSync(file) && fs.readFileSync(file, 'utf8') === contents) {
      console.log(`installed=${label}`);
      return;
    }
    fail(EXIT.human, `${target} is already loaded with a different configuration`);
  }
  let created = false;
  try {
    fs.writeFileSync(file, contents, { mode: 0o600, flag: 'wx' });
    created = true;
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    if (fs.readFileSync(file, 'utf8') !== contents) fail(EXIT.human, `${file} already exists with a different configuration`);
  }
  try { checked(launch('bootstrap', domain, file)); } catch (error) {
    if (created && launch('print', target).status !== 0) fs.rmSync(file, { force: true });
    throw error;
  }
  console.log(`installed=${label}`);
});
