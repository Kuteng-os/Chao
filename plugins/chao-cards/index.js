// DSH plugin entry: exposes the card-design tools and the guiding skill.
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {defineTool} from '@deepseek-ai/dsh-tools';
import {BUNDLED_SKILL_RANK} from '@deepseek-ai/dsh-skill';
import {PLUGIN_VERSION, cardSchema, catalogView, getCard, rulesPage, saveCard, trialCard, validateCard} from './lib/cards.mjs';
import {prStatus, reportIssue, submitPr, updatePr} from './lib/github.mjs';
import {bypassReason} from './lib/guard.mjs';
import {approvePr, publishInbox, reviewQueue} from './lib/review.mjs';
import {checkUpdate, installUpdate} from './lib/update.mjs';

export const name = 'chao-cards';
export const inject = ['tools', 'skills'];

const text = {
  schema: {type: 'string'},
  render: (_args, value) => [{type: 'text', text: value}],
};
const json = value => JSON.stringify(value);
const cardParameter = {type: 'object', required: true, additionalProperties: true, description: '完整的 CardSpec 卡牌定义对象'};
const replacesParameter = {type: 'object', additionalProperties: true, description: '修改旧牌时必填：chao_get_card 返回的 replaces 对象，原样传入。做新牌时不要传。'};
const artParameter = {type: 'string', description: '可选：卡面图片在本机的完整路径。必须是 PNG，不超过 2 MiB，边长不超过 1024。'};

const SKILL_NAME = 'chao-card-maker';
const SKILL_URL = new URL('./skills/chao-card-maker.md', import.meta.url);
const RESOURCE_BASE = {kind: 'directory', path: fileURLToPath(new URL('./skills/', import.meta.url))};
const INVOCATION = {modelInvocable: true, userInvocable: true};
const DESCRIPTION = '为卡牌游戏《巢战》设计新卡牌、修改旧牌，校验规则并提交到 GitHub，也可以审核和发布投稿。玩家想做卡、改卡、提交或审核卡牌时使用。';
const CANDIDATE = {name: SKILL_NAME, description: DESCRIPTION, invocation: INVOCATION, provider: 'chao-cards', source: 'bundled', resourceBase: RESOURCE_BASE, rank: BUNDLED_SKILL_RANK, locator: SKILL_URL};

const skillProvider = {
  name: 'chao-cards',
  list: () => Promise.resolve([CANDIDATE]),
  async get() {
    return {name: SKILL_NAME, description: DESCRIPTION, invocation: INVOCATION, provider: 'chao-cards', source: 'bundled', resourceBase: RESOURCE_BASE, content: await readFile(SKILL_URL, 'utf8')};
  },
};

/** Anything published under the player's GitHub account needs their explicit approval. */
function approvalPrompt(name, args) {
  const card = args.card?.name ?? '这张卡牌', extras = `${args.replaces ? '（修改已有卡牌）' : ''}${args.art_path ? `，附带卡面 ${args.art_path}` : ''}`;
  if (name === 'chao_submit_pr') return `用你的 GitHub 账号提交卡牌「${card}」${extras}，并创建 Pull Request`;
  if (name === 'chao_update_pr') return `用你的 GitHub 账号把 PR #${args.pr} 更新为卡牌「${card}」${extras}`;
  if (name === 'chao_approve_pr') return `用你的 GitHub 账号通过并合并 PR #${args.pr}，然后把卡牌发布给所有玩家`;
  if (name === 'chao_plugin_update' && args.install) return '从 GitHub 下载最新版巢战插件并安装，完成后需要重启 DSH Desktop';
  if (name === 'chao_publish_inbox') return '把投稿目录里已合并的卡牌写入卡库，并推送到 main 发布给所有玩家';
  if (name === 'chao_report_issue' && args.submit) return `用你的 GitHub 账号公开发布 Issue：${args.title}`;
  return null;
}

