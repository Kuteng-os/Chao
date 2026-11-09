import {cardSeries,currentCardSeries,seriesCatalog,requireSeries} from './card_series.js';
import {referenceTemplates} from './card_references.js';
import {latestCards,resolveCard} from './derived_cards.js';
import {collectJobDiagnostic} from './diagnostics.js';
import {registerComponents,componentCatalog,expandComponents} from './mechanism_components.js';
import {validateMedia} from './card_media.js';
import {archived,lifecycleSnapshot,assertKeywordAvailable} from './content_lifecycle.js';
import {randomUUID} from 'node:crypto';
import {selectArt,selectTokenArt} from './card_art.js';
import {requireCardFaction} from './factions.js';
import {ApiError, fail, hash, canonical, normalize} from './codec.js';
import {compileCard, validateKeyword, registryEntries, registryHash, checkExplicitNumbers, checkEffectAmounts, extractExplicitCardConstraints, validateCardBlueprint, applyCardBlueprint} from './validation.js';
import {checkMechanismIntent} from './mechanism_intent.js';

import {createReview, consumeReview, reviewResult} from './mechanism_reviews.js';
import {schemaCheck} from './validation.js';
import {authorFor} from './authorship.js';
import {isAdmin,audit} from './account_roles.js';

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const hashPattern = /^[0-9a-f]{64}$/;
const terminal = new Set(['ready', 'unsupported', 'failed', 'canceled']);
const clone = x => structuredClone(x);
export function fields(body, required, optional = []) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) fail('INVALID_REQUEST', '请求必须为 JSON 对象。', 400);
  const allowed = new Set([...required, ...optional]);
  if (required.some(k => !Object.hasOwn(body, k)) || Object.keys(body).some(k => !allowed.has(k))) fail('INVALID_REQUEST', '请求缺少必填字段或包含未知字段。', 400);
}
const uuid = value => { if (typeof value !== 'string' || !uuidPattern.test(value)) fail('INVALID_REQUEST', 'ID 必须为小写 UUID。', 400); };
const integer = value => { if (!Number.isSafeInteger(value) || value < 1) fail('INVALID_REQUEST', '修订必须为正整数。', 400); };
const text = (value, max = 2000, min = 1) => { if (typeof value !== 'string' || [...value].length < min || [...value].length > max) fail('INPUT_TOO_LONG', `文本长度必须为 ${min} 至 ${max} 个字符。`, 400); };
const digest = value => { if (typeof value !== 'string' || !hashPattern.test(value)) fail('INVALID_REQUEST', '哈希格式无效。', 400); };
const owned = (item, owner) => { if (!item || item.owner_id !== owner) fail('NOT_FOUND', '未找到此对象。', 404); return item; };
function answersCheck(answers, questions, minimum = 0) {
  if (!Array.isArray(answers) || answers.length < minimum || answers.length > 3) fail('INVALID_REQUEST', '每轮最多回答三个问题。', 400);
  const used = new Set();
  return answers.map(a => {
    fields(a, ['question_id', 'answer']); text(a.answer, 500);
    const question = questions.find(q => q.id === a.question_id);
    if (!question || used.has(a.question_id)) fail('INVALID_REQUEST', '问题不属于当前任务或重复回答。', 400);
    used.add(a.question_id); return {question_id: a.question_id, question: question.question, answer: a.answer};
  });
}
const publicJob = job => Object.fromEntries(['diagnostic_id', 'diagnostic_number', 'generation_id', 'conversation_id', 'round', 'status', 'editor_revision', 'result', 'error', 'resumed_generation_id','history','source_text','kind','target_kind'].filter(k => Object.hasOwn(job, k)).map(k => [k, clone(job[k])]));
const publicProposal = proposal => Object.fromEntries(['proposal_id', 'revision', 'status', 'assigned_id', 'assigned_version', 'confirmed_intent', 'questions', 'candidate', 'candidate_hash', 'missing_capabilities', 'review_message', 'generation_job_id', 'resumed_generation_id','history','source_text','kind','target_kind'].filter(k => Object.hasOwn(proposal, k)).map(k => [k, clone(proposal[k])]));
function safeError(error) { return error instanceof ApiError ? {code: error.code, message: error.message, retryable: error.retryable, ...(error.details ? {details: error.details} : {})} : {code: 'INTERNAL_ERROR', message: '服务内部操作失败，请重试。', retryable: true}; }

