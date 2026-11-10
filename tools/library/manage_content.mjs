// Maintainer edits that have no submission file: registering factions and archiving cards.
//   node tools/library/manage_content.mjs faction add --name <名称> --color <#rrggbb> [--category large|normal|small] [--author <署名>] [--dry-run]
//   node tools/library/manage_content.mjs card archive|restore <card_id> [--dry-run]
//   node tools/library/manage_content.mjs keyword add <keyword.json> [--dry-run]
// A builtin keyword also needs engine support and a new client; a template keyword only needs a client that knows its effects.
// Archiving keeps the card resolvable for existing decks; it only leaves the live pool, the same as the old server did.
import {createHash, randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {validateKeyword} from '../../server/src/validation.js';
import {loadCatalog, saveCatalog} from './catalog_io.mjs';

const CATEGORIES = ['large', 'normal', 'small'];
const args = process.argv.slice(2);
const option = name => { const index = args.indexOf(name); return index < 0 ? null : args.splice(index, 2)[1]; };
const dryRun = args.includes('--dry-run');
const stop = message => { console.error(message); process.exit(1); };
const authorFor = name => ({id: createHash('sha256').update(`frontline-author:github:${name}`).digest('hex').slice(0, 24), name});

function addFaction(catalog) {
  const name = option('--name')?.trim(), color = option('--color'), category = option('--category') ?? 'normal', author = option('--author')?.trim();
  if (!name || [...name].length > 64) stop('--name 需为 1 至 64 个字符。');
  if (!/^#[0-9a-fA-F]{6}$/.test(color ?? '')) stop('--color 需为 #rrggbb。');
  if (!CATEGORIES.includes(category)) stop(`--category 只能是 ${CATEGORIES.join('、')}。`);
  const key = text => text.normalize('NFC').toLowerCase();
  if (catalog.factions.some(faction => key(faction.name) === key(name))) stop(`阵营「${name}」已经登记。`);
  const faction = {category, archived: false, faction_id: randomUUID(), revision: 1, name, role: 'major', color: color.toLowerCase(), icon_id: null, background_id: null, author: author ? authorFor(author) : null, can_edit: false};
  return {catalog: {...catalog, factions: [...catalog.factions, faction].sort((a, b) => a.name.localeCompare(b.name, 'zh'))}, report: {faction_id: faction.faction_id, name, category, color: faction.color}};
}

function setArchived(catalog, archived) {
  const id = args[2];
  const card = catalog.cards.find(entry => entry.card_id === id);
  if (!card) stop(`卡库中没有 ${id}。`);
  if (card.derived_from) stop(`衍生卡跟随来源卡《${card.derived_from.name}》归档，请处理来源卡。`);
  const family = entry => entry.card_id === id || entry.derived_from?.card_id === id;
  const lifecycle = {...catalog.lifecycle, cards: {...catalog.lifecycle.cards, [id]: {...catalog.lifecycle.cards[id], archived, revision: card.revision}}};
  const cards = catalog.cards.map(entry => family(entry) ? {...entry, archived: archived || Boolean(entry.derived_from?.retired)} : entry);
  return {catalog: {...catalog, lifecycle, cards}, report: {card_id: id, name: card.definition.name, archived, records: cards.filter(family).length}};
}

function addKeyword(catalog) {
  const file = args[2];
  if (!file) stop('需要词条定义文件。');
  const {definition, definition_hash} = validateKeyword(JSON.parse(readFileSync(file, 'utf8')), {allowBuiltin: true});
  if (catalog.keywords.some(entry => entry.definition.id === definition.id && entry.definition.version === definition.version)) stop(`词条 ${definition.id}@${definition.version} 已经登记。`);
  const entry = {definition_hash, definition, archived: false, can_manage: false, owned_by_me: false, can_edit: false};
  return {catalog: {...catalog, keywords: [...catalog.keywords, entry]}, report: {id: definition.id, version: definition.version, name: definition.name, kind: definition.implementation.kind}};
}

const [area, action] = args;
const catalog = loadCatalog();
let result;
if (area === 'faction' && action === 'add') result = addFaction(catalog);
else if (area === 'keyword' && action === 'add') result = addKeyword(catalog);
else if (area === 'card' && ['archive', 'restore'].includes(action)) result = setArchived(catalog, action === 'archive');
else stop('用法见文件开头的注释。');
console.log(JSON.stringify(result.report, null, 1));
if (!dryRun) console.log(`卡库版本：${saveCatalog(result.catalog).catalog_version}`);
