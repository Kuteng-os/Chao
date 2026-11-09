// Accepts a checked submission into data/catalog.json.
// node tools/library/add_card.mjs submissions/inbox/card-xxx.card.json [--replace <card_id>] [--series <n>] [--dry-run]
import {randomUUID, createHash} from 'node:crypto';
import {readFileSync, writeFileSync, renameSync, mkdirSync} from 'node:fs';
import {basename, join} from 'node:path';
import {publicCard} from '../../server/src/cloud_catalog.js';
import {rulesText} from '../../server/src/validation.js';
import {DATA, ROOT, loadCatalog, registry, saveCatalog} from './catalog_io.mjs';
import {checkSubmission, pngSize} from './submission.mjs';

const args = process.argv.slice(2);
const option = name => { const index = args.indexOf(name); return index < 0 ? null : args.splice(index, 2)[1]; };
const replace = option('--replace'), series = option('--series');
const dryRun = args.includes('--dry-run');
const path = args.find(arg => !arg.startsWith('--'));
if (!path) throw new Error('Usage: add_card.mjs <file.card.json> [--replace <card_id>] [--series <n>] [--dry-run]');

const catalog = loadCatalog();
const {errors, compiled, submission, artPath} = checkSubmission(path, catalog);
if (errors.length) { console.error(`校验失败：\n- ${errors.join('\n- ')}`); process.exit(1); }

const previous = replace ? catalog.cards.find(card => card.card_id === replace) : null;
if (replace && !previous) throw new Error(`卡库中没有 ${replace}。`);
let art = previous?.art;
const artBytes = artPath ? readFileSync(artPath) : null;
if (artBytes) art = {id: createHash('sha256').update(artBytes).digest('hex'), ...pngSize(artBytes)};

const author = submission.author.trim(), owner = `github:${author}`;
const stored = {
  card_id: previous?.card_id ?? randomUUID(),
  revision: (previous?.revision ?? 0) + 1,
  series: series ? Number(series) : catalog.health.card_series.current,
  ...compiled,
  rules_text: rulesText(compiled.definition),
  interpreter_version: 'interpreter-1',
  compiler_version: 'card-compiler-1',
  provenance: {source_kind: 'github_submission'},
  owner_id: owner,
  created_at: new Date().toISOString(),
  ...(art ? {art} : {}),
  token_art: previous?.token_art ?? {},
};
const record = publicCard(stored, null, false, {keywords: registry(catalog), identities: {[owner]: {display_name: author}}, content_lifecycle: catalog.lifecycle});

console.log(JSON.stringify({card_id: record.card_id, revision: record.revision, name: record.definition.name, series: record.series, rules_text: record.rules_text}, null, 1));
if (dryRun) process.exit(0);

if (artBytes) writeFileSync(join(DATA, 'art', `${art.id}.bin`), artBytes);
saveCatalog({...catalog, cards: [...catalog.cards.filter(card => card.card_id !== record.card_id), record]});
const accepted = join(ROOT, 'submissions', 'accepted');
mkdirSync(accepted, {recursive: true});
renameSync(path, join(accepted, basename(path)));
if (artPath) renameSync(artPath, join(accepted, basename(artPath)));
console.log('已写入 data/catalog.json；git push 到 main 后玩家下次启动自动更新。');
