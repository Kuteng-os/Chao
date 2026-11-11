// Accepts one checked inbox file, a card pack or a legacy single card, into data/catalog.json.
// node tools/library/add_card.mjs submissions/inbox/pack-xxx.pack.json [--series <n>] [--dry-run]
// node tools/library/add_card.mjs submissions/inbox/card-xxx.card.json [--replace <card_id>] [--series <n>] [--dry-run]
// Cards carrying "replaces" revise that card; revisions keep the original pack and author. A pack is all-or-nothing.
import {writeFileSync, renameSync, mkdirSync} from 'node:fs';
import {basename, join} from 'node:path';
import {acceptFile, replacedSummary} from './accept.mjs';
import {DATA, ROOT, loadCatalog, saveCatalog} from './catalog_io.mjs';

const args = process.argv.slice(2);
const option = name => { const index = args.indexOf(name); return index < 0 ? null : args.splice(index, 2)[1]; };
const replace = option('--replace'), series = option('--series');
const dryRun = args.includes('--dry-run');
const path = args.find(arg => !arg.startsWith('--'));
if (!path) throw new Error('Usage: add_card.mjs <pack.json|card.json> [--replace <card_id>] [--series <n>] [--dry-run]');
if (replace && path.endsWith('.pack.json')) throw new Error('卡包里的修改请写在每张卡的 replaces 字段，不使用 --replace。');

const accepted = acceptFile(path, loadCatalog(), {series: series ? Number(series) : null, replaceId: replace});
if (accepted.errors.length) { console.error(`校验失败：\n- ${accepted.errors.join('\n- ')}`); process.exit(1); }

console.log(JSON.stringify({name: accepted.name, author: accepted.author, cards: accepted.results.map(({record, previous}) => ({card_id: record.card_id, revision: record.revision, name: record.definition.name, series: record.series, rules_text: record.rules_text, replaces: replacedSummary(previous)}))}, null, 1));
if (dryRun) process.exit(0);

for (const {art, artBytes} of accepted.results) if (art) writeFileSync(join(DATA, 'art', `${art.id}.bin`), artBytes);
saveCatalog(accepted.catalog);
const acceptedDirectory = join(ROOT, 'submissions', 'accepted');
mkdirSync(acceptedDirectory, {recursive: true});
for (const file of accepted.files) renameSync(file, join(acceptedDirectory, basename(file)));
console.log('已写入 data/catalog.json；git push 到 main 后玩家下次启动自动更新。');
