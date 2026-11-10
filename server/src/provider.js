import {freezeReferenceTemplates} from './card_references.js';
import {expandComponents} from './mechanism_components.js';
import {fieldRules, premiseRules, diagnosticRules, mechanics0910} from './rule_capabilities.js';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import {ApiError, strictParse, canonical} from './codec.js';
import {schemas, schemaCheck, docsURL, applyCardBlueprint} from './validation.js';
import {rulesSummary} from './rule_capabilities.js';
import {checkMechanismIntent} from './mechanism_intent.js';
import {compileCard} from './validation.js';

const promptDocument = readFileSync(new URL('COMPILER_PROMPT.md', docsURL), 'utf8');
const templates = [...promptDocument.matchAll(/```text\r?\n([\s\S]*?)\r?\n```/g)].map(m => m[1]);
const compositionRules = readFileSync(new URL("COMPOSITION_0_8_27.md", docsURL), "utf8");
const selectionRules = readFileSync(new URL("RESEARCH_AND_HAND_CHOICES.md",docsURL),"utf8");
const newRules = readFileSync(new URL("DIAGNOSTICS_0_8_33.md",docsURL),"utf8");
const killRules = readFileSync(new URL('DIAGNOSTICS_0_8_37.md',docsURL),'utf8');
const followupRules = readFileSync(new URL('DIAGNOSTICS_0_8_41.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_42.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_43.md',docsURL),'utf8')+'\n'+readFileSync(new URL('CARD_LANGUAGE_0_8_44.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_48.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_50.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_51.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_52.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_54.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_55.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_56.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_57.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_58.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_61.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_62.md',docsURL),'utf8')+'\n'+readFileSync(new URL('DIAGNOSTICS_0_8_63.md',docsURL),'utf8');
const conciseRules = readFileSync(new URL('CONCISE_RULES.md',docsURL),'utf8');
const summary = readFileSync(new URL("DIAGNOSTICS_0_8_31.md",docsURL),"utf8") + "\n" + selectionRules + "\n" + rulesSummary + "\n" + fieldRules + "\n" + premiseRules + "\n" + diagnosticRules + mechanics0910 + "\n" + compositionRules + "\n" + readFileSync(new URL("CUSTOM_STACKS.md",docsURL),"utf8")+"\n"+newRules+"\n"+readFileSync(new URL("DIAGNOSTICS_0_8_34.md",docsURL),"utf8");
// Keep the complete contract while sharing repeated schema fragments in model input.
// Validation still uses the original schemas; local refs retain their original root.
export function promptSchema(schema) {
  const counts=new Map();
  function count(v){if(!v||typeof v!=='object')return;const key=JSON.stringify(v);if((typeof v.type==='string'||Array.isArray(v.oneOf)||Array.isArray(v.anyOf)||Array.isArray(v.enum))&&key.length>60)counts.set(key,(counts.get(key)??0)+1);for(const x of Object.values(v))count(x);}
  count(schema);const shared={},ids=new Map();
  function visit(v,root=false){
    if(!v||typeof v!=='object')return v;
    const key=JSON.stringify(v);
    if(!root&&(counts.get(key)??0)>1){let id=ids.get(key);if(!id){id='p'+ids.size;ids.set(key,id);shared[id]=Object.fromEntries(Object.entries(v).map(([k,x])=>[k,visit(x)]));}return {$ref:'#/$defs/'+id};}
    return Array.isArray(v)?v.map(x=>visit(x)):Object.fromEntries(Object.entries(v).map(([k,x])=>[k,visit(x)]));
  }
  // Short shared references save prompt space without omitting any constraints.
  // Existing #/definitions references keep their original targets.
  const result=visit(schema,true);result.$defs={...result.$defs,...shared};return JSON.stringify(result);
}
export function makePrompt(kind, catalog, blueprint = null) {
  if (kind === 'mechanism-review') {
    const prompt = readFileSync(new URL('MECHANISM_REVIEW_PROMPT.md', docsURL), 'utf8') + '\nMECHANISM_REVIEW_SCHEMA:\n' + JSON.stringify(schemas['mechanism-review']) + '\nRULES_LANGUAGE_SUMMARY:\n' + summary + '\n已登记词条目录:\n' + JSON.stringify(catalog);
    if (Buffer.byteLength(prompt)>200000) throw new ApiError('INPUT_TOO_LONG','词条目录超过支持限制。',413);
    return prompt+'\n'+killRules+'\n'+conciseRules+'\n'+followupRules+'\n当 card_blueprint.effect_mode=replace 时，玩家已明确选择修改现有效果：允许按本次要求替换、修改或删除已有 abilities，不受上面追加模式的已有能力只读约定限制；复述完整修改后的规则，并保留未要求修改的效果。基础属性、已有词条和衍生卡基础配置仍只读；replace 可修改衍生 abilities/play_target，append 可补齐空白衍生效果。';
  }
  const values = {CARD_SCHEMA_JSON: promptSchema(schemas.card), GENERATION_SCHEMA_JSON: JSON.stringify(schemas.generation), KEYWORD_SCHEMA_JSON: promptSchema(schemas.keyword), KEYWORD_GENERATION_SCHEMA_JSON: JSON.stringify(schemas['keyword-generation']), KEYWORD_CATALOG_JSON: JSON.stringify(catalog), RULES_LANGUAGE_SUMMARY: summary};
  let prompt = (kind === 'card' ? templates[0] : templates[1]).replace(/\{\{([A-Z_]+)\}\}/g, (_, key) => values[key] ?? `{{${key}}}`);
  if (/\{\{[A-Z_]+\}\}/.test(prompt) || Buffer.byteLength(prompt) > 200000) throw new ApiError('INVALID_REQUEST', '服务端提示词或词条目录超过支持限制。', 500);
  prompt += '\n'+killRules+'\n'+conciseRules+'\n'+followupRules;
  if (kind !== 'card' || !blueprint) return prompt;
  prompt += '\n卡面描述 display_text 由玩家手写，仅用于展示，不从该字段推断或修改机制，不自动填写或改写它。\n固定衍生卡协议：card_blueprint.tokens 中的单位、指令和反制由服务器原样保留。card.tokens 默认只填写本次新增的模板；已有衍生卡若包含待填的 configurable 词条 abilities:[]，可以返回该模板补齐这些空槽，其余字段必须保持原样。空白衍生指令/反制的abilities:[]可以补齐，play_target也可随之填写；其他基础字段仍只读。没有新增或待补齐时返回 []。引用已有衍生卡时，summon/create_card 使用其准确 token_id，不要为同名卡另建 ID，除补齐空槽或 replace 修改效果外，不回填或改写已有模板。';
  if(blueprint.effect_mode==='replace')return prompt+'\nCARD_BLUEPRINT 明确替换效果模式（effect_mode=replace）：玩家主动选择修改已有能力。返回完整 CardSpec；card.abilities 是替换后的完整能力，不是追加；保留仍需存在的原有效果，仅按需求修改或删除指定效果，不要再自动追加旧能力。可随效果更新 play_target。name、kind、unit_class、cost、operation_cost、attack、health、sin、faction_id、rarity、已有关键词引用和已有 tokens 的基础属性仍只读。已有衍生卡也允许仅替换abilities和play_target，返回原token_id及完整基础字段，其余原样保留。先正式复述变更，确认后生成预览；不要把替换需求报成追加模式冲突。';
  const append = blueprint.effect_mode === 'append' ? '\n追加模式 effect_mode=append：优先于下面旧版去重约定。card.abilities 只能包含本次新加的能力，服务器在服务层恰好追加一次；已有能力不得复制。允许主动追加同触发/同目标/同操作乃至完全相同的效果（例如已有抽2张，再加抽1张）。能力组及组内顺序影响结算，不要合并既有组。play_target 非空时所有登场 chosen 共用该目标；阵亡 chosen 使用各能力组 target，不可改变；tokens 基础配置只读，空白 abilities 可以补齐，新召唤或加入手牌可以增加不重名衍生单位、指令和反制。' : '';
  return prompt + append + '\n\nCARD_BLUEPRINT 协议（当前任务）：玩家已在界面填写基础配置，user 数据的 card_blueprint 是唯一的只读基础配置。kind、unit_class、cost、operation_cost、attack、health、sin（罪孽；未选择为 null 或缺省，不得自动推断）、faction_id（如存在）、rarity（如存在）、counter_trigger（反制）必须原样复制到 card，非空 name 也必须保留。不要询问、重新设计或从 source_text 推断这些已固定字段；名称未指定时可以命名。玩家已选 keywords 必须保留准确 id/version/params，允许从附加要求增加已登记词条，但不能改变或删除已有引用，同 ID 不得重复。模板词条由服务器展开，不要在 abilities 重复复制模板效果。card_blueprint.abilities 若存在，是玩家已组合的固定能力，触发、效果顺序、目标、数量、属性变化及持续时间都不可改变或再次询问。返回 card.abilities 时只填写额外能力，不复制这些固定能力；无需额外能力时填 []，服务器会自动在前面拼接固定能力。不要返回与固定能力具有相同触发/操作/目标的修改版或部分重叠能力，服务器会拒绝冲突；完全相同的完整能力仅去重一次。本牌固定能力、额外能力及词条展开共同计入 8 能力/24 操作预算；每个衍生模板另有8能力/24操作预算，本牌加衍生模板合计96操作，每个能力最多4操作。source_text 只描述附加效果或机制；你的主要职责是理解词条和附加能力，仅对尚未确定的机制、目标、触发时机或技能数值继续澄清。基础攻击、生命、费用与技能 amount/attack_delta/health_delta 是不同字段，不得用基础数值替代技能数值。仍须返回完整 GenerationResult 和完整 CardSpec，不输出局部补丁；此处 card.abilities 作为额外能力的约定仅适用于存在 Blueprint 的任务。';
}
const publicError = (code, message, retryable = false) => new ApiError(code, message, 503, undefined, retryable);
function validationFeedback(error) {
  // Only expose our validation messages, never native exceptions or provider bodies.
  if (!(error instanceof ApiError)) return [{code: 'INVALID_MODEL_OUTPUT', path: '', message: '模型结果结构不完整，请返回符合 Schema 的完整 JSON 对象。'}];
  const details = error.details?.length ? error.details : [{code: error.code, path: '', message: error.message}];
  return details.slice(0, 6).map(detail => ({code: String(detail.code || error.code).slice(0, 64), path: String(detail.path || '').slice(0, 160), message: String(detail.message || error.message).slice(0, 320)}));
}
async function limitedText(response, limit) {
  let size = 0; const chunks = [];
  for await (const chunk of response.body) {
    size += chunk.length; if (size > limit) { await response.body.cancel().catch(() => {}); throw publicError('INVALID_MODEL_OUTPUT', '模型响应超过大小限制。'); }
    chunks.push(chunk);
  }
  try { return new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)); }
  catch { throw publicError('INVALID_MODEL_OUTPUT', '模型响应包含无效 UTF-8。'); }
}
export class DeepSeekProvider {
  constructor(config = {}) {
    this.key = config.apiKey || ''; this.model = config.model || 'deepseek-flash'; this.baseURL = config.baseURL || 'https://api.deepseek.com';
    this.deadlineMs = config.deadlineMs || 240000; this.fetch = config.fetch || globalThis.fetch;
    if (!['https://api.deepseek.com', 'https://api.deepseek.com/v1'].includes(this.baseURL.replace(/\/$/, ''))) throw new Error('Only official DeepSeek HTTPS API endpoints are allowed.');
  }
  get configured() { return Boolean(this.key); }
  async generate({kind, catalog, context, signal, onAttempt}) {
    if (!this.configured) throw publicError('PROVIDER_NOT_CONFIGURED', '尚未配置服务端 DeepSeek API Key；可先手动导入 JSON。');
    const deadline = Date.now() + this.deadlineMs;
    const messages = [{role: 'system', content: makePrompt(kind, catalog, context.card_blueprint)}, {role: 'user', content: canonical(context)}];
    let lastError, waitMs = 0, tokenBudget = 16384;
    for (let attempt = 0; attempt < 2; attempt++) {
      if (signal.aborted) throw publicError('CANCELED', '任务已取消。');
      if (Date.now() + waitMs >= deadline) throw publicError('GENERATION_TIMEOUT', '生成任务超过截止时间。', true);
      if (waitMs) await delay(waitMs, undefined, {signal});
      await onAttempt();
      const attemptSignal = AbortSignal.any([signal, AbortSignal.timeout(Math.min(180000, Math.max(1, deadline - Date.now())))]);
      let response;
      try {
        response = await this.fetch(`${this.baseURL.replace(/\/$/, '')}/chat/completions`, {method: 'POST', redirect: 'error', signal: attemptSignal,
          headers: {'Authorization': `Bearer ${this.key}`, 'Content-Type': 'application/json'},
          body: JSON.stringify({model: this.model, stream: false, thinking: {type: 'enabled'}, reasoning_effort: 'high', max_tokens: tokenBudget, response_format: {type: 'json_object'}, messages})});
      } catch (error) {
        if (signal.aborted) throw publicError('CANCELED', '任务已取消。');
        lastError = publicError(attemptSignal.aborted ? 'GENERATION_TIMEOUT' : 'PROVIDER_UNAVAILABLE', '模型服务暂时不可用；请求可能已计费。', true); waitMs = 350 + Math.floor(Math.random() * 250); continue;
      }
      if (!response.ok) {
        await response.body?.cancel().catch(() => {});
        if (response.status === 401) throw publicError('PROVIDER_AUTH_FAILED', '服务端 DeepSeek 凭据无效。');
        if (response.status === 402) throw publicError('PROVIDER_BALANCE_REQUIRED', 'DeepSeek 账户余额不足。');
        if (response.status === 400 || response.status === 404) throw publicError('MODEL_NOT_AVAILABLE', '配置模型或请求协议不可用，请检查服务端配置。');
        if (response.status === 429 || response.status >= 500) {
          lastError = publicError(response.status === 429 ? 'RATE_LIMITED' : 'PROVIDER_UNAVAILABLE', 'DeepSeek 暂时限流或不可用。', true);
          const retry = response.headers.get('retry-after'); const seconds = Number(retry);
          waitMs = retry ? (Number.isFinite(seconds) ? seconds * 1000 : Math.max(0, Date.parse(retry) - Date.now())) : 500 + Math.floor(Math.random() * 300);
          if (!Number.isFinite(waitMs)) waitMs = 500; continue;
        }
        throw publicError('PROVIDER_UNAVAILABLE', 'DeepSeek 拒绝了请求。');
      }
      let outer, content = '';
      try {
        outer = JSON.parse(await limitedText(response, 1048576));
        const choice = outer.choices?.[0]; content = choice?.message?.content;
        if (choice?.finish_reason !== 'stop' || typeof content !== 'string' || !content.trim()) {
          if(choice?.finish_reason==='length'||typeof content!=='string'||!content.trim())tokenBudget=32768;
          throw publicError('INVALID_MODEL_OUTPUT', '模型输出为空或被截断。');
        }
        const result = strictParse(content, 32768);
        if(kind==='card'&&result.status==='ok'&&result.card){result.card=expandComponents(result.card,context.component_catalog);result.card=freezeReferenceTemplates(result.card,context.card_template_catalog);}
        if (kind === 'card' && context.card_blueprint && result.status === 'ok' && result.card && typeof result.card === 'object' && !Array.isArray(result.card)) result.card = applyCardBlueprint(result.card, context.card_blueprint, {mergeEffects: context.card_blueprint.effect_mode !== 'append'});
        schemaCheck(kind === 'mechanism-review' ? 'mechanism-review' : kind === 'card' ? 'generation' : 'keyword-generation', result);
        if(kind==='card'&&result.status==='ok'&&/压制(?:并|和|与|及)抑制|(?:较|更)[多少].{0,2}方|[多少]的一方/.test(context.source_text??'')){
          const registry=Object.fromEntries(catalog.map(k=>[`${k.definition.id}@${k.definition.version}`,{...k,registry_status:'approved'}]));
          const checked=compileCard(applyCardBlueprint(result.card,context.card_blueprint),registry);
          checkMechanismIntent(context.source_text,checked.compiled_program.expanded_definition);
        }
        return {result, metadata: {thinking: 'enabled', reasoning_effort: 'high', requested_model: this.model, returned_model: typeof outer.model === 'string' ? outer.model : this.model, provider_request_id: typeof outer.id === 'string' ? outer.id : null}};
      } catch (error) {
        if (signal.aborted) throw publicError('CANCELED', '任务已取消。');
        if (['INVALID_KEYWORD_PARAMS', 'BLUEPRINT_ABILITY_CONFLICT'].includes(error.code)) throw error;
        const details = validationFeedback(error), first = details[0];
        const message = error.code === 'BLUEPRINT_TOKEN_CONFLICT' ? error.message : first.message;
        lastError = new ApiError('INVALID_MODEL_OUTPUT', `效果生成未通过校验：${message}${first.path ? `（${first.path}）` : ''} 请重新生成。`, 503, details);
        messages.push({role: 'user', content: JSON.stringify({operation: 'repair_candidate', candidate: typeof content === 'string' && Buffer.byteLength(content) <= 32768 ? content : '', validation_errors: details, instruction: '返回修正后的完整结果，保留玩家所有意图与数值；缺信息继续澄清。' + (kind === 'card' && context.card_blueprint ? '固定衍生卡由服务器原样保留，card.tokens 只返回本次新增模板，没有新增时返回 []；效果使用已有模板的原 token_id。' : '')})}); waitMs = 0;
      }
    }
    throw lastError || publicError('PROVIDER_UNAVAILABLE', '模型服务不可用。', true);
  }
}