export class CardService {
  constructor(store, provider, config = {}) { this.store = store; this.provider = provider; this.controllers = new Map(); this.pending = new Set(); this.minuteLimit = config.minuteLimit || 5; this.dailyLimit = Number(config.dailyLimit ?? process.env.MODEL_DAILY_LIMIT ?? 500); if(!Number.isInteger(this.dailyLimit)||this.dailyLimit<1||this.dailyLimit>10000)throw new Error("Invalid MODEL_DAILY_LIMIT"); this.requireFactions=Boolean(config.requireFactions); }
  health() { return {ok: true, model: this.provider.model, configured: this.provider.configured, keyword_count: registryEntries(this.store.state.keywords).length, card_count: Object.keys(this.store.state.cards).length,card_series:seriesCatalog(this.store.state)}; }
  keywords(versionHash, owner = null) {
    if (versionHash) digest(versionHash);
    const state = this.store.state, current = registryHash(state.keywords);
    const entries = versionHash ? state.catalogs[versionHash] : registryEntries(state.keywords);
    if (!entries) fail('NOT_FOUND', '未找到此冻结词条目录。', 404);
    return {keyword_registry_hash: versionHash || current, definitions: entries.map(e => ({definition_hash: e.definition_hash, definition: clone(e.definition), archived: archived(state,"keywords",e.definition.id), can_manage: Boolean(owner && (e.owner_id===owner||isAdmin(state,owner))), owned_by_me: Boolean(owner && e.owner_id === owner), can_edit: e.definition.implementation.kind!=='builtin' && Boolean(owner && (e.owner_id === owner || isAdmin(state,owner)))}))};
  }
  cards(owner) { return {card_series:seriesCatalog(this.store.state),lifecycle:lifecycleSnapshot(this.store.state), cards: latestCards(this.store.state).filter(record=>record.owner_id===owner).map(clone)}; }
  card(owner, id, revision) { const record=resolveCard(this.store.state,id,revision??null);if(!record||record.owner_id!==owner)fail('NOT_FOUND','未找到此卡牌。',404);return clone(record); }
  job(owner, id) { const job=owned(this.store.state.generations[id],owner); const report=Object.values(this.store.state.diagnostics??{}).find(r=>r.generation_id===id); return {...publicJob(job),...(report?{diagnostic_number:report.number}: {})}; }
  proposal(owner, id) { return publicProposal(owned(this.store.state.proposals[id], owner)); }
  async idem(owner, route, body, operation) {
    uuid(body.request_id); const signature = hash({route, body});
    return this.store.transaction(state => {
      const key = `${owner}:${body.request_id}`, existing = state.idempotency[key];
      if (existing) { if (existing.signature !== signature) fail('IDEMPOTENCY_CONFLICT', '该请求 ID 已用于不同内容。', 409); return existing.response; }
      const response = operation(state); state.idempotency[key] = {signature, response}; return response;
    });
  }
  draft(state, owner, definition, options = {}) {
    const compiled = compileCard(expandComponents(definition,state.mechanism_components), state.keywords);
    validateMedia(state,owner,compiled.definition);
    if (this.requireFactions || compiled.definition.faction_id) requireCardFaction(compiled.definition,state.factions);
    const draft = {draft_id: randomUUID(), draft_hash: compiled.definition_hash, definition: compiled.definition, keyword_bindings: compiled.keyword_bindings, compiled_program_hash: compiled.compiled_program_hash, compiled_program: compiled.compiled_program, rules_text: compiled.short_rules_text??compiled.rules_text, detailed_text: compiled.detailed_text, keyword_names: compiled.keyword_names, assumptions: options.assumptions || [], warnings: [{code: 'CUSTOM_RULES', message: '自定义牌通过规则校验，尚无竞技平衡保证。'}, {code: 'IDENTITY', message: '确认后将创建新的卡牌身份；修订接口则保留原身份。'}], expires_at: new Date(Date.now() + 86400000).toISOString()};
    state.drafts[draft.draft_id] = {...draft, owner_id: owner, provenance: options.provenance || {source_kind: 'json_import'}, canonical_definition: compiled.canonical_definition, generation_id: options.generation_id || null, imported_card: null};
    return draft;
  }
  async manualDraft(owner, body, isPackage = false) {
    fields(body, isPackage ? ['request_id', 'package'] : ['request_id', 'definition'], isPackage ? [] : ['editor_revision']);
    if (body.editor_revision !== undefined) integer(body.editor_revision);
    if (isPackage) { fields(body.package, ['package_version', 'definition'], ['definition_hash', 'keyword_bindings']); if (body.package.package_version !== '1') fail('VERSION_MISMATCH', '不支持此导入包版本。'); if (Buffer.byteLength(canonical(body.package)) > 32768) fail('INPUT_TOO_LONG', '导入包超过 32 KiB。', 413); }
    return this.idem(owner, isPackage ? 'card-import' : 'card-draft', body, state => {
      const result = this.draft(state, owner, isPackage ? body.package.definition : body.definition);
      if (isPackage) {
        if (body.package.definition_hash !== undefined && body.package.definition_hash !== result.draft_hash) fail('HASH_MISMATCH', '卡牌定义哈希不匹配。');
        if (body.package.keyword_bindings !== undefined && canonical(body.package.keyword_bindings) !== canonical(result.keyword_bindings)) fail('HASH_MISMATCH', '词条绑定与已登记定义不匹配。');
      }
      return {status: 'ready', result};
    });
  }
  async confirmCard(owner, body, cardId) {
    fields(body, ['request_id', 'draft_id', 'draft_hash', ...(cardId ? ['base_revision'] : [])], ['art_id','token_art_ids','series','expected_series']); uuid(body.draft_id); digest(body.draft_hash); if (cardId) integer(body.base_revision);
    return this.idem(owner, `confirm-card:${cardId || 'new'}`, body, state => {
      const draft = owned(state.drafts[body.draft_id], owner);
      if (draft.draft_hash !== body.draft_hash) fail('STALE_DRAFT', '草稿内容已变化，请重新预览。', 409);
      if (draft.imported_card) {
        const imported = draft.imported_card;
        if ((cardId && imported.card_id !== cardId) || (!cardId && imported.revision !== 1)) fail('REVISION_CONFLICT', '草稿已经用于另一修订操作。', 409);
        const previous = state.cards[imported.card_id]?.find(c => c.revision === imported.revision);
        if(!previous)fail("CONTENT_DELETED","此卡牌已彻底删除，请重新创建草稿。",410);
        return {...previous,author:authorFor(state,previous.owner_id)};
      }
      if (Date.parse(draft.expires_at) <= Date.now()) fail('STALE_DRAFT', '草稿已过期，请重新生成预览。', 410);
      if (draft.generation_id && ['canceled', 'superseded'].includes(state.generations[draft.generation_id]?.status)) fail('STALE_DRAFT', '该草稿已取消或被后续修订替代。', 409);
      let versions = [];
      if (cardId) { versions = state.cards[cardId]; if (!versions || (versions[0].owner_id !== owner && !isAdmin(state,owner))) fail('NOT_FOUND', '未找到此卡牌。', 404); if (versions.at(-1).revision !== body.base_revision) fail('REVISION_CONFLICT', '卡牌已产生新修订，请重新加载。', 409); }
      const compiled = compileCard(draft.definition, state.keywords);
      validateMedia(state,owner,compiled.definition);
      if (this.requireFactions || compiled.definition.faction_id) requireCardFaction(compiled.definition,state.factions);
      if (compiled.compiled_program_hash !== draft.compiled_program_hash) fail('HASH_MISMATCH', '预览依赖发生变化。');
      const series=body.series===undefined?(versions.length?cardSeries(versions[0]):currentCardSeries(state)):requireSeries(state,body.series);
      if(versions.length&&body.series!==undefined&&body.expected_series!==cardSeries(versions[0]))fail('REVISION_CONFLICT','卡牌期数已变化，请重新加载。',409);
      const stored = {card_id: cardId || randomUUID(), revision: versions.length + 1, series, ...compiled, interpreter_version: 'interpreter-1', compiler_version: 'card-compiler-1', provenance: draft.provenance, owner_id: versions[0]?.owner_id ?? owner, created_at: new Date().toISOString()};
      const art = Object.hasOwn(body, 'art_id') ? selectArt(state, owner, body.art_id) : versions.at(-1)?.art;
      if (art) stored.art = art;
      stored.token_art=selectTokenArt(state,owner,body.token_art_ids,compiled.definition.tokens,versions.at(-1)?.token_art);
      registerComponents(state,owner,compiled.definition);
      for(const version of versions)version.series=series;
      state.cards[stored.card_id] = [...versions, stored]; if(stored.owner_id!==owner)audit(state,owner,'admin_card_revision',stored.card_id); draft.imported_card = {card_id: stored.card_id, revision: stored.revision}; return {...stored,author:authorFor(state,stored.owner_id)};
    });
  }
  rate(state, owner) {
    const limits = state.limits[owner] ||= {created: [], day: '', attempts: 0}; const now = Date.now();
    limits.created = limits.created.filter(n => now - n < 60000);
    if (limits.created.length >= this.minuteLimit) fail('RATE_LIMITED', `每分钟最多创建 ${this.minuteLimit} 轮生成任务，请稍后继续。`, 429);
    if (Object.values(state.generations).some(j => j.owner_id === owner && ['queued', 'running'].includes(j.status))) fail('RATE_LIMITED', '已有生成任务在运行，请等待或取消。', 429);
    limits.created.push(now);
  }
  async createReview(owner, body) { return createReview(this, owner, body); }
  async createGeneration(owner, body) {
    fields(body, ['request_id', 'editor_revision', 'source_text', 'clarification_answers', 'schema_version', 'ruleset_version'], ['parent_generation_id', 'card_blueprint', 'mechanism_review']);
    text(body.source_text); integer(body.editor_revision); if (body.schema_version !== '1.0.0' || body.ruleset_version !== 'frontline-1') fail('VERSION_MISMATCH', '规则或数据版本不匹配。');
    const result = await this.idem(owner, 'generation', body, state => {
      let history = [], conversation_id = randomUUID(), round = 1, parent = null;
      let blueprint = Object.hasOwn(body, 'card_blueprint') ? validateCardBlueprint(body.card_blueprint, state.keywords) : null;
      if (body.parent_generation_id) {
        uuid(body.parent_generation_id); parent = owned(state.generations[body.parent_generation_id], owner);
        if (!['needs_clarification', 'needs_keyword_registration'].includes(parent.status)) fail('REVISION_CONFLICT', '父任务当前不能继续澄清。', 409);
        if (parent.source_text !== body.source_text || body.editor_revision < parent.editor_revision) fail('STALE_DRAFT', '后续轮次必须保留原文和有效编辑修订。', 409);
        if (parent.child_generation_id) fail('REVISION_CONFLICT', '此轮已经有后续任务。', 409);
        if (Object.hasOwn(body, 'card_blueprint') && canonical(blueprint) !== canonical(parent.card_blueprint || null)) fail('REVISION_CONFLICT', '基础数值、已选词条或固定能力已改变，请创建新的生成任务。', 409);
        blueprint = parent.card_blueprint || null;
        history = [...parent.history, ...answersCheck(body.clarification_answers, parent.result?.questions || [])]; conversation_id = parent.conversation_id; round = parent.round + 1;
      } else answersCheck(body.clarification_answers, []);
      if (Buffer.byteLength(canonical({source_text: body.source_text, history})) > 16384) fail('INPUT_TOO_LONG', '会话超过 16 KiB，请确认并使用精简需求创建新会话。', 413);
      if(this.requireFactions) requireCardFaction(blueprint??{},state.factions);
      const mechanism_review = consumeReview(state, owner, body, 'card', blueprint);
      this.rate(state, owner);
      const job = {mechanism_review, generation_id: randomUUID(), conversation_id, round, status: 'queued', editor_revision: body.editor_revision, owner_id: owner, kind: 'card', source_text: body.source_text, card_blueprint: blueprint, history, attempts: 0, created_at: new Date().toISOString()};
      if(mechanism_review)state.generations[mechanism_review.generation_id].compilation_id=job.generation_id;
      state.generations[job.generation_id] = job; if (parent) parent.child_generation_id = job.generation_id;
      return {...publicJob(job), poll_after_ms: 1000};
    });
    this.schedule(result.generation_id); return result;
  }
  async cancelGeneration(owner, id) {
    const result = await this.store.transaction(state => { const job = owned(state.generations[id], owner); if (['queued', 'running', 'needs_keyword_registration', 'needs_clarification', 'awaiting_confirmation'].includes(job.status)) { job.status = 'canceled'; delete job.result; } return publicJob(job); });
    this.controllers.get(id)?.abort(); return result;
  }
  proposalRecord(owner, definition, sourceText, name, related) {
    const proposal_id = randomUUID(); return {proposal_id, revision: 1, owner_id: owner, status: 'proposed', assigned_id: definition?.id || `custom.kw_${proposal_id.replaceAll('-', '').slice(0, 20)}`, assigned_version: definition?.version || 1, source_text: sourceText, suggested_name: name, confirmed_intent: sourceText, questions: [], candidate: null, candidate_hash: null, missing_capabilities: [], review_message: null, history: [], related_generation_id: related || null};
  }
  checkName(state, def, owner) {
    assertKeywordAvailable(state,def.id);
    const labels = new Set([def.name, ...def.aliases].map(v => v.trim().toLocaleLowerCase('en-US')));
    for (const entry of registryEntries(state.keywords)) if (entry.definition.id !== def.id && [entry.definition.name, ...entry.definition.aliases].some(v => labels.has(v.trim().toLocaleLowerCase('en-US')))) fail('REVISION_CONFLICT', `名称或别名已用于词条【${entry.definition.name}】。请从词条档案引用已有词条；修改它请打开该词条的编辑入口，制作不同效果请换一个名称。`, 409, [{code:'KEYWORD_NAME_CONFLICT',path:'/name',message:`已有词条：${entry.definition.id}@${entry.definition.version}`}]);
    const existing = state.keywords[`${def.id}@${def.version}`]; if (existing) fail('REVISION_CONFLICT', '此词条 ID 和版本已登记，不能覆盖。', 409);
    const previous = Object.values(state.keywords).filter(e => e.definition.id === def.id);
    if (previous.some(e=>e.definition.implementation.kind==='builtin') || (previous.length && previous.some(e => e.owner_id !== owner) && !isAdmin(state,owner))) fail('REVISION_CONFLICT', '该词条身份不可修改。', 409);
    const expected = previous.length ? Math.max(...previous.map(e => e.definition.version)) + 1 : 1;
    if (def.version !== expected) fail('REVISION_CONFLICT', `此词条下一个版本必须为 ${expected}。`, 409);
  }
  async keywordImport(owner, body) {
    fields(body, ['request_id', 'definition'], ['related_generation_id']);
    return this.idem(owner, 'keyword-import', body, state => {
      const checked = validateKeyword(body.definition);
      if (!checked.definition.id.startsWith('custom.') && !Object.values(state.keywords).some(e=>e.definition.id===checked.definition.id && e.definition.implementation.kind!=='builtin' && (e.owner_id===owner || isAdmin(state,owner)))) fail('INVALID_KEYWORD_PARAMS', '玩家词条必须使用 custom 命名空间。');
      this.checkName(state, checked.definition, owner);
      if (body.related_generation_id) owned(state.generations[body.related_generation_id], owner);
      const proposal = this.proposalRecord(owner, checked.definition, checked.definition.description, checked.definition.name, body.related_generation_id);
      proposal.status = 'ready_to_register'; proposal.candidate = checked.definition; proposal.candidate_hash = checked.definition_hash;
      state.proposals[proposal.proposal_id] = proposal; return publicProposal(proposal);
    });
  }
  async createProposal(owner, body) {
    fields(body, ['request_id', 'source_text', 'suggested_name', 'related_generation_id'], ['mechanism_review']); text(body.source_text); text(body.suggested_name, 64);
    const result = await this.idem(owner, 'keyword-proposal', body, state => {
      if (body.related_generation_id !== null) { uuid(body.related_generation_id); owned(state.generations[body.related_generation_id], owner); }
      this.rate(state, owner);
      const mechanism_review = consumeReview(state, owner, body, 'keyword');
      const proposal = this.proposalRecord(owner, null, body.source_text, body.suggested_name, body.related_generation_id);
      proposal.mechanism_review = mechanism_review;
      const job = this.keywordJob(state, proposal); state.proposals[proposal.proposal_id] = proposal;
      return {proposal_id: proposal.proposal_id, revision: 1, status: 'proposed', generation_job_id: job.generation_id};
    }); this.schedule(result.generation_job_id); return result;
  }
  keywordJob(state, proposal) {
    const job = {generation_id: randomUUID(), conversation_id: proposal.proposal_id, round: proposal.revision, status: 'queued', editor_revision: proposal.revision, owner_id: proposal.owner_id, kind: 'keyword', proposal_id: proposal.proposal_id, attempts: 0, created_at: new Date().toISOString()};
    proposal.generation_job_id = job.generation_id; state.generations[job.generation_id] = job; return job;
  }
  async answerProposal(owner, id, body) {
    fields(body, ['request_id', 'expected_revision', 'answers']); integer(body.expected_revision);
    const result = await this.idem(owner, `keyword-answers:${id}`, body, state => {
      const p = owned(state.proposals[id], owner); if (p.revision !== body.expected_revision || p.status !== 'needs_clarification') fail('REVISION_CONFLICT', '词条提案已变化，请重新加载。', 409);
      const history = [...p.history, ...answersCheck(body.answers, p.questions, 1)];
      if (Buffer.byteLength(canonical({source_text: p.source_text, history})) > 16384) fail('INPUT_TOO_LONG', '词条会话过长，请整理需求创建新提案。', 413);
      this.rate(state, owner); p.history = history; p.revision++; p.status = 'proposed'; p.questions = []; p.candidate = null; p.candidate_hash = null;
      const job = this.keywordJob(state, p); return {proposal_id: p.proposal_id, revision: p.revision, generation_job_id: job.generation_id};
    }); this.schedule(result.generation_job_id); return result;
  }
  async confirmKeyword(owner, id, body) {
    fields(body, ['request_id', 'expected_revision', 'candidate_hash']); integer(body.expected_revision); digest(body.candidate_hash);
    const result = await this.idem(owner, `keyword-confirm:${id}`, body, state => {
      const p = owned(state.proposals[id], owner);
      if (p.revision !== body.expected_revision || p.candidate_hash !== body.candidate_hash) fail('REVISION_CONFLICT', '词条候选修订或哈希不匹配。', 409);
      if (p.status === 'approved') return {definition: p.candidate, definition_hash: p.candidate_hash, registry_status: 'approved', approval_source: 'automatic_validation'};
      if (p.status !== 'ready_to_register') fail('REVISION_CONFLICT', '词条尚未完成澄清与候选校验。', 409);
      const checked = validateKeyword(p.candidate); this.checkName(state, checked.definition, owner);
      const originalOwner=Object.values(state.keywords).find(e=>e.definition.id===p.assigned_id)?.owner_id??owner;
      if(originalOwner!==owner)audit(state,owner,'admin_keyword_revision',p.assigned_id);
      state.keywords[`${p.assigned_id}@${p.assigned_version}`] = {...checked, owner_id: originalOwner, registry_status: 'approved', approval_source: 'automatic_validation', confirmed_revision: p.revision, validator_version: 'validator-1', approved_at: new Date().toISOString()};
      p.status = 'approved'; state.catalogs[registryHash(state.keywords)] = registryEntries(state.keywords);
      const response = {...checked, registry_status: 'approved', approval_source: 'automatic_validation'};
      const parent = state.generations[p.related_generation_id];
      if (parent && parent.owner_id === owner && parent.status === 'needs_keyword_registration' && !parent.child_generation_id) {
        const approved = Object.values(state.proposals).filter(item => item.related_generation_id === parent.generation_id && item.status === 'approved');
        const dependenciesReady = parent.result.proposals.every(requested => approved.some(item => [item.suggested_name, item.candidate.name, ...item.candidate.aliases].includes(requested.name)));
        if (dependenciesReady) {
          // Registration is committed even if quota prevents immediately resuming compilation.
          try { this.rate(state, owner); }
          catch (error) { if (!(error instanceof ApiError) || error.code !== 'RATE_LIMITED') throw error; response.resume_required = true; return response; }
          const next = {generation_id: randomUUID(), conversation_id: parent.conversation_id, round: parent.round + 1, status: 'queued', editor_revision: parent.editor_revision, owner_id: owner, kind: 'card', source_text: parent.source_text, card_blueprint: parent.card_blueprint || null, history: parent.history, attempts: 0, created_at: new Date().toISOString()};
          state.generations[next.generation_id] = next; parent.child_generation_id = next.generation_id; parent.resumed_generation_id = next.generation_id; p.resumed_generation_id = next.generation_id;
          response.resumed_generation_id = next.generation_id;
        }
      }
      return response;
    }); if (result.resumed_generation_id) this.schedule(result.resumed_generation_id); return result;
  }
  async withdrawProposal(owner, id) {
    const result = await this.store.transaction(state => { const p = owned(state.proposals[id], owner); if (p.status === 'approved') fail('REVISION_CONFLICT', '已批准词条不能撤回或覆盖。', 409); p.status = 'withdrawn'; const j = state.generations[p.generation_job_id]; if (j && !terminal.has(j.status)) j.status = 'canceled'; return publicProposal(p); });
    this.controllers.get(result.generation_job_id)?.abort(); return result;
  }
  schedule(id) {
    if (this.pending.has(id) || this.store.state.generations[id]?.status !== 'queued') return;
    this.pending.add(id); setImmediate(() => this.run(id).catch(() => {}).finally(() => this.pending.delete(id)));
  }
  async run(id) {
    const controller = new AbortController(); this.controllers.set(id, controller);
    try {
      const job = await this.store.transaction(state => { const j = state.generations[id]; if (j.status !== 'queued') return null; j.status = 'running'; return j; }); if (!job) return;
      const proposal = job.kind === 'keyword' ? this.store.state.proposals[job.proposal_id] : null;
      const context = proposal ? {proposal_id: proposal.proposal_id, revision: proposal.revision, assigned_id: proposal.assigned_id, assigned_version: proposal.assigned_version, source_text: proposal.source_text, suggested_name: proposal.suggested_name, confirmed_history: proposal.history} : {conversation_id: job.conversation_id, round: job.round, editor_revision: job.editor_revision, source_text: job.source_text, confirmed_history: job.history, keyword_resolution: []};
      if (job.kind === 'mechanism-review') Object.assign(context, {target_kind: job.target_kind, suggested_name: job.suggested_name, review_history: job.history});
      if (!proposal) {
        if (job.card_blueprint) context.card_blueprint = job.card_blueprint;
        else context.explicit_constraints = extractExplicitCardConstraints(job.source_text).constraints;
      }
      context.faction_catalog=Object.values(this.store.state.factions??{}).map(f=>({id:f.faction_id,name:f.name}));
      context.card_reference_catalog=Object.values(this.store.state.cards??{}).map(versions=>versions.at(-1)).filter(Boolean).slice(0,512).map(c=>({card_id:c.card_id,name:c.definition.name}));
      context.card_template_catalog=referenceTemplates(this.store.state,job.source_text,job.history);
      context.component_catalog=componentCatalog(this.store.state).slice(0,128);
      const output = await this.provider.generate({kind: job.kind, catalog: this.keywords().definitions.filter(k=>!k.archived), context, signal: controller.signal, onAttempt: () => this.store.transaction(state => {
        const j = state.generations[id]; if (j.status !== 'running' || controller.signal.aborted) fail('CANCELED', '任务已取消。', 409);
        const limits = state.limits[j.owner_id] ||= {created: [], day: '', attempts: 0}, day = new Date(Date.now()+8*3600000).toISOString().slice(0, 10);
        if (limits.day !== day) { limits.day = day; limits.attempts = 0; }
        if (limits.attempts >= this.dailyLimit) fail('RATE_LIMITED', `今日模型调用已达 ${this.dailyLimit} 次，北京时间次日 00:00 恢复；原会话已保留。`, 429);
        if (j.attempts >= 2) fail('RATE_LIMITED', '本轮上游调用预算已用尽。', 429); limits.attempts++; j.attempts++;
      })});
      await this.store.transaction(state => {
        const j = state.generations[id]; if (j.status !== 'running' || controller.signal.aborted) return;
        const result = normalize(output.result);
        if (result.questions) {
          const seen = new Set();
          const answeredHistory = j.kind === 'mechanism-review' ? [] : (j.kind === 'keyword' ? state.proposals[j.proposal_id].history : j.history);
          result.questions = result.questions.map((q, index) => {
            if (seen.has(q.id)) fail('INVALID_MODEL_OUTPUT', '模型返回重复的问题 ID。'); seen.add(q.id);
            if (answeredHistory.some(answer => answer.question.trim() === q.question.trim())) fail('INVALID_MODEL_OUTPUT', '模型重复询问已回答的问题，请保留已有答案后重新生成。');
            return {...q, id: `q_${id.slice(0, 8)}_${index}_${q.id}`.slice(0, 32)};
          });
        }
        if (j.kind === 'mechanism-review') {
          schemaCheck('mechanism-review', result);
          j.status = 'awaiting_confirmation'; j.result = reviewResult(result); collectJobDiagnostic(state,j); return;
        }
        if (j.kind === 'keyword') {
          const p = state.proposals[j.proposal_id]; if (p.status === 'withdrawn' || p.revision !== j.round || p.generation_job_id !== id) return;
          if (result.status === 'candidate') {
            if (result.definition.id !== p.assigned_id || result.definition.version !== p.assigned_version) fail('INVALID_MODEL_OUTPUT', '模型修改了服务端分配的词条身份。');
            const checked = validateKeyword(result.definition); this.checkName(state, checked.definition, j.owner_id);
            p.status = 'ready_to_register'; p.candidate = checked.definition; p.candidate_hash = checked.definition_hash;
          } else if (result.status === 'needs_clarification') { p.status = 'needs_clarification'; p.questions = result.questions; }
          else { p.status = 'pending_implementation'; p.missing_capabilities = result.missing_capabilities; p.review_message = result.description; }
          j.status = 'ready'; j.result = {proposal_id: p.proposal_id, proposal_status: p.status};
        } else if (result.status === 'ok') {
          const card = applyCardBlueprint(expandComponents(result.card,state.mechanism_components), j.card_blueprint);
          const checked = compileCard(card, state.keywords);
          checkMechanismIntent(j.source_text,checked.compiled_program.expanded_definition);
          if (j.card_blueprint) checkEffectAmounts(j.source_text, checked.compiled_program.expanded_definition);
          else checkExplicitNumbers(j.source_text, card, checked.compiled_program.expanded_definition);
          checkEffectAmounts(result.explanation, checked.compiled_program.expanded_definition);
          j.result = this.draft(state, j.owner_id, card, {generation_id: id, assumptions: result.assumptions, provenance: {source_kind: 'model', source_text: j.source_text, ...(j.mechanism_review ? {mechanism_review: j.mechanism_review} : {}), ...output.metadata, prompt_version: 'compiler-3'}}); j.status = 'ready';
        } else { j.status = result.status; const {status, ...rest} = result; j.result = rest; }
        collectJobDiagnostic(state,j);
      });
    } catch (error) {
      await this.store.transaction(state => { const j = state.generations[id]; if (!j || j.status !== 'running') return; j.status = controller.signal.aborted ? 'canceled' : 'failed'; j.error = safeError(error); collectJobDiagnostic(state,j);
        if (j.kind === 'keyword') { const p = state.proposals[j.proposal_id]; if (p.status !== 'withdrawn' && p.revision === j.round) { p.status = 'rejected'; p.review_message = j.error.message; } }
      }).catch(() => {});
    } finally { this.controllers.delete(id); }
  }
  async close() { for (const controller of this.controllers.values()) controller.abort(); while (this.pending.size) await new Promise(resolve => setTimeout(resolve, 20)); await this.store.close(); }
}
