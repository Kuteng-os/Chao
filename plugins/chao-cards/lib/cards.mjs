// Card-design logic behind the DSH tools. It has no DSH dependency, so it can be tested with plain Node.
import {execFile} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {homedir, tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {promisify} from 'node:util';
import {makePrompt, promptSchema} from '../runtime/server/src/provider.js';
import {compileCard, cardPresentation, schemas} from '../runtime/server/src/validation.js';
import {loadCatalog, registry} from '../runtime/tools/library/catalog_io.mjs';
import {checkSubmission, SUBMISSION_FORMAT} from '../runtime/tools/library/submission.mjs';

export const PLUGIN_VERSION = '0.2.0';
const GAME_NAME = /^Frontline[^\\/]*\.exe$/i;
const MIN_GAME_VERSION = '0.9.8';
const TRIAL_TIMEOUT_MS = 60000;
const REPO = 'https://github.com/xiangwu738-design/Chao';
const CATALOG_URL = 'https://raw.githubusercontent.com/xiangwu738-design/Chao/main/data/catalog.json';
const CATALOG_TTL_MS = 300000;
const CATALOG_TIMEOUT_MS = 10000;
const URL_LIMIT = 7000;
const PAGE_CHARS = 24000;
const MAX_CARD_RESULTS = 40;

let cached = null;

/** Prefers the live catalog so new cards count as duplicates; the packaged copy keeps the tools working offline. */
export async function currentCatalog({url = CATALOG_URL, fetchImpl = globalThis.fetch} = {}) {
  if (cached && Date.now() - cached.at < CATALOG_TTL_MS) return cached.catalog;
  let catalog = loadCatalog();
  try {
    const response = await fetchImpl(url, {signal: AbortSignal.timeout(CATALOG_TIMEOUT_MS)});
    if (response.ok) {
      const remote = await response.json();
      if (remote.format === catalog.format && remote.catalog_version >= catalog.catalog_version) catalog = remote;
    }
  } catch {
    // Offline or blocked: the packaged catalog is still a valid baseline.
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
    return {total: found.length, shown: Math.min(found.length, MAX_CARD_RESULTS), cards: found.slice(0, MAX_CARD_RESULTS).map(card => ({name: card.definition.name, kind: card.definition.kind, cost: card.definition.cost, rules_text: card.rules_text}))};
  }
  return {error: 'kind 必须是 keywords、factions 或 cards。'};
}

function errorsOf(error) {
  return error.details?.length ? error.details.map(({path, message}) => ({path: path ?? '', message})) : [{path: '', message: error.message}];
}

function packageFor(compiled, author) {
  return {format: SUBMISSION_FORMAT, game_version: `dsh-plugin-${PLUGIN_VERSION}`, author, definition: compiled.definition, definition_hash: compiled.definition_hash};
}

const fileName = hash => `card-${hash.slice(0, 12)}`;

/** Runs the same checks as the pull-request workflow, so a card that passes here also passes there. */
export async function validateCard(card, options) {
  const catalog = await currentCatalog(options), keywords = registry(catalog);
  let compiled;
  try {
    compiled = compileCard(card, keywords);
  } catch (error) {
    return {ok: false, errors: errorsOf(error)};
  }
  const directory = mkdtempSync(join(tmpdir(), 'chao-card-'));
  try {
    const path = join(directory, `${fileName(compiled.definition_hash)}.card.json`);
    writeFileSync(path, JSON.stringify(packageFor(compiled, '校验')));
    const {errors} = checkSubmission(path, catalog);
    if (errors.length) return {ok: false, errors: errors.map(message => ({path: '', message}))};
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
  const {rules_text} = cardPresentation(compiled.definition, keywords, compiled.compiled_program.expanded_definition);
  return {ok: true, name: compiled.definition.name, rules_text, definition_hash: compiled.definition_hash, compiled};
}

export function defaultOutputDir() {
  return process.env.CHAO_CARDS_OUTPUT || join(homedir(), '巢战卡牌');
}

export async function saveCard(card, author, {outputDir = defaultOutputDir(), ...options} = {}) {
  const trimmed = String(author ?? '').trim();
  if (!trimmed || [...trimmed].length > 64) return {ok: false, errors: [{path: 'author', message: '署名需为 1 至 64 个字符。'}]};
  const checked = await validateCard(card, options);
  if (!checked.ok) return checked;
  mkdirSync(outputDir, {recursive: true});
  const base = fileName(checked.definition_hash), text = JSON.stringify(packageFor(checked.compiled, trimmed));
  const submission = join(outputDir, `${base}.card.json`), preview = join(outputDir, `${base}.preview.json`);
  writeFileSync(submission, text);
  // The game's JSON page accepts a bare CardSpec, which lets players test before submitting.
  writeFileSync(preview, JSON.stringify(checked.compiled.definition, null, 2));
  const url = `${REPO}/new/main/submissions/inbox?filename=${base}.card.json`, filled = `${url}&value=${encodeURIComponent(text)}`;
  const prefilled = filled.length <= URL_LIMIT;
  return {ok: true, name: checked.name, rules_text: checked.rules_text, submission_file: submission, game_preview_file: preview, submit_url: prefilled ? filled : url, prefilled, submit_note: prefilled ? '打开链接后选择 Propose changes，再创建 Pull Request。' : `卡牌内容较长，打开链接后把 ${submission} 的全部内容粘贴进去，再创建 Pull Request。`};
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
