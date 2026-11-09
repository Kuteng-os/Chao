// Accepts a checked submission into data/catalog.json.
// node tools/library/add_card.mjs submissions/inbox/card-xxx.card.json [--replace <card_id>] [--series <n>] [--dry-run]
// A submission carrying "replaces" revises that card without --replace. Revisions keep the original pack and author.
import {readFileSync, writeFileSync, renameSync, mkdirSync} from 'node:fs';
import {basename, join} from 'node:path';
import {acceptSubmission, replacedSummary} from './accept.mjs';
import {DATA, ROOT, loadCatalog, saveCatalog} from './catalog_io.mjs';
import {checkSubmission} from './submission.mjs';

const args = process.argv.slice(2);
const option = name => { const index = args.indexOf(name); return index < 0 ? null : args.splice(index, 2)[1]; };
const replace = option('--replace'), series = option('--series');
const dryRun = args.includes('--dry-run');
const path = args.find(arg => !arg.startsWith('--'));
if (!path) throw new Error('Usage: add_card.mjs <file.card.json> [--replace <card_id>] [--series <n>] [--dry-run]');

const catalog = loadCatalog();
const {errors, compiled, submission, artPath} = checkSubmission(path, catalog);
if (errors.length) { console.error(`校验失败：\n- ${errors.join('\n- ')}`); process.exit(1); }

const artBytes = artPath ? readFileSync(artPath) : null;
const accepted = acceptSubmission(catalog, {compiled, submission, artBytes, replaceId: replace ?? submission.replaces?.card_id ?? null, series: series ? Number(series) : null});
const {record, art, previous} = accepted;

console.log(JSON.stringify({card_id: record.card_id, revision: record.revision, name: record.definition.name, series: record.series, rules_text: record.rules_text, replaces: replacedSummary(previous)}, null, 1));
if (dryRun) process.exit(0);

if (art) writeFileSync(join(DATA, 'art', `${art.id}.bin`), artBytes);
saveCatalog(accepted.catalog);
const acceptedDirectory = join(ROOT, 'submissions', 'accepted');
mkdirSync(acceptedDirectory, {recursive: true});
renameSync(path, join(acceptedDirectory, basename(path)));
if (artPath) renameSync(artPath, join(acceptedDirectory, basename(artPath)));
console.log('已写入 data/catalog.json；git push 到 main 后玩家下次启动自动更新。');
