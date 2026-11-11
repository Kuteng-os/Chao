// Checks player submissions as data only; nothing from the files is ever executed.
// Since 0.10 players submit card packs (pack-<hash>.pack.json); single-card files are still read for older pull requests.
import {readFileSync, existsSync, statSync} from 'node:fs';
import {basename, dirname, join} from 'node:path';
import {hash} from '../../server/src/codec.js';
import {compileCard} from '../../server/src/validation.js';
import {requireCardFaction} from '../../server/src/factions.js';
import {DATA, registry} from './catalog_io.mjs';

export const SUBMISSION_FORMAT = 'chao-card-submission-v1';
export const PACK_FORMAT = 'chao-card-pack-v1';
export const MAX_PNG = 2 * 1024 * 1024;
export const MAX_PACK_CARDS = 20;
const CARD_NAME = /^card-[0-9a-f]{12}\.card\.json$/;
const PACK_NAME = /^pack-([0-9a-f]{12})\.pack\.json$/;
const MAX_JSON = 65536, MAX_PACK_JSON = 1024 * 1024, MAX_SIDE = 1024;
const FIELDS = new Set(['format', 'game_version', 'author', 'definition', 'definition_hash', 'replaces']);
const PACK_FIELDS = new Set(['format', 'game_version', 'author', 'name', 'description', 'cards']);
const ENTRY_FIELDS = new Set(['definition', 'definition_hash', 'replaces']);
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/;

export function pngSize(bytes) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(signature) || bytes.toString('latin1', 12, 16) !== 'IHDR') return null;
  return {width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20)};
}

/** A pack is named after the hashes of its cards, in order, so the file name always matches its content. */
export const packHash = entries => hash(entries.map(entry => entry.definition_hash));
export const packFileName = digest => `pack-${digest.slice(0, 12)}.pack.json`;
export const packArtName = (digest, definitionHash) => `pack-${digest.slice(0, 12)}-${definitionHash.slice(0, 12)}.png`;

function mediaIds(definition) {
  const ids = [];
  for (const owner of [definition, ...(definition.tokens ?? [])]) {
    const {sounds = {}, background, music} = owner?.media ?? {};
    if (background) ids.push(['art', background]);
    for (const id of [...Object.values(sounds), ...(music ? [music] : [])]) ids.push(['sounds', id]);
  }
  return ids;
}

/** The in-game form may choose 无阵营/无罪孽, so faction and an explicit sin are required of plugin submissions only. */
function basicInfoErrors(definition, source) {
  const errors = [];
  if (!String(definition.name ?? '').trim()) errors.push('基本信息缺失：卡牌名称。');
  if (!definition.rarity) errors.push('基本信息缺失：稀有度（rarity）。');
  if (String(source).startsWith('dsh-plugin-')) {
    if (!definition.faction_id) errors.push('基本信息缺失：阵营（faction_id），请从已登记的阵营中选择。');
    if (!Object.hasOwn(definition, 'sin')) errors.push('基本信息缺失：罪孽（sin），确实没有罪孽时明确填 null。');
  }
  return errors;
}

function replacementTarget(replaces, catalog, errors) {
  if (replaces === undefined) return null;
  if (!replaces || typeof replaces.card_id !== 'string' || !Number.isInteger(replaces.revision) || Object.keys(replaces).length !== 2) {
    errors.push('replaces 必须且只能包含 card_id 和 revision。');
    return null;
  }
  const target = catalog.cards.find(card => card.card_id === replaces.card_id);
  if (!target) errors.push(`要修改的卡牌不存在：${replaces.card_id}。`);
  else if (target.derived_from) errors.push(`衍生卡不能单独修改，请修改来源卡《${target.derived_from.name}》。`);
  else if (target.revision !== replaces.revision) errors.push(`《${target.definition.name}》已经更新到 v${target.revision}，请基于最新版本重新修改。`);
  return target ?? null;
}

function artErrors(artPath) {
  const bytes = readFileSync(artPath), size = pngSize(bytes);
  if (bytes.length > MAX_PNG) return ['卡图超过 2 MiB。'];
  if (!size) return ['卡图必须是 PNG。'];
  if (size.width < 1 || size.height < 1 || size.width > MAX_SIDE || size.height > MAX_SIDE) return ['卡图边长需在 1 至 1024 像素之间。'];
  return [];
}

/** Every check one card must pass, wherever it was submitted from. */
export function checkCard(entry, {catalog, source, artPath = null, skipMedia = false}) {
  const errors = [];
  let compiled;
  try { compiled = compileCard(entry.definition, registry(catalog)); } catch (error) { return {errors: [error.message]}; }
  if (compiled.definition_hash !== entry.definition_hash) errors.push('definition_hash 与卡牌内容不一致，请重新导出。');
  try { requireCardFaction(compiled.definition, Object.fromEntries(catalog.factions.map(item => [item.faction_id, item]))); } catch (error) { errors.push(error.message); }
  errors.push(...basicInfoErrors(compiled.definition, source));
  const target = replacementTarget(entry.replaces, catalog, errors);
  const hasArt = Boolean(artPath && existsSync(artPath));
  if (catalog.cards.some(card => card.definition_hash === compiled.definition_hash && card.card_id !== target?.card_id)) errors.push('卡库里已有完全相同的卡牌。');
  if (target?.definition_hash === compiled.definition_hash && !hasArt) errors.push('这次修改既没有改变卡牌内容，也没有提交新卡面。');
  if (!skipMedia) for (const [kind, id] of mediaIds(compiled.definition)) if (!existsSync(join(DATA, kind, `${id}.bin`))) errors.push(`引用了卡库中不存在的媒体：${id}。`);
  if (hasArt) errors.push(...artErrors(artPath));
  return {errors, compiled, target, artPath: hasArt ? artPath : null};
}

