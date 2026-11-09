// Checks one player submission as data only; nothing from the file is ever executed.
import {readFileSync, existsSync, statSync} from 'node:fs';
import {basename, dirname, join} from 'node:path';
import {compileCard} from '../../server/src/validation.js';
import {requireCardFaction} from '../../server/src/factions.js';
import {DATA, registry} from './catalog_io.mjs';

export const SUBMISSION_FORMAT = 'chao-card-submission-v1';
const NAME = /^card-[0-9a-f]{12}\.card\.json$/;
export const MAX_PNG = 2 * 1024 * 1024;
const MAX_JSON = 65536, MAX_SIDE = 1024;
const FIELDS = new Set(['format', 'game_version', 'author', 'definition', 'definition_hash', 'replaces']);

export function pngSize(bytes) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(signature) || bytes.toString('latin1', 12, 16) !== 'IHDR') return null;
  return {width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20)};
}

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

/**
 * Returns {errors, compiled, submission, artPath, target}; an empty errors array means it can be accepted.
 * skipMedia is for callers without the repository's media directory, which CI still checks.
 */
export function checkSubmission(path, catalog, {skipMedia = false} = {}) {
  const errors = [], file = basename(path);
  if (!NAME.test(file)) return {errors: [`文件名必须是 card-<哈希前12位>.card.json，实际是 ${file}。`]};
  if (statSync(path).size > MAX_JSON) return {errors: ['卡牌文件超过 64 KiB。']};
  let submission;
  try { submission = JSON.parse(readFileSync(path, 'utf8')); } catch (error) { return {errors: [`JSON 无法解析：${error.message}`]}; }
  if (!submission || typeof submission !== 'object' || Array.isArray(submission)) return {errors: ['文件内容必须是 JSON 对象。']};
  if (submission.format !== SUBMISSION_FORMAT) errors.push(`format 必须是 ${SUBMISSION_FORMAT}。`);
  for (const key of Object.keys(submission)) if (!FIELDS.has(key)) errors.push(`不允许的字段：${key}。`);
  if (typeof submission.author !== 'string' || !submission.author.trim() || [...submission.author].length > 64) errors.push('author 需为 1 至 64 个字符。');
  if (errors.length) return {errors};
  let compiled;
  try { compiled = compileCard(submission.definition, registry(catalog)); } catch (error) { return {errors: [error.message]}; }
  if (compiled.definition_hash !== submission.definition_hash) errors.push('definition_hash 与卡牌内容不一致，请在游戏里重新提交。');
  if (!file.startsWith(`card-${compiled.definition_hash.slice(0, 12)}.`)) errors.push('文件名中的哈希与卡牌内容不一致。');
  try { requireCardFaction(compiled.definition, Object.fromEntries(catalog.factions.map(entry => [entry.faction_id, entry]))); } catch (error) { errors.push(error.message); }
  errors.push(...basicInfoErrors(compiled.definition, submission.game_version));
  const target = replacementTarget(submission.replaces, catalog, errors);
  const artPath = join(dirname(path), file.replace('.card.json', '.png'));
  if (catalog.cards.some(card => card.definition_hash === compiled.definition_hash && card.card_id !== target?.card_id)) errors.push('卡库里已有完全相同的卡牌。');
  if (target?.definition_hash === compiled.definition_hash && !existsSync(artPath)) errors.push('这次修改既没有改变卡牌内容，也没有提交新卡面。');
  if (!skipMedia) for (const [kind, id] of mediaIds(compiled.definition)) if (!existsSync(join(DATA, kind, `${id}.bin`))) errors.push(`引用了卡库中不存在的媒体：${id}。`);
  if (existsSync(artPath)) {
    const bytes = readFileSync(artPath), size = pngSize(bytes);
    if (bytes.length > MAX_PNG) errors.push('卡图超过 2 MiB。');
    if (!size) errors.push('卡图必须是 PNG。');
    else if (size.width < 1 || size.height < 1 || size.width > MAX_SIDE || size.height > MAX_SIDE) errors.push('卡图边长需在 1 至 1024 像素之间。');
  }
  return {errors, compiled, submission, artPath: existsSync(artPath) ? artPath : null, target};
}
