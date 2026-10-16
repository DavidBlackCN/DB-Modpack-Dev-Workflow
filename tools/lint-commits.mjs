import { run, requireSuccess } from './lib/pakku.mjs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const args = process.argv.slice(2);
if (!args.length) args.push('--from', 'HEAD~1', '--to', 'HEAD', '--verbose');
try { requireSuccess(await run(process.execPath, [require.resolve('@commitlint/cli/cli.js'), ...args])); }
catch (e) { console.error(e.message); process.exitCode = e.exitCode ?? 1; }
