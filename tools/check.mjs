// The addon's checks, as CI runs them and as anyone can run them from the addon's folder:
// `node tools/check.mjs`. Every Lua file must parse, and the recorder must get through its
// stand-in client (tools/recorder-mock.lua) without a Lua error, without writing an ERR line
// (or a SPEECH line, which is switched off), and without the stand-in finding any of the lines
// it checks wrong ("-- expect FAIL"). Needs Node and nothing installed: npx fetches luaparse and
// fengari, at the versions named below.
//
// fengari, the Lua the stand-in client runs on, exits with success even when the Lua code
// throws, so a run is judged by what it prints: a "stack traceback" is an error, and the
// stand-in ends with a summary line that a run cut short never reaches.

import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const LUAPARSE = 'luaparse@0.3.1';
const FENGARI = 'fengari-node-cli@0.1.0';
const npx = process.platform === 'win32' ? 'npx.cmd' : 'npx';
// The addon's folder, wherever the check is started from.
const root = join(dirname(fileURLToPath(import.meta.url)), '..');

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
	if (output) console.error(output.split('\n').slice(-20).join('\n'));
}

for (const folder of ['.', 'tools']) {
	for (const name of readdirSync(join(root, folder)).filter((file) => file.endsWith('.lua'))) {
		const file = relative(root, join(root, folder, name)).split('\\').join('/');
		const result = run([LUAPARSE, file]);
		if (result.status !== 0) fail(`${file} doesn't parse`, result.output);
		else console.log(`parses: ${file}`);
	}
}

const recorder = run(['-p', FENGARI, 'fengari', 'tools/recorder-mock.lua']).output;
const summary = recorder.split('\n').find((line) => /^-- [A-Z]+=\d/.test(line));
if (recorder.includes('stack traceback')) fail('the recorder threw under its stand-in client', recorder);
else if (!summary) fail("the recorder's stand-in client never reached its summary", recorder);
else if (/\bERR=/.test(summary)) fail('the recorder wrote ERR lines', recorder);
else if (/\bSPEECH=/.test(summary)) fail('the recorder wrote SPEECH lines, which are switched off', recorder);
else if (/^-- chat: /m.test(recorder)) fail('the recorder said something went wrong in chat', recorder);
else if (/^-- expect FAIL/m.test(recorder)) fail("the recorder's lines aren't what its stand-in client expects", recorder);
else console.log(`recorder: ${summary}`);

process.exit(failed ? 1 : 0);
