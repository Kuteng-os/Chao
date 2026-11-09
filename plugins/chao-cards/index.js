// DSH plugin entry: exposes the card-design tools and the guiding skill.
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {defineTool} from '@deepseek-ai/dsh-tools';
import {BUNDLED_SKILL_RANK} from '@deepseek-ai/dsh-skill';
import {PLUGIN_VERSION, cardSchema, catalogView, rulesPage, saveCard, trialCard, validateCard} from './lib/cards.mjs';
import {prStatus, reportIssue, submitPr, updatePr} from './lib/github.mjs';

export const name = 'chao-cards';
export const inject = ['tools', 'skills'];

const text = {
  schema: {type: 'string'},
  render: (_args, value) => [{type: 'text', text: value}],
};
const json = value => JSON.stringify(value);
const cardParameter = {type: 'object', required: true, additionalProperties: true, description: '完整的 CardSpec 卡牌定义对象'};

const SKILL_NAME = 'chao-card-maker';
const SKILL_URL = new URL('./skills/chao-card-maker.md', import.meta.url);
const RESOURCE_BASE = {kind: 'directory', path: fileURLToPath(new URL('./skills/', import.meta.url))};
const INVOCATION = {modelInvocable: true, userInvocable: true};
const DESCRIPTION = '为卡牌游戏《巢战》设计新卡牌：理解玩家的描述，追问细节，校验规则，并生成可以提交到 GitHub 的卡牌文件。玩家想做卡、改卡或提交卡牌时使用。';
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
  const card = args.card?.name ?? '这张卡牌';
  if (name === 'chao_submit_pr') return `用你的 GitHub 账号提交卡牌「${card}」并创建 Pull Request`;
  if (name === 'chao_update_pr') return `用你的 GitHub 账号把 PR #${args.pr} 更新为卡牌「${card}」`;
  if (name === 'chao_report_issue' && args.submit) return `用你的 GitHub 账号公开发布 Issue：${args.title}`;
  return null;
}

export function apply(ctx) {
  ctx.skills.registerProvider(() => skillProvider);

  ctx.on('tools/pre-execute', async (exec, next) => {
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
    description: '查询游戏现有内容。kind=keywords 查可用词条，kind=factions 查阵营及 faction_id，kind=cards 查已有卡牌。',
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
    name: 'chao_validate_card',
    description: '用游戏的真实规则校验卡牌，不写入文件。通过时返回玩家可见的规则文本；失败时返回错误路径和原因，修改后再次校验。',
    parameters: {card: cardParameter},
    output: text,
    async execute(args) {
      const {compiled, ...result} = await validateCard(args.card);
      return json(result);
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_trial_card',
    description: '在真实游戏引擎里试玩卡牌，返回每一步的战报和局面，用来确认效果与设想一致。默认按卡牌类型走完打出、推进、攻击、回合触发和阵亡；可用 scenario 调整局面以测试条件效果。',
    parameters: {
      card: cardParameter,
      scenario: {type: 'object', additionalProperties: true, description: '可选：my_units、enemy_units（数组，元素含 name、unit_class、attack、health、row）；credits；actions（play、move、attack、activate、end_turn、enemy_ai、kill 的序列）；target_index、attack_target_index、activate_index；choices（依次回答选择的序号）'},
      game_path: {type: 'string', description: 'Frontline-*.exe 的完整路径，玩家提供一次后会记住'},
    },
    output: text,
    async execute(args) {
      return json(await trialCard(args.card, {scenario: args.scenario ?? {}, gamePath: args.game_path ?? ''}));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_save_card',
    description: '玩家确认卡牌后调用：再次校验并保存到本机，返回提交到 GitHub 的链接和可在游戏 JSON 页试玩的文件路径。',
    parameters: {
      card: cardParameter,
      author: {type: 'string', required: true, description: '玩家的署名，1 至 64 个字符'},
    },
    output: text,
    async execute(args) {
      return json(await saveCard(args.card, args.author));
    },
  }));

  ctx.tools.register(defineTool({
    name: 'chao_submit_pr',
    description: '玩家确认卡牌后，用其本机 GitHub CLI 登录直接创建 Pull Request。调用时会弹出确认框。未安装或未登录 gh 时返回 fallback 和提交链接。',
    parameters: {
      card: cardParameter,
      author: {type: 'string', required: true, description: '玩家的署名，1 至 64 个字符'},
    },
    output: text,
    async execute(args, exec) {
      return json(await submitPr(args.card, args.author, {signal: exec.signal}));
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
    description: '把修改后的卡牌推送到玩家自己的 PR，旧文件会被替换，校验自动重跑。调用时会弹出确认框。',
    parameters: {
      pr: {type: 'number', required: true, description: 'PR 编号'},
      card: cardParameter,
      author: {type: 'string', required: true, description: '玩家的署名，1 至 64 个字符'},
    },
    output: text,
    async execute(args, exec) {
      return json(await updatePr(args.pr, args.card, args.author, {signal: exec.signal}));
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
