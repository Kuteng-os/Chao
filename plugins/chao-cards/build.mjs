// Copies the validator, rule documents and catalog into runtime/ so the plugin works without the game repository.
import {copyFileSync, mkdirSync, readdirSync, rmSync, statSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..');
const runtime = join(here, 'runtime');

// fs.cpSync exits silently on non-ASCII Windows paths in Node 22, so files are copied one by one.
function copy(from, to) {
  if (statSync(from).isDirectory()) {
    mkdirSync(to, {recursive: true});
    for (const entry of readdirSync(from)) copy(join(from, entry), join(to, entry));
    return;
  }
  mkdirSync(dirname(to), {recursive: true});
  copyFileSync(from, to);
}

rmSync(runtime, {recursive: true, force: true});
for (const path of ['server/src', 'docs/cards', 'web/card_text.mjs', 'web/card_text_rules.json', 'tools/library/accept.mjs', 'tools/library/catalog_io.mjs', 'tools/library/submission.mjs', 'data/catalog.json']) copy(join(repo, path), join(runtime, path));
rmSync(join(runtime, 'docs/cards/examples'), {recursive: true, force: true});
console.log('runtime ready');