export function apply(ctx) {
  ctx.skills.registerProvider(() => skillProvider);

  // A guard cannot be overridden by another plugin's approval; older DSH builds fall back to the hook below.
  const guarded = typeof ctx.tools.guard === 'function';
  if (guarded) ctx.tools.guard(exec => bypassReason(exec.name, exec.arguments));

  ctx.on('tools/pre-execute', async (exec, next) => {
    const denied = guarded ? undefined : bypassReason(exec.name, exec.arguments);
    if (denied) return {kind: 'deny', reason: denied};
    const prompt = approvalPrompt(exec.name, exec.arguments);
    return prompt ? {kind: 'ask', reason: prompt, displayReason: prompt} : next();
  });

  ctx.tools.register(defineTool({
    name: 'chao_rules',
    description: `读取《巢战》制卡规则指南，按页返回（插件 ${PLUGIN_VERSION}）。写第一张卡前先读第 1 页并按提示读完其余页。`,
    parameters: {page: {type: 'number', description: '页码，从 1 开始，默认 1'}},
    output: text,
    async execute(args) {
      return json(rulesPage(args.page ?? 1));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_card_schema',
    description: '查询卡牌结构。不传 section 返回字段和全部效果名；section=effect:<op> 返回单个效果的结构；section=card、ability、token、premise 等返回对应结构。',
    parameters: {section: {type: 'string', description: '要查询的段，例如 effect:draw'}},
    output: text,
    async execute(args) {
      return json(cardSchema(args.section ?? ''));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_catalog',
    description: '查询游戏现有内容。kind=keywords 查可用词条，kind=factions 查阵营及 faction_id，kind=cards 查已有卡牌及其 card_id。',
    parameters: {
      kind: {type: 'string', required: true, description: 'keywords、factions 或 cards'},
      query: {type: 'string', description: '可选的搜索词'},
    },
    output: text,
    async execute(args) {
      return json(await catalogView(args.kind, args.query ?? ''));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_get_card',
    description: '读取卡库里一张已有卡牌的完整定义，用来修改旧牌。返回的 replaces 必须传给后续的校验、试卡、保存和提交工具。',
    parameters: {
      card_id: {type: 'string', description: '卡牌 id，来自 chao_catalog'},
      name: {type: 'string', description: '卡牌名称，没有 card_id 时使用'},
    },
    output: text,
    async execute(args) {
      return json(await getCard({cardId: args.card_id ?? '', name: args.name ?? ''}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_validate_card',
    description: '用游戏的真实规则校验卡牌，并检查基本信息（稀有度、阵营、罪孽），不写入文件。通过时返回玩家可见的规则文本；失败时返回错误路径和原因，修改后再次校验。',
    parameters: {card: cardParameter, replaces: replacesParameter, art_path: artParameter},
    output: text,
    async execute(args) {
      const {compiled, ...result} = await validateCard(args.card, {replaces: args.replaces, artPath: args.art_path});
      return json(result);
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_trial_card',
    description: '在真实游戏引擎里试玩卡牌，返回每一步的战报和局面，用来确认效果与设想一致。默认按卡牌类型走完打出、推进、攻击、回合触发和阵亡；可用 scenario 调整局面以测试条件效果。',
    parameters: {
      card: cardParameter,
      replaces: replacesParameter,
      scenario: {type: 'object', additionalProperties: true, description: '可选：my_units、enemy_units（数组，元素含 name、unit_class、attack、health、row）；credits；actions（play、move、attack、activate、end_turn、enemy_ai、kill 的序列）；target_index、attack_target_index、activate_index；choices（依次回答选择的序号）'},
      game_path: {type: 'string', description: 'Frontline-*.exe 的完整路径，玩家提供一次后会记住'},
    },
    output: text,
    async execute(args) {
      return json(await trialCard(args.card, {scenario: args.scenario ?? {}, gamePath: args.game_path ?? '', replaces: args.replaces}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_save_card',
    description: '玩家确认卡牌后调用：再次校验并保存到本机，返回提交到 GitHub 的链接和可在游戏 JSON 页试玩的文件路径。',
    parameters: {
      card: cardParameter,
      author: {type: 'string', required: true, description: '玩家的署名，1 至 64 个字符'},
      replaces: replacesParameter,
      art_path: artParameter,
    },
    output: text,
    async execute(args) {
      return json(await saveCard(args.card, args.author, {replaces: args.replaces, artPath: args.art_path}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_submit_pr',
    description: '玩家确认卡牌后，用其本机 GitHub CLI 登录直接创建 Pull Request。工具内部会重新运行程序校验，未通过时不会提交。调用时会弹出确认框。未安装或未登录 gh 时返回 fallback 和提交链接。',
    parameters: {
      card: cardParameter,
      author: {type: 'string', required: true, description: '玩家的署名，1 至 64 个字符'},
      replaces: replacesParameter,
      art_path: artParameter,
    },
    output: text,
    async execute(args, exec) {
      return json(await submitPr(args.card, args.author, {signal: exec.signal, replaces: args.replaces, artPath: args.art_path}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_pr_status',
    description: '查询 PR 的校验结果。validation 为 ok、failed 或 pending；failed 时 details 含错误原因。wait=true 时最多等待两分钟。',
    parameters: {
      pr: {type: 'number', required: true, description: 'PR 编号'},
      wait: {type: 'boolean', description: '是否等待校验完成'},
    },
    output: text,
    async execute(args, exec) {
      return json(await prStatus(args.pr, {wait: args.wait ?? false, signal: exec.signal}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_update_pr',
    description: '把修改后的卡牌推送到玩家自己的 PR，旧文件会被替换，校验自动重跑。工具内部会重新运行程序校验，未通过时不会推送。调用时会弹出确认框。',
    parameters: {
      pr: {type: 'number', required: true, description: 'PR 编号'},
      card: cardParameter,
      author: {type: 'string', required: true, description: '玩家的署名，1 至 64 个字符'},
      replaces: replacesParameter,
      art_path: artParameter,
    },
    output: text,
    async execute(args, exec) {
      return json(await updatePr(args.pr, args.card, args.author, {signal: exec.signal, replaces: args.replaces, artPath: args.art_path}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_review_queue',
    description: '维护者工具：列出待审核的 PR、校验状态和卡牌内容，以及已合并但还没发布的投稿。需要仓库写入权限。',
    parameters: {},
    output: text,
    async execute(_args, exec) {
      return json(await reviewQueue({signal: exec.signal}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_approve_pr',
    description: '维护者工具：通过并合并一个 PR，然后写入卡库并推送给所有玩家。只有最新提交通过程序校验、并且用当前卡库复查仍然通过的 PR 才能合并。调用时会弹出确认框。',
    parameters: {pr: {type: 'number', required: true, description: 'PR 编号'}},
    output: text,
    async execute(args, exec) {
      return json(await approvePr(args.pr, {signal: exec.signal}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_publish_inbox',
    description: '维护者工具：把已合并到投稿目录、还没发布的卡牌写入卡库并推送给所有玩家。校验不通过的卡会跳过。调用时会弹出确认框。',
    parameters: {},
    output: text,
    async execute(_args, exec) {
      return json(await publishInbox({signal: exec.signal}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_plugin_update',
    description: '检查 GitHub 上是否有新版巢战插件；install=true 时下载、校验并用 DSH 安装，会弹出确认框。安装后需要重启 DSH Desktop。',
    parameters: {install: {type: 'boolean', description: '是否立即下载安装，默认只检查'}},
    output: text,
    async execute(args) {
      return json(args.install ? await installUpdate() : await checkUpdate());
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_report_issue',
    description: '反馈校验反复失败或需要游戏尚不支持的新机制。默认只生成预填链接；submit=true 时用玩家的 GitHub CLI 直接发布，并弹出确认框。',
    parameters: {
      title: {type: 'string', required: true, description: '简短标题'},
      details: {type: 'string', required: true, description: '错误原文或所需机制的说明'},
      card_json: {type: 'string', description: '相关卡牌的 JSON 文本'},
      submit: {type: 'boolean', description: '是否直接发布'},
    },
    output: text,
    async execute(args, exec) {
      return json(await reportIssue(args.title, args.details, args.card_json ?? '', {submit: args.submit ?? false, signal: exec.signal}));
    },
  }));
}
