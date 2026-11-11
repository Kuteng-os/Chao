// Card-design logic behind the DSH tools. It has no DSH dependency, so it can be tested with plain Node.
import {execFile} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {homedir, tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {promisify} from 'node:util';
import {makePrompt, promptSchema} from '../runtime/server/src/provider.js';
import {compileCard, cardPresentation, schemas} from '../runtime/server/src/validation.js';
import {loadCatalog, registry} from '../runtime/tools/library/catalog_io.mjs';
import {replacedSummary} from '../runtime/tools/library/accept.mjs';
import {checkPack, checkSubmission, MAX_PACK_CARDS, MAX_PNG, PACK_FORMAT, packArtName, packFileName, packHash, SUBMISSION_FORMAT} from '../runtime/tools/library/submission.mjs';

export const PLUGIN_VERSION = '0.6.0';
const GAME_NAME = /^Frontline[^\\/]*\.exe$/i;
const MIN_GAME_VERSION = '0.10.0';
const TRIAL_TIMEOUT_MS = 60000;
const REPO = 'https://github.com/xiangwu738-design/Chao';
const CATALOG_URLS = ['https://raw.githubusercontent.com/xiangwu738-design/Chao/main/data/catalog.json', 'https://cdn.jsdelivr.net/gh/xiangwu738-design/Chao@main/data/catalog.json'];
const CATALOG_TTL_MS = 300000;
const CATALOG_TIMEOUT_MS = 10000;
const URL_LIMIT = 7000;
const PAGE_CHARS = 24000;
const MAX_CARD_RESULTS = 40;

let cached = null;

/** Prefers the live catalog so new cards count as duplicates; the packaged copy keeps the tools working offline. */
export async function currentCatalog({urls = CATALOG_URLS, fetchImpl = globalThis.fetch} = {}) {
  if (cached && Date.now() - cached.at < CATALOG_TTL_MS) return cached.catalog;
  let catalog = loadCatalog();
  for (const url of urls) {
    try {
      const response = await fetchImpl(url, {signal: AbortSignal.timeout(CATALOG_TIMEOUT_MS)});
      if (!response.ok) continue;
      const remote = await response.json();
      if (remote.format === catalog.format && remote.catalog_version >= catalog.catalog_version) catalog = remote;
      break;
    } catch {
      // Try the next source; the packaged catalog remains a valid baseline.
    }
  }
  cached = {at: Date.now(), catalog};
  return catalog;
}

export function resetCatalogCache() {
  cached = null;
}

let guide = null;

function guideText() {
  if (guide !== null) return guide;
  guide = makePrompt('card', '@@CATALOG@@', null)
    .replace(promptSchema(schemas.card), '（卡牌结构请用 chao_card_schema 工具按需查询）')
    .replace(JSON.stringify(schemas.generation), '（本插件不使用 GenerationResult，直接把 CardSpec 交给 chao_validate_card）')
    .replace('"@@CATALOG@@"', '（词条目录请用 chao_catalog 工具查询）');
  return guide;
}

/** Splits the rule guide on line breaks so each page stays below typical tool-output caps. */
function guidePages() {
  const pages = [];
  let current = '';
  for (const line of guideText().split('\n')) {
    if (current.length + line.length + 1 > PAGE_CHARS && current) {
      pages.push(current);
      current = '';
    }
    current += `${line}\n`;
  }
  if (current) pages.push(current);
  return pages;
}

export function rulesPage(page = 1) {
  const pages = guidePages();
  if (!Number.isInteger(page) || page < 1 || page > pages.length) return {error: `page 需在 1 至 ${pages.length} 之间。`, total_pages: pages.length};
  return {page, total_pages: pages.length, text: pages[page - 1]};
}

const effects = () => schemas.card.definitions.effect.oneOf;
const opOf = entry => entry?.properties?.op?.const;

export function cardSchema(section = '') {
  const {properties, required, definitions} = schemas.card;
  if (!section) return {card_fields: Object.keys(properties), required, sections: [...Object.keys(definitions).filter(name => name !== 'effect'), 'card'], effect_ops: effects().map(opOf), usage: '传 section=effect:<op> 查询单个效果，传 section=card 或上面的段名查询结构。'};
  if (section === 'card') return {schema: JSON.parse(promptSchema({type: 'object', properties: Object.fromEntries(Object.entries(properties).filter(([key]) => !['abilities', 'tokens'].includes(key))), required})), note: 'abilities 见 section=ability，tokens 见 section=token。'};
  if (section.startsWith('effect:')) {
    const op = section.slice('effect:'.length), entry = effects().find(item => opOf(item) === op);
    return entry ? {schema: JSON.parse(promptSchema(entry))} : {error: `未知效果 ${op}。`, effect_ops: effects().map(opOf)};
  }
  if (section === 'effect') return {effect_ops: effects().map(opOf), usage: '传 section=effect:<op> 查询单个效果。'};
  return definitions[section] ? {schema: JSON.parse(promptSchema(definitions[section]))} : {error: `未知段 ${section}。`, sections: Object.keys(definitions)};
}

export async function catalogView(kind, query = '', options) {
  const catalog = await currentCatalog(options), needle = query.trim().toLocaleLowerCase();
  const matches = text => !needle || String(text).toLocaleLowerCase().includes(needle);
  if (kind === 'keywords') {
    return catalog.keywords.filter(entry => !entry.archived && matches(`${entry.definition.name}${entry.definition.id}${entry.definition.description}`)).map(({definition}) => ({id: definition.id, version: definition.version, name: definition.name, description: definition.description, parameters: definition.parameters, implementation: definition.implementation.kind}));
  }
  if (kind === 'factions') return catalog.factions.filter(entry => !entry.archived && matches(entry.name)).map(entry => ({faction_id: entry.faction_id, name: entry.name, category: entry.category}));
  if (kind === 'cards') {
    const found = catalog.cards.filter(card => !card.archived && matches(`${card.definition.name}${card.rules_text}`));
    return {total: found.length, shown: Math.min(found.length, MAX_CARD_RESULTS), cards: found.slice(0, MAX_CARD_RESULTS).map(card => ({card_id: card.card_id, revision: card.revision, name: card.definition.name, kind: card.definition.kind, cost: card.definition.cost, author: card.author?.name ?? '', derived: Boolean(card.derived_from), rules_text: card.rules_text}))};
  }
  return {error: 'kind 必须是 keywords、factions 或 cards。'};
}

function missingBasicInfo(definition) {
  return [['rarity', '稀有度'], ['faction_id', '阵营'], ['sin', '罪孽']].filter(([key]) => !Object.hasOwn(definition, key) || (key !== 'sin' && !definition[key])).map(([key, label]) => ({field: key, label}));
}

/** Loads an existing card for revision. The returned replaces object must accompany every later call for this card. */
export async function getCard({cardId = '', name = ''} = {}, options) {
  const catalog = await currentCatalog(options), wanted = name.trim().toLocaleLowerCase();
  if (!cardId && !wanted) return {ok: false, errors: [{path: 'card_id', message: '需要 card_id 或 name。'}]};
  let found = catalog.cards.filter(card => cardId ? card.card_id === cardId : card.definition.name.toLocaleLowerCase().includes(wanted));
  const exact = found.filter(card => card.definition.name.toLocaleLowerCase() === wanted);
  if (exact.length === 1) found = exact;
  if (!found.length) return {ok: false, errors: [{path: 'card_id', message: '卡库里没有找到这张牌。'}]};
  if (found.length > 1) return {ok: false, need_choice: true, message: '匹配到多张牌，请让玩家选择后用 card_id 查询。', matches: found.slice(0, MAX_CARD_RESULTS).map(card => ({card_id: card.card_id, name: card.definition.name, author: card.author?.name ?? '', rules_text: card.rules_text}))};
  const card = found[0];
  if (card.derived_from) return {ok: false, errors: [{path: 'card_id', message: `衍生卡不能单独修改，请修改来源卡《${card.derived_from.name}》（${card.derived_from.card_id}）。`}]};
  return {ok: true, card_id: card.card_id, revision: card.revision, replaces: {card_id: card.card_id, revision: card.revision}, card: card.definition, rules_text: card.rules_text, author: card.author?.name ?? '', series: card.series, archived: Boolean(card.archived), has_art: Boolean(card.art), missing_basic_info: missingBasicInfo(card.definition)};
}

function errorsOf(error) {
  return error.details?.length ? error.details.map(({path, message}) => ({path: path ?? '', message})) : [{path: '', message: error.message}];
}

function packageFor(compiled, author, replaces) {
  return {format: SUBMISSION_FORMAT, game_version: `dsh-plugin-${PLUGIN_VERSION}`, author, definition: compiled.definition, definition_hash: compiled.definition_hash, ...(replaces ? {replaces} : {})};
}

function artProblem(path) {
  try {
    if (!statSync(path).isFile()) return `卡面不是文件：${path}`;
    return statSync(path).size > MAX_PNG ? '卡面超过 2 MiB。' : '';
  } catch {
    return `找不到卡面文件：${path}`;
  }
}

const fileName = hash => `card-${hash.slice(0, 12)}`;

/** Runs the same checks as the pull-request workflow, so a card that passes here also passes there. */
export async function validateCard(card, {replaces, artPath, ...options} = {}) {
  const catalog = await currentCatalog(options), keywords = registry(catalog);
  if (artPath) {
    const problem = artProblem(artPath);
    if (problem) return {ok: false, errors: [{path: 'art_path', message: problem}]};
  }
  let compiled;
  try {
    compiled = compileCard(card, keywords);
  } catch (error) {
    return {ok: false, errors: errorsOf(error)};
  }
  const directory = mkdtempSync(join(tmpdir(), 'chao-card-'));
  let target;
  try {
    const base = fileName(compiled.definition_hash), path = join(directory, `${base}.card.json`);
    writeFileSync(path, JSON.stringify(packageFor(compiled, '校验', replaces)));
    if (artPath) copyFileSync(artPath, join(directory, `${base}.png`));
    const result = checkSubmission(path, catalog, {skipMedia: true});
    if (result.errors.length) return {ok: false, errors: result.errors.map(message => ({path: '', message}))};
    target = result.target;
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
  const {rules_text} = cardPresentation(compiled.definition, keywords, compiled.compiled_program.expanded_definition);
  return {ok: true, name: compiled.definition.name, rules_text, definition_hash: compiled.definition_hash, has_art: Boolean(artPath), replaced: replacedSummary(target), compiled};
}

export function defaultOutputDir() {
  return process.env.CHAO_CARDS_OUTPUT || join(homedir(), '巢战卡牌');
}

const packError = (path, message) => ({ok: false, errors: [{path, message}]});

/**
 * Validates every card and then the pack as a whole, with the same checker CI runs, so a pack that passes here passes there.
 * spec: {name, description?, author, cards: [{card, replaces?, art_path?}]}
 */
export async function buildPack(spec, options = {}) {
  const author = String(spec?.author ?? '').trim(), name = String(spec?.name ?? '').trim(), description = String(spec?.description ?? '').trim();
  if (!author || [...author].length > 64) return packError('author', '署名需为 1 至 64 个字符。');
  if (!name || [...name].length > 32) return packError('name', '卡包名称需为 1 至 32 个字符。');
  if ([...description].length > 300) return packError('description', '卡包简介最多 300 个字符。');
  const items = Array.isArray(spec?.cards) ? spec.cards : [];
  if (!items.length || items.length > MAX_PACK_CARDS) return packError('cards', `卡包需要包含 1 至 ${MAX_PACK_CARDS} 张卡。`);
  const errors = [], checked = [];
  for (const [index, item] of items.entries()) {
    const result = await validateCard(item?.card, {replaces: item?.replaces, artPath: item?.art_path, ...options});
    if (!result.ok) errors.push(...result.errors.map(error => ({path: `cards/${index}${error.path ? '/' + error.path : ''}`, message: `第 ${index + 1} 张：${error.message}`})));
    else checked.push({...result, replaces: item.replaces, art_path: item.art_path});
  }
  if (errors.length) return {ok: false, errors};
  const entries = checked.map(card => ({definition: card.compiled.definition, definition_hash: card.definition_hash, ...(card.replaces ? {replaces: card.replaces} : {})}));
  const pack = {format: PACK_FORMAT, game_version: `dsh-plugin-${PLUGIN_VERSION}`, author, name, ...(description ? {description} : {}), cards: entries};
  const digest = packHash(entries);
  const catalog = await currentCatalog(options);
  const directory = mkdtempSync(join(tmpdir(), 'chao-pack-'));
  try {
    const path = join(directory, packFileName(digest));
    writeFileSync(path, JSON.stringify(pack));
    for (const card of checked) if (card.art_path) copyFileSync(card.art_path, join(directory, packArtName(digest, card.definition_hash)));
    const result = checkPack(path, catalog, {skipMedia: true});
    if (result.errors.length) return {ok: false, errors: result.errors.map(message => ({path: '', message}))};
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
  const summary = checked.map(card => ({name: card.name, rules_text: card.rules_text, has_art: Boolean(card.art_path), ...(card.replaced ? {replaced: card.replaced} : {})}));
  return {ok: true, pack, digest, checked, cards: summary};
}

/** Writes the pack and its art into one folder that can be uploaded to GitHub as-is, or imported into the game. */
export async function savePack(spec, {outputDir = defaultOutputDir(), ...options} = {}) {
  const built = await buildPack(spec, options);
  if (!built.ok) return built;
  const folder = join(outputDir, 'packs', packFileName(built.digest).replace('.pack.json', ''));
  rmSync(folder, {recursive: true, force: true});
  mkdirSync(folder, {recursive: true});
  const packFile = join(folder, packFileName(built.digest));
  writeFileSync(packFile, JSON.stringify(built.pack));
  const artFiles = [];
  for (const card of built.checked) {
    if (!card.art_path) continue;
    const target = join(folder, packArtName(built.digest, card.definition_hash));
    copyFileSync(card.art_path, target);
    artFiles.push(target);
  }
  return {ok: true, name: built.pack.name, card_count: built.pack.cards.length, cards: built.cards, folder, pack_file: packFile, art_files: artFiles, upload_url: `${REPO}/upload/main/submissions/inbox`, submit_note: `打开 upload_url，把 ${folder} 里的全部文件拖进网页，选择 Propose changes，再创建 Pull Request。`, game_import_note: `在游戏“创作工坊 → 导入卡包”选择 ${packFile}，可以把整包导入本地卡库，组牌试玩。`, pack: built.pack, digest: built.digest, checked: built.checked};
}

export function issueLink(title, details, card = '') {
  const base = `${REPO}/issues/new?template=bug.yml&title=${encodeURIComponent(`[报错] ${title}`)}&version=${encodeURIComponent(`dsh-plugin-${PLUGIN_VERSION}`)}&details=${encodeURIComponent(details)}`;
  const withCard = card ? `${base}&card=${encodeURIComponent(card)}` : base;
  return withCard.length <= URL_LIMIT ? {url: withCard, card_included: Boolean(card)} : {url: base, card_included: false, note: '卡牌 JSON 较长，请手动粘贴到 Issue 的卡牌栏。'};
}

function configPath(outputDir) {
  return join(outputDir, 'config.json');
}

function rememberedGame(outputDir) {
  try {
    return JSON.parse(readFileSync(configPath(outputDir), 'utf8')).game_path ?? '';
  } catch {
    return '';
  }
}

const needGame = message => ({ok: false, need_game_path: true, message});

/** Plays the card in the real game engine. Only runs an existing Frontline*.exe, never an arbitrary program. */
export async function trialCard(card, {scenario = {}, gamePath = '', outputDir = defaultOutputDir(), timeoutMs = TRIAL_TIMEOUT_MS, ...options} = {}) {
  const exe = gamePath || process.env.CHAO_GAME_EXE || rememberedGame(outputDir);
  if (!exe) return needGame(`请提供 ${MIN_GAME_VERSION} 或更新版本 Frontline-*.exe 的完整路径，只需提供一次。`);
  if (!GAME_NAME.test(basename(exe)) || !existsSync(exe)) return needGame(`找不到游戏程序：${exe}。需要 Frontline-*.exe 的完整路径。`);
  const checked = await validateCard(card, options);
  if (!checked.ok) return checked;
  if (gamePath) {
    mkdirSync(outputDir, {recursive: true});
    writeFileSync(configPath(outputDir), JSON.stringify({game_path: gamePath}));
  }
  const catalog = await currentCatalog(options);
  const directory = mkdtempSync(join(tmpdir(), 'chao-trial-'));
  try {
    const job = join(directory, 'job.json'), report = join(directory, 'report.json');
    writeFileSync(job, JSON.stringify({card: checked.compiled.definition, keywords: catalog.keywords.map(entry => entry.definition), scenario}));
    try {
      await promisify(execFile)(exe, ['--headless', '--', `--card-trial=${job}`, `--card-trial-out=${report}`], {timeout: timeoutMs, windowsHide: true});
    } catch (error) {
      if (!existsSync(report)) return {ok: false, error: `游戏没有返回试卡结果，可能版本低于 ${MIN_GAME_VERSION}：${error.message.slice(0, 200)}`};
    }
    if (!existsSync(report)) return {ok: false, error: `游戏没有返回试卡结果，可能版本低于 ${MIN_GAME_VERSION}。`};
    return JSON.parse(readFileSync(report, 'utf8'));
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
}
