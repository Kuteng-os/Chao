// CI entry: node tools/library/validate_submission.mjs <file.card.json>...  Prints JSON; exit 1 when any file fails.
import {basename} from 'node:path';
import {loadCatalog} from './catalog_io.mjs';
import {checkSubmission} from './submission.mjs';

const catalog = loadCatalog();
const results = process.argv.slice(2).map(path => ({file: path.split(/[\/]/).pop(), errors: checkSubmission(path, catalog).errors}));
const ok = results.length > 0 && results.every(result => result.errors.length === 0);
console.log(JSON.stringify({ok, results}));
process.exit(ok ? 0 : 1);
