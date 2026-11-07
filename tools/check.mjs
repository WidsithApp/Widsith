// The addon's checks, as CI runs them and as anyone can run them from the addon's folder:
// `node tools/check.mjs`. Every Lua file must parse as the game's Lua 5.1 would read it, and
// every test under tools/tests must pass on the stand-in client (tools/harness). Needs Node and
// nothing installed: npx fetches luaparse and fengari, at the versions named below.
//
// fengari, the Lua the stand-in client runs on, exits with success even when the Lua code
// throws, so the runner reports through its exit code and a run cut short by an error (a
// "stack traceback" with no summary line) is a failure too.
//
// `node tools/check.mjs tests` runs the tests alone; `node tools/check.mjs tests money` runs the
// test files whose names contain the word.

import { spawnSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const LUAPARSE = 'luaparse@0.3.1';
const FENGARI = 'fengari-node-cli@0.1.0';
const npx = process.platform === 'win32' ? 'npx.cmd' : 'npx';
// The addon's folder, wherever the check is started from.
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const [mode, filter] = process.argv.slice(2);

function run(args) {
	const result = spawnSync(npx, ['--yes', ...args], {
		cwd: root,
		encoding: 'utf8',
		shell: process.platform === 'win32'
	});
	return { status: result.status, output: `${result.stdout ?? ''}${result.stderr ?? ''}` };
}

let failed = false;
function fail(message, output = '') {
	failed = true;
	console.error(`FAIL ${message}`);
	if (output) console.error(output.split('\n').slice(-30).join('\n'));
}

const luaFiles = (folder) =>
	readdirSync(join(root, folder))
		.filter((file) => file.endsWith('.lua'))
		.sort()
		.map((name) => relative(root, join(root, folder, name)).split('\\').join('/'));

if (mode !== 'tests') {
	for (const folder of ['.', 'tools', 'tools/harness', 'tools/tests']) {
		for (const file of luaFiles(folder)) {
			const result = run([LUAPARSE, file]);
			if (result.status !== 0) fail(`${file} doesn't parse`, result.output);
			else console.log(`parses: ${file}`);
		}
	}
}

const version = readFileSync(join(root, 'Widsith.toc'), 'utf8').match(/^## Version:\s*(\S+)/m)?.[1] ?? '0.0.0';
const tests = luaFiles('tools/tests').filter((file) => !filter || file.includes(filter));
if (tests.length === 0) fail('no test files to run');
else {
	const result = run(['-p', FENGARI, 'fengari', 'tools/harness/run.lua', '--version', version, ...tests]);
	const summary = result.output.split('\n').find((line) => /^-- \d+ passed/.test(line));
	if (result.output.includes('stack traceback') && !summary) fail('the test run ended in a Lua error', result.output);
	else if (!summary) fail('the test run never reached its summary', result.output);
	else if (result.status !== 0) fail(`tests failed: ${summary}`, result.output);
	else {
		console.log(result.output.trimEnd());
	}
}

process.exit(failed ? 1 : 0);