function readJson(path, limit, label) {
  if (statSync(path).size > limit) return {errors: [`${label}超过 ${Math.round(limit / 1024)} KiB。`]};
  try {
    const value = JSON.parse(readFileSync(path, 'utf8'));
    return value && typeof value === 'object' && !Array.isArray(value) ? {value} : {errors: ['文件内容必须是 JSON 对象。']};
  } catch (error) {
    return {errors: [`JSON 无法解析：${error.message}`]};
  }
}

const authorErrors = author => typeof author !== 'string' || !author.trim() || [...author].length > 64 || CONTROL.test(author) ? ['author 需为 1 至 64 个字符。'] : [];

/** Legacy single-card file. Returns {errors, compiled, submission, artPath, target}. */
export function checkSubmission(path, catalog, {skipMedia = false} = {}) {
  const file = basename(path);
  if (!CARD_NAME.test(file)) return {errors: [`文件名必须是 card-<哈希前12位>.card.json，实际是 ${file}。`]};
  const {value: submission, errors: readErrors} = readJson(path, MAX_JSON, '卡牌文件');
  if (readErrors) return {errors: readErrors};
  const errors = [];
  if (submission.format !== SUBMISSION_FORMAT) errors.push(`format 必须是 ${SUBMISSION_FORMAT}。`);
  for (const key of Object.keys(submission)) if (!FIELDS.has(key)) errors.push(`不允许的字段：${key}。`);
  errors.push(...authorErrors(submission.author));
  if (errors.length) return {errors};
  const checked = checkCard(submission, {catalog, source: submission.game_version, artPath: join(dirname(path), file.replace('.card.json', '.png')), skipMedia});
  if (checked.compiled && !file.startsWith(`card-${checked.compiled.definition_hash.slice(0, 12)}.`)) checked.errors.push('文件名中的哈希与卡牌内容不一致。');
  return {...checked, submission};
}

/**
 * A card pack. Returns {errors, pack, cards: [{entry, compiled, target, artPath, label}]}.
 * The pack is all-or-nothing: any error rejects every card in it.
 */
export function checkPack(path, catalog, {skipMedia = false} = {}) {
  const file = basename(path), match = PACK_NAME.exec(file);
  if (!match) return {errors: [`文件名必须是 pack-<哈希前12位>.pack.json，实际是 ${file}。`]};
  const {value: pack, errors: readErrors} = readJson(path, MAX_PACK_JSON, '卡包文件');
  if (readErrors) return {errors: readErrors};
  const errors = [];
  if (pack.format !== PACK_FORMAT) errors.push(`format 必须是 ${PACK_FORMAT}。`);
  for (const key of Object.keys(pack)) if (!PACK_FIELDS.has(key)) errors.push(`不允许的字段：${key}。`);
  errors.push(...authorErrors(pack.author));
  if (typeof pack.name !== 'string' || !pack.name.trim() || [...pack.name].length > 32 || CONTROL.test(pack.name)) errors.push('卡包名称需为 1 至 32 个字符。');
  if (pack.description !== undefined && (typeof pack.description !== 'string' || [...pack.description].length > 300 || /[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/.test(pack.description))) errors.push('卡包简介最多 300 个字符。');
  if (!Array.isArray(pack.cards) || pack.cards.length < 1 || pack.cards.length > MAX_PACK_CARDS) errors.push(`卡包需要包含 1 至 ${MAX_PACK_CARDS} 张卡。`);
  if (errors.length) return {errors, pack};
  for (const [index, entry] of pack.cards.entries()) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) errors.push(`第 ${index + 1} 张卡必须是对象。`);
    else for (const key of Object.keys(entry)) if (!ENTRY_FIELDS.has(key)) errors.push(`第 ${index + 1} 张卡有不允许的字段：${key}。`);
  }
  if (errors.length) return {errors, pack};
  const digest = packHash(pack.cards);
  if (match[1] !== digest.slice(0, 12)) errors.push('文件名中的哈希与卡包内容不一致，请重新导出卡包。');

  const cards = [], names = new Map(), hashes = new Set(), targets = new Set();
  for (const [index, entry] of pack.cards.entries()) {
    const artPath = join(dirname(path), packArtName(digest, String(entry.definition_hash ?? '')));
    const checked = checkCard(entry, {catalog, source: pack.game_version, artPath, skipMedia});
    const name = checked.compiled?.definition.name ?? entry.definition?.name ?? '?';
    const label = `第 ${index + 1} 张《${name}》`;
    errors.push(...checked.errors.map(message => `${label}：${message}`));
    if (!checked.compiled) continue;
    if (hashes.has(checked.compiled.definition_hash)) errors.push(`${label}：卡包里有完全相同的卡。`);
    if (names.has(name)) errors.push(`${label}：与第 ${names.get(name)} 张卡重名。`);
    if (checked.target && targets.has(checked.target.card_id)) errors.push(`${label}：同一张旧牌在卡包里被修改了两次。`);
    hashes.add(checked.compiled.definition_hash);
    names.set(name, index + 1);
    if (checked.target) targets.add(checked.target.card_id);
    cards.push({entry, compiled: checked.compiled, target: checked.target, artPath: checked.artPath, label});
  }
  return {errors, pack, cards, digest};
}

/** PNGs in the inbox that belong to no card of their pack; CI rejects them so nothing slips into the repository unchecked. */
export function strayPackArt(fileNames, checkedPacks) {
  const expected = new Set(checkedPacks.flatMap(({digest, cards}) => (cards ?? []).map(card => packArtName(digest, card.compiled.definition_hash))));
  return fileNames.filter(name => /^pack-[0-9a-f]{12}-[0-9a-f]{12}\.png$/.test(name) && !expected.has(name));
}
