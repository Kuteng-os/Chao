// CI entry: node tools/library/validate_submission.mjs <file>...  Prints JSON; exit 1 when any file fails.
// Accepts card packs (pack-*.pack.json), their art (pack-*-*.png) and legacy single cards (card-*.card.json, card-*.png).
import {basename} from 'node:path';
import {loadCatalog} from './catalog_io.mjs';
import {checkPack, checkSubmission, strayPackArt} from './submission.mjs';

const catalog = loadCatalog();
const paths = process.argv.slice(2);
const revisionNote = (target, label = '这张投稿') => `${label}会修改已有卡牌《${target.definition.name}》v${target.revision}（原作者：${target.author?.name ?? '未署名'}）。`;

const packs = [];
const results = paths.filter(path => path.endsWith('.pack.json') || path.endsWith('.card.json')).map(path => {
  if (path.endsWith('.pack.json')) {
    const checked = checkPack(path, catalog);
    packs.push(checked);
    const notes = [];
    if (checked.pack?.name && checked.cards) notes.push(`卡包《${checked.pack.name}》，${checked.cards.length} 张卡，作者 ${String(checked.pack.author).trim()}。`);
    for (const card of checked.cards ?? []) if (card.target) notes.push(revisionNote(card.target, card.label));
    return {file: basename(path), errors: checked.errors, notes};
  }
  const {errors, target} = checkSubmission(path, catalog);
  return {file: basename(path), errors, notes: target ? [revisionNote(target)] : []};
});
const stray = strayPackArt(paths.map(path => basename(path)), packs.filter(pack => pack.digest));
if (stray.length) results.push({file: stray.join('、'), errors: stray.map(name => `${name} 不属于卡包里的任何一张卡。`), notes: []});

const ok = results.length > 0 && results.every(result => result.errors.length === 0);
console.log(JSON.stringify({ok, results}));
process.exit(ok ? 0 : 1);
