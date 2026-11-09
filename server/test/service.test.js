import {builtinDefinitions} from '../src/validation.js';
const initialKeywords=4+builtinDefinitions.length;
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import http from 'node:http';
import {createApp} from '../src/index.js';
import {strictParse, canonical, hash} from '../src/codec.js';
import {compileCard, validateKeyword, docsURL, extractExplicitCardConstraints, checkExplicitNumbers, validateCardBlueprint, applyCardBlueprint} from '../src/validation.js';
import {DeepSeekProvider, makePrompt} from '../src/provider.js';
import {ruleCapabilities} from '../src/rule_capabilities.js';

const fixture = async name => JSON.parse(await readFile(new URL(`examples/${name}.json`, docsURL), 'utf8'));
const manualUnit = () => ({schema_version: '1.0.0', ruleset_version: 'frontline-1', name: '测试手工定义', flavor_text: '', kind: 'unit', unit_class: 'infantry', cost: 2, operation_cost: 1, attack: 2, health: 3, keywords: [], play_target: null, abilities: [], tokens: [], appearance: {emblem: 'infantry'}});
const generationBody = (extra = {}) => ({request_id: randomUUID(), editor_revision: 1, source_text: '2费步兵，2攻3血，行动费1，无能力。', clarification_answers: [], schema_version: '1.0.0', ruleset_version: 'frontline-1', ...extra});
async function setup(t, options = {}) {
  const dataDir = options.dataDir || await mkdtemp(join(tmpdir(), 'chao-service-'));
  const app = await createApp({dataDir, port: 0, minuteLimit: 100, dailyLimit: 500, ...options});
  const address = await app.listen(); const base = `http://127.0.0.1:${address.port}`;
  const request = async (path, body, method = body ? 'POST' : 'GET', headers = {}) => {
    const response = await fetch(base + path, {method, headers: {'Content-Type': 'application/json', ...headers}, ...(body !== undefined ? {body: typeof body === 'string' ? body : JSON.stringify(body)} : {})});
    return {status: response.status, body: await response.json()};
  };
  t.after(async () => { await app.close(); if (!options.dataDir) await rm(dataDir, {recursive: true, force: true}); });
  return {app, request, dataDir};
}
async function complete(request, id) {
  for (let n = 0; n < 200; n++) {
    const response = await request(`/v1/card-generations/${id}`);
    if (!['queued', 'running'].includes(response.body.status)) return response.body;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw new Error('Job never completed');
}
function scriptedProvider(results) {
  const calls = [];
  return {model: 'test-only', configured: true, calls, async generate(input) { await input.onAttempt(); calls.push(input); const next = results.shift(); if (next instanceof Error) throw next; const result = typeof next === 'function' ? await next(input) : next; return {result, metadata: {requested_model: 'test-only', returned_model: 'test-only'}}; }};
}

const reviewOutput=(formal_text,questions=[],missing_capabilities=[])=>({status:'review',formal_text,questions,missing_capabilities});
test('mechanism review keeps frozen fields and revision history, compiles only the confirmed interpretation',async t=>{
  const unit=manualUnit();unit.abilities=[{trigger:'on_play',effects:[{op:'modify_stacks',stack:'heavy_armor',target:'self',amount:2,duration:'battle'}]}];
  const provider=scriptedProvider([reviewOutput('登场时获得重甲1。'),reviewOutput('登场时获得重甲2。'),{status:'ok',card:unit,explanation:'登场时获得重甲2。',assumptions:[]}]);
  const {app,request}=await setup(t,{provider});
  const card_blueprint={name:unit.name,kind:'unit',unit_class:'infantry',cost:2,operation_cost:1,attack:2,health:3,keywords:[]};
  const first=await request('/v1/mechanism-reviews',{request_id:randomUUID(),kind:'card',source_text:'重甲1',card_blueprint});assert.equal(first.status,202);
  const a=await complete(request,first.body.generation_id);assert.equal(a.status,'awaiting_confirmation');assert.equal(Object.keys(app.service.store.state.drafts).length,0);
  const ref=j=>({generation_id:j.generation_id,result_hash:j.result.result_hash});
  const confirmed=j=>generationBody({source_text:j.result.formal_text,card_blueprint,mechanism_review:ref(j)});
  const second=await request('/v1/mechanism-reviews',{request_id:randomUUID(),kind:'card',parent_generation_id:a.generation_id,review_hash:a.result.result_hash,feedback:'改成2层',answers:[]});assert.equal(second.status,202);
  const b=await complete(request,second.body.generation_id);assert.equal(b.status,'awaiting_confirmation');assert.equal(provider.calls[1].context.review_history[0].feedback,'改成2层');assert.equal(provider.calls[1].context.source_text,'重甲1');
  assert.equal((await request('/v1/card-generations',confirmed(a))).status,409,'stale interpretation cannot compile');
  assert.equal((await request('/v1/card-generations',{...confirmed(b),card_blueprint:{...card_blueprint,attack:9}})).status,409,'frozen fields cannot change');
  const body=confirmed(b),next=await request('/v1/card-generations',body);assert.equal(next.status,202,JSON.stringify(next.body));
  assert.deepEqual((await request('/v1/card-generations',body)).body,next.body,'confirmation idempotent');
  const ready=await complete(request,next.body.generation_id);assert.equal(ready.status,'ready',JSON.stringify(ready));assert.equal(ready.result.definition.abilities[0].effects[0].amount,2);
  assert.equal((await request('/v1/card-generations',confirmed(b))).status,409,'cannot consume twice');
  assert.equal(provider.calls.at(-1).context.source_text,'登场时获得重甲2。');assert.equal(Object.keys(app.service.store.state.cards).length,0,'still requires explicit save');
});

test('keyword interpretation supports questions, multiple revisions, and separate registration confirmation',async t=>{
 const provider=scriptedProvider([reviewOutput('获得重甲，持续时间待确认。',[{id:'duration',question:'持续多久？',options:['本次在场期间','当前回合']}]),reviewOutput('登场时获得重甲2，持续本次在场期间。'),input=>({status:'candidate',definition:{schema_version:'1.0.0',ruleset_version:'frontline-1',id:input.context.assigned_id,version:1,name:'强化装甲',description:'登场时获得重甲2。',aliases:[],parameters:{},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{op:'modify_stacks',target:'self',stack:'heavy_armor',amount:2,duration:'battle'}]}]}}})]);
 const {request}=await setup(t,{provider});
 const first=await request('/v1/mechanism-reviews',{request_id:randomUUID(),kind:'keyword',source_text:'获得两层重甲',suggested_name:'强化装甲'});const a=await complete(request,first.body.generation_id);
 const compile=j=>({request_id:randomUUID(),source_text:j.result.formal_text,suggested_name:'强化装甲',related_generation_id:null,mechanism_review:{generation_id:j.generation_id,result_hash:j.result.result_hash}});
 assert.equal((await request('/v1/keyword-proposals',compile(a))).status,409,'unanswered review is not confirmable');
 const second=await request('/v1/mechanism-reviews',{request_id:randomUUID(),kind:'keyword',parent_generation_id:a.generation_id,review_hash:a.result.result_hash,answers:[{question_id:a.result.questions[0].id,answer:'登场获得，整个在场期间'}]});const b=await complete(request,second.body.generation_id);
 const next=await request('/v1/keyword-proposals',compile(b));assert.equal(next.status,202,JSON.stringify(next.body));await complete(request,next.body.generation_job_id);
 const p=(await request('/v1/keyword-proposals/'+next.body.proposal_id)).body;assert.equal(p.status,'ready_to_register');assert.equal((await request('/v1/keywords')).body.definitions.length,initialKeywords);
 assert.equal((await request(`/v1/keyword-proposals/${p.proposal_id}/confirm`,{request_id:randomUUID(),expected_revision:p.revision,candidate_hash:p.candidate_hash})).status,201);
});

test('interpretation ownership, cancellation and missing capabilities block confirmation',async t=>{
 const provider=scriptedProvider([reviewOutput('每回合额外一个回合',[],['额外回合未支持'])]);const {app,request}=await setup(t,{provider});
 const first=await request('/v1/mechanism-reviews',{request_id:randomUUID(),kind:'keyword',source_text:'每回合额外一个回合',suggested_name:'时间'});const a=await complete(request,first.body.generation_id);
 const body={request_id:randomUUID(),source_text:a.result.formal_text,suggested_name:'时间',related_generation_id:null,mechanism_review:{generation_id:a.generation_id,result_hash:a.result.result_hash}};
 await assert.rejects(app.service.createProposal('another-owner',body),e=>e.code==='NOT_FOUND');
 assert.equal((await request('/v1/keyword-proposals',body)).status,409);
 assert.equal((await request('/v1/card-generations/'+a.generation_id,undefined,'DELETE')).body.status,'canceled');
 assert.equal((await request('/v1/keyword-proposals',{...body,request_id:randomUUID()})).status,409);
});

test('official adapter explicitly enables high thinking and only returns final structured interpretation',async()=>{
 const provider=new DeepSeekProvider({apiKey:'test-only',fetch:async(url,options)=>{
  const body=JSON.parse(options.body);assert.deepEqual(body.thinking,{type:'enabled'});assert.equal(body.reasoning_effort,'high');assert.equal(body.temperature,undefined);assert.equal(body.max_tokens,16384);
  return new Response(JSON.stringify({model:'deepseek-flash',choices:[{finish_reason:'stop',message:{reasoning_content:'private reasoning fixture',content:JSON.stringify(reviewOutput('登场时获得重甲2。'))}}]}));
 }});
 const result=await provider.generate({kind:'mechanism-review',catalog:[],context:{source_text:'重甲2',target_kind:'keyword'},signal:new AbortController().signal,onAttempt:async()=>{}});
 assert.equal(result.result.formal_text,'登场时获得重甲2。');assert(!JSON.stringify(result).includes('private reasoning fixture'));assert.equal(result.metadata.thinking,'enabled');
});

const artilleryBlueprint = (extra = {}) => ({kind: 'unit', unit_class: 'artillery', cost: 3, operation_cost: 0, attack: 2, health: 1, keywords: [], ...extra});

test('canonical encoder passes every cross-language byte/hash vector', async () => {
  for (const vector of (await fixture('canonical_vectors')).vectors) { const value = strictParse(vector.input_json); assert.equal(canonical(value), vector.canonical_utf8, vector.name); assert.equal(hash(value), vector.sha256, vector.name); }
});
test('strict parser rejects duplicate keys, trailing text, lone surrogates, noninteger and invalid UTF-8', () => {
  for (const value of ['{"a":1,"a":2}', '{"a":1} tail', '{"a":NaN}', '{"a":1.2}', '{"a":"\\ud800"}', '{"a":9007199254740992}', '\ufeff{}', '{"a":1,}']) assert.throws(() => strictParse(value));
  assert.throws(() => strictParse(Buffer.from([0xc0, 0xaf]))); assert.throws(() => strictParse('['.repeat(18) + '0' + ']'.repeat(18)));
  assert.equal(canonical(strictParse('{"a":1.0,"b":-0}')), '{"a":1,"b":0}');
});
test('compiler matches exact fixture hash and rejects semantic/unknown operation fixtures', async t => {
  const {app} = await setup(t); const registry = structuredClone(app.service.store.state.keywords);
  const custom = validateKeyword(await fixture('keywords/example_supply')); registry[`${custom.definition.id}@1`] = {...custom, registry_status: 'approved'};
  const compiled = compileCard(await fixture('valid_unit'), registry), expected = await fixture('compiled_unit');
  assert.equal(compiled.compiled_program_hash, expected.compiled_program_hash); assert.equal(canonical(compiled.compiled_program), canonical(expected.compiled_program));
  for (const file of ['invalid_unknown_op', 'invalid_semantic_target']) { const invalid = await fixture(file); assert.throws(() => compileCard(invalid, registry)); }
});
test('new service has no cards; no configured key returns a visible failed job without fake generation', async t => {
  const {request} = await setup(t, {provider: new DeepSeekProvider({apiKey: ''})});
  const health = await request('/health'); assert.equal(health.body.card_count, 0); assert.equal(health.body.configured, false);
  assert.equal((await request('/v1/keywords')).body.definitions.length, initialKeywords);
  const task = await request('/v1/card-generations', generationBody()); assert.equal(task.status, 202);
  const done = await complete(request, task.body.generation_id); assert.equal(done.status, 'failed'); assert.equal(done.error.code, 'PROVIDER_NOT_CONFIGURED');
});
test('manual previews do not publish; confirmation is durable and idempotent; revisions preserve old versions', async t => {
  const {app, request} = await setup(t);
  const definition = manualUnit(); definition.name = 'Cafe\u0301';
  const draft = await request('/v1/card-drafts', {request_id: randomUUID(), definition}); assert.equal(draft.status, 201); assert.equal(draft.body.result.definition.name, 'Café');
  assert.equal((await request('/v1/cards')).body.cards.length, 0);
  const body = {request_id: randomUUID(), draft_id: draft.body.result.draft_id, draft_hash: draft.body.result.draft_hash};
  const [a, b] = await Promise.all([request('/v1/cards', body), request('/v1/cards', body)]); assert.deepEqual(a.body, b.body); assert.equal(a.status, 201);
  const otherID = await request('/v1/cards', {...body, request_id: randomUUID()}); assert.equal(otherID.body.card_id, a.body.card_id);
  assert.equal((await request('/v1/cards')).body.cards.length, 1);
  const conflicting = await request('/v1/cards', {...body, draft_hash: 'a'.repeat(64)}); assert.equal(conflicting.status, 409);
  const next = await request('/v1/card-drafts', {request_id: randomUUID(), definition: {...definition, attack: 3}});
  const revision = await request(`/v1/cards/${a.body.card_id}/revisions`, {request_id: randomUUID(), base_revision: 1, draft_id: next.body.result.draft_id, draft_hash: next.body.result.draft_hash});
  assert.equal(revision.body.revision, 2); assert.equal((await request(`/v1/cards/${a.body.card_id}?revision=1`)).body.definition.attack, 2);
  const disk = JSON.parse(await readFile(app.service.store.file, 'utf8')); assert.equal(disk.cards[a.body.card_id].length, 2);
});
test('strict request validation and bad import hash never create drafts or cards', async t => {
  const {request, app} = await setup(t);
  assert.equal((await request('/v1/card-drafts', '{"request_id":"x","request_id":"y","definition":{}}')).status, 400);
  assert.equal((await request('/v1/card-drafts', {request_id: randomUUID(), definition: {...manualUnit(), script: 'evil'}})).status, 422);
  assert.equal((await request('/v1/card-imports', {request_id: randomUUID(), package: {package_version: '1', definition: manualUnit(), definition_hash: '0'.repeat(64)}})).body.error.code, 'HASH_MISMATCH');
  assert.equal(Object.keys(app.service.store.state.drafts).length, 0);
  assert.equal((await request('/v1/card-drafts', {request_id: randomUUID(), definition: manualUnit(), unauthorized: true})).status, 400);
});
test('keyword confirmation registers separately, validates all parameter values, and expands once', async t => {
  const {request} = await setup(t); const base = await fixture('keywords/example_supply'); base.id = 'custom.supply';
  const proposal = await request('/v1/keyword-imports', {request_id: randomUUID(), definition: base}); assert.equal(proposal.body.status, 'ready_to_register');
  const unit = {...manualUnit(), keywords: [{id: 'custom.supply', version: 1, params: {amount: 2}}]};
  assert.equal((await request('/v1/card-drafts', {request_id: randomUUID(), definition: unit})).body.error.code, 'KEYWORD_NOT_REGISTERED');
  const confirmBody = {request_id: randomUUID(), expected_revision: 1, candidate_hash: proposal.body.candidate_hash};
  const approved = await request(`/v1/keyword-proposals/${proposal.body.proposal_id}/confirm`, confirmBody); assert.equal(approved.status, 201);
  assert.equal((await request(`/v1/keyword-proposals/${proposal.body.proposal_id}`, undefined, 'DELETE')).status, 409);
  const draft = await request('/v1/card-drafts', {request_id: randomUUID(), definition: unit}); assert.equal(draft.status, 201);
  assert.equal(draft.body.result.compiled_program.expanded_definition.abilities.length, 1);
  assert.equal(draft.body.result.compiled_program.expanded_definition.abilities[0].effects[0].amount, 2);
  assert.equal(draft.body.result.compiled_program.expanded_definition.keywords.length, 0);
  const bad = {...base, id: 'custom.bad', name: '边界坏词条', parameters: {attack: {type: 'integer', minimum: -1, maximum: 1}, health: {type: 'integer', minimum: -1, maximum: 1}}, implementation: {kind: 'template', abilities: [{trigger: 'on_play', effects: [{op: 'modify_stats', target: 'self', attack_delta: {param: 'attack'}, health_delta: {param: 'health'}, duration: 'battle'}]}]}};
  const rejected = await request('/v1/keyword-imports', {request_id: randomUUID(), definition: bad}); assert.equal(rejected.status, 422); assert.equal((await request('/v1/keywords')).body.definitions.length, initialKeywords+1);
  const conflict = await request('/v1/keyword-imports', {request_id: randomUUID(), definition: {...base, id: 'custom.other'}}); assert.equal(conflict.status, 409);
});
test('fight keyword generation, explicit registration and card preview preserve the new operations', async t => {
  const fight = await fixture('keywords/example_fight'); fight.name='双重射击'; fight.aliases=[];
  const provider = scriptedProvider([input => ({status:'candidate',definition:{...fight,id:input.context.assigned_id,version:input.context.assigned_version}})]);
  const {request} = await setup(t,{provider});
  const created = await request('/v1/keyword-proposals',{request_id:randomUUID(),source_text:'双重射击，每回合可以攻击两次',suggested_name:'双重射击',related_generation_id:null});
  await complete(request,created.body.generation_job_id);
  const ready = (await request(`/v1/keyword-proposals/${created.body.proposal_id}`)).body;
  assert.equal(ready.status,'ready_to_register');
  assert.equal((await request('/v1/keywords')).body.definitions.length,initialKeywords,'candidate does not publish itself');
  const confirmation = await request(`/v1/keyword-proposals/${ready.proposal_id}/confirm`,{request_id:randomUUID(),expected_revision:ready.revision,candidate_hash:ready.candidate_hash});
  assert.equal(confirmation.status,201);
  const definition = {...manualUnit(),keywords:[{id:ready.assigned_id,version:ready.assigned_version,params:{}}],abilities:[{trigger:'on_play',effects:[{op:'modify_operation_cost',target:'self',cost_delta:-1,duration:'battle'},{op:'destroy',target:'random_enemy_unit'}]}]};
  const draft = await request('/v1/card-drafts',{request_id:randomUUID(),definition});
  assert.equal(draft.status,201,JSON.stringify(draft.body));
  const effects = draft.body.result.compiled_program.expanded_definition.abilities.flatMap(a=>a.effects);
  assert.deepEqual(effects.map(e=>e.op),['modify_operation_cost','destroy','set_attack_limit']);
  assert.equal(effects.at(-1).attacks,2);
  assert.equal((await request('/v1/cards')).body.cards.length,0,'card still needs separate confirmation');
  const health = (await request('/health')).body;
  assert.deepEqual(health.rules,ruleCapabilities);
  for (const kind of ['card','keyword']) {
    const prompt = makePrompt(kind,[]);
    for (const op of ['set_attack_limit','destroy','modify_operation_cost']) assert.ok(prompt.includes(op));
    assert.match(prompt,/每回合可以攻击两次/); assert.match(prompt,/不叠加、不清空已用次数/);
  }
});

test('card generation handles four result branches and server-owned multi-round history', async t => {
  const provider = scriptedProvider([{status: 'needs_clarification', questions: [{id: 'stats', question: '攻防是多少？', options: ['2/3', '3/4']}]}, {status: 'ok', card: manualUnit(), assumptions: [], explanation: ''}, {status: 'needs_keyword_registration', proposals: [{name: '补给', description: '抽牌', requested_behavior: '登场抽牌'}], questions: []}, {status: 'unsupported', reasons: ['不支持复活'], suggestions: ['可明确设计新的支持能力']}]);
  const {request} = await setup(t, {provider}); const firstBody = generationBody();
  const first = await request('/v1/card-generations', firstBody), q = await complete(request, first.body.generation_id); assert.equal(q.status, 'needs_clarification');
  const nextBody = generationBody({parent_generation_id: q.generation_id, clarification_answers: [{question_id: q.result.questions[0].id, answer: '2/3'}]});
  const next = await request('/v1/card-generations', nextBody), ready = await complete(request, next.body.generation_id); assert.equal(ready.status, 'ready'); assert.equal(provider.calls[1].context.confirmed_history[0].answer, '2/3');
  assert.equal((await request('/v1/cards')).body.cards.length, 0);
  for (const status of ['needs_keyword_registration', 'unsupported']) { const task = await request('/v1/card-generations', generationBody()); assert.equal((await complete(request, task.body.generation_id)).status, status); }
});
test('cancellation wins over a late provider response and repeated request IDs never call twice', async t => {
  let release; const blocked = new Promise(resolve => release = resolve);
  const provider = scriptedProvider([async () => { await blocked; return {status: 'ok', card: manualUnit(), assumptions: [], explanation: ''}; }]);
  const {request, app} = await setup(t, {provider}); const body = generationBody();
  const task = await request('/v1/card-generations', body); await request('/v1/card-generations', body);
  while (!provider.calls.length) await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal((await request(`/v1/card-generations/${task.body.generation_id}`, undefined, 'DELETE')).body.status, 'canceled'); release();
  await new Promise(resolve => setTimeout(resolve, 30)); assert.equal((await request(`/v1/card-generations/${task.body.generation_id}`)).body.status, 'canceled');
  assert.equal(provider.calls.length, 1); assert.equal(Object.keys(app.service.store.state.drafts).length, 0);
});
test('keyword natural language multi-round clarification keeps allocated identity until explicit confirmation', async t => {
  const provider = scriptedProvider([{status: 'needs_clarification', questions: [{id: 'draw', question: '抽几张？', options: ['1', '2']}]}, async input => ({status: 'candidate', definition: {...await fixture('keywords/example_supply'), id: input.context.assigned_id, version: input.context.assigned_version}})]);
  const {request} = await setup(t, {provider});
  const created = await request('/v1/keyword-proposals', {request_id: randomUUID(), source_text: '创建补给词条，登场抽牌', suggested_name: '补给', related_generation_id: null});
  await complete(request, created.body.generation_job_id);
  const proposal = (await request(`/v1/keyword-proposals/${created.body.proposal_id}`)).body; assert.equal(proposal.status, 'needs_clarification');
  const round = await request(`/v1/keyword-proposals/${proposal.proposal_id}/answers`, {request_id: randomUUID(), expected_revision: 1, answers: [{question_id: proposal.questions[0].id, answer: '每张卡提供1到3的整数参数'}]});
  await complete(request, round.body.generation_job_id); const ready = (await request(`/v1/keyword-proposals/${proposal.proposal_id}`)).body;
  assert.equal(ready.status, 'ready_to_register'); assert.equal(ready.assigned_id, proposal.assigned_id); assert.equal(ready.revision, 2); assert.equal((await request('/v1/keywords')).body.definitions.length, initialKeywords);
  assert.equal((await request(`/v1/keyword-proposals/${proposal.proposal_id}/confirm`, {request_id: randomUUID(), expected_revision: 1, candidate_hash: ready.candidate_hash})).status, 409);
  assert.equal((await request(`/v1/keyword-proposals/${proposal.proposal_id}/confirm`, {request_id: randomUUID(), expected_revision: 2, candidate_hash: ready.candidate_hash})).status, 201);
});
test('official adapter uses a local mock HTTP server for bounded format repair and budget (zero real API calls)', async t => {
  const received = []; const upstream = http.createServer(async (req, res) => {
    let input = ''; for await (const chunk of req) input += chunk; received.push(JSON.parse(input));
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({id: 'mock-1', model: 'deepseek-flash', choices: [{finish_reason: 'stop', message: {content: received.length === 1 ? '{"status":"ok","status":"unsupported"}' : JSON.stringify({status: 'ok', card: manualUnit(), assumptions: [], explanation: ''})}}]}));
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve)); t.after(() => new Promise(resolve => upstream.close(resolve)));
  const provider = new DeepSeekProvider({apiKey: 'test-only-not-real', fetch: (url, options) => { assert.equal(url, 'https://api.deepseek.com/chat/completions'); return fetch(`http://127.0.0.1:${upstream.address().port}`, options); }});
  const {request, app} = await setup(t, {provider}); const task = await request('/v1/card-generations', generationBody()); const ready = await complete(request, task.body.generation_id);
  assert.equal(ready.status, 'ready'); assert.equal(received.length, 2); assert.equal(received[0].model, 'deepseek-flash'); assert.deepEqual(received[0].response_format, {type: 'json_object'}); assert.equal(received[1].messages.length, 3);
  assert.equal(app.service.store.state.generations[task.body.generation_id].attempts, 2);
});
test('token auth and browser origin rejection protect local mutation endpoints', async t => {
  const {request} = await setup(t, {token: 'a'.repeat(32)});
  assert.equal((await request('/health')).status, 401);
  assert.equal((await request('/health', undefined, 'GET', {Authorization: `Bearer ${'a'.repeat(32)}`})).status, 200);
  assert.equal((await request('/health', undefined, 'GET', {Authorization: `Bearer ${'a'.repeat(32)}`, Origin: 'https://attacker.example'})).status, 403);
});

test('restart retains approved cards and marks unfinished upstream jobs failed instead of replaying charges', async t => {
  const dataDir = await mkdtemp(join(tmpdir(), 'chao-restart-')); t.after(() => rm(dataDir, {recursive: true, force: true}));
  const first = await createApp({dataDir, port: 0}); const owner = 'local-player';
  const preview = await first.service.manualDraft(owner, {request_id: randomUUID(), definition: manualUnit()});
  const stored = await first.service.confirmCard(owner, {request_id: randomUUID(), draft_id: preview.result.draft_id, draft_hash: preview.result.draft_hash});
  const pending = randomUUID();
  await first.service.store.transaction(state => { state.generations[pending] = {generation_id: pending, owner_id: owner, status: 'running', kind: 'card', attempts: 1}; });
  await first.close();
  const second = await createApp({dataDir, port: 0});
  try { assert.equal(second.service.cards(owner).cards[0].definition_hash, stored.definition_hash); assert.equal(second.service.job(owner, pending).status, 'failed'); assert.equal(second.service.store.state.generations[pending].attempts, 1); }
  finally { await second.close(); }
});

test('automatic keyword registration resumes only the associated unchanged pending card', async t => {
  const provider = scriptedProvider([{status: 'needs_keyword_registration', proposals: [{name: '补给', description: '抽牌', requested_behavior: '登场抽牌'}], questions: []}, {status: 'ok', card: manualUnit(), assumptions: [], explanation: ''}]);
  const {request} = await setup(t, {provider});
  const created = await request('/v1/card-generations', generationBody()); const parent = await complete(request, created.body.generation_id);
  const definition = await fixture('keywords/example_supply'); definition.id = 'custom.supply'; definition.name = '补给';
  const p = (await request('/v1/keyword-imports', {request_id: randomUUID(), definition, related_generation_id: parent.generation_id})).body;
  const confirmation = await request(`/v1/keyword-proposals/${p.proposal_id}/confirm`, {request_id: randomUUID(), expected_revision: 1, candidate_hash: p.candidate_hash});
  assert.match(confirmation.body.resumed_generation_id, /^[0-9a-f-]+$/);
  const resumed = await complete(request, confirmation.body.resumed_generation_id); assert.equal(resumed.status, 'ready'); assert.equal(resumed.conversation_id, parent.conversation_id);
  assert.equal(provider.calls.length, 2); assert.equal((await request('/v1/cards')).body.cards.length, 0);
});

test('provider authentication failure is never retried and two invalid outputs exhaust shared repair budget', async () => {
  let calls = 0, attempts = 0;
  const auth = new DeepSeekProvider({apiKey: 'fake-test', fetch: async () => { calls++; return new Response('{}', {status: 401}); }});
  const input = {kind: 'card', catalog: [], context: {}, signal: new AbortController().signal, onAttempt: async () => { attempts++; }};
  await assert.rejects(auth.generate(input), error => error.code === 'PROVIDER_AUTH_FAILED'); assert.equal(calls, 1);
  calls = 0; attempts = 0;
  const invalid = new DeepSeekProvider({apiKey: 'fake-test', fetch: async () => { calls++; return new Response(JSON.stringify({choices: [{finish_reason: 'stop', message: {content: '{bad json'}}]}), {status: 200}); }});
  await assert.rejects(invalid.generate(input), error => error.code === 'INVALID_MODEL_OUTPUT'); assert.equal(calls, 2); assert.equal(attempts, 2);
});

test('legacy intent extraction consumes prefix/suffix attributes without reading deployment/action across boundaries', () => {
  const expected = {cost: 3, operation_cost: 0, attack: 2, health: 1, unit_class: 'artillery'};
  const cases = [
    '一张炮，3费部署0行动，攻击2防御1',
    '一张炮兵，部署费用：3，行动费用：0，攻击力：2，生命值：1',
    '炮，3部署费0行动费2攻1血',
    '3费炮兵，0费行动，2攻击1防御',
    '一张炮，部署3费行动0费攻击2防御1',
    '一门火炮，部署费=3;行动费=0;攻击=2;生命=1',
    '炮兵，行动费0部署费3生命1攻击2',
    '一张炮，３费部署０行动，攻击２防御１',
    '炮兵，3费，0行动，2攻，1血',
    '一张炮，部署费用为3，行动费用为0，攻击力是2，生命值是1'
  ];
  for (const source of cases) {
    assert.deepEqual(extractExplicitCardConstraints(source).constraints, expected, source);
    assert.doesNotThrow(() => checkExplicitNumbers(source, {...expected, abilities: []}), source);
  }
  const source = cases[0];
  for (const field of ['cost', 'operation_cost', 'attack', 'health', 'unit_class']) assert.throws(() => checkExplicitNumbers(source, {...expected, [field]: field === 'unit_class' ? 'infantry' : 9, abilities: []}), error => error.details?.[0]?.path === `/${field}`);
  assert.deepEqual(extractExplicitCardConstraints('部署时对敌方总部造成2点伤害，抽1张牌。').constraints, {});
});

test('exact artillery report reaches ready with correct model output; failure was overlapping validation, not card cost', async t => {
  const source = '一张炮，3费部署0行动，攻击2防御1';
  const card = {...manualUnit(), ...artilleryBlueprint(), appearance: {emblem: 'artillery'}};
  const provider = scriptedProvider([{status: 'ok', card, assumptions: [], explanation: ''}]);
  const {request} = await setup(t, {provider});
  const started = await request('/v1/card-generations', generationBody({source_text: source}));
  const ready = await complete(request, started.body.generation_id);
  assert.equal(ready.status, 'ready'); assert.equal(ready.result.definition.cost, 3); assert.equal(ready.result.definition.operation_cost, 0);
  assert.equal(ready.result.definition.attack, 2); assert.equal(ready.result.definition.health, 1); assert.equal(ready.result.definition.unit_class, 'artillery');
  assert.deepEqual(provider.calls[0].context.explicit_constraints, {cost: 3, operation_cost: 0, attack: 2, health: 1, unit_class: 'artillery'});
  assert.equal((await request('/v1/cards')).body.cards.length, 0);
});

test('player blueprint freezes all base fields and selected keywords while model only supplies additional mechanisms', async t => {
  const blueprint = artilleryBlueprint({name: '玩家的炮', keywords: [{id: 'core.guard', version: 1, params: {}}]});
  const modelCard = {...manualUnit(), name: '模型改名', cost: 9, attack: 9, health: 9, operation_cost: 3, keywords: [{id: 'core.blitz', version: 1, params: {}}], abilities: [{trigger: 'on_play', effects: [{op: 'damage', target: 'enemy_hq', amount: 2}, {op: 'modify_stats', target: 'self', attack_delta: 4, health_delta: 0, duration: 'battle'}]}]};
  const provider = scriptedProvider([{status: 'ok', card: modelCard, assumptions: [], explanation: '登场对敌方总部造成2点伤害，自身攻击增加4。'}]);
  const {request} = await setup(t, {provider});
  const source = '这段机制说明提及部署0行动，基础配置以表单为准。登场对敌方总部造成2点伤害，自身攻击增加4。';
  const started = await request('/v1/card-generations', generationBody({source_text: source, card_blueprint: blueprint}));
  const ready = await complete(request, started.body.generation_id); assert.equal(ready.status, 'ready');
  for (const field of ['kind', 'unit_class', 'cost', 'operation_cost', 'attack', 'health', 'name']) assert.equal(ready.result.definition[field], blueprint[field], field);
  assert.deepEqual(ready.result.definition.keywords.map(ref => ref.id), ['core.guard', 'core.blitz']);
  assert.equal(ready.result.definition.abilities[0].effects[0].amount, 2); assert.equal(ready.result.definition.abilities[0].effects[1].attack_delta, 4);
  assert.equal(ready.result.definition.appearance.emblem, 'artillery');
  assert.deepEqual(provider.calls[0].context.card_blueprint, blueprint); assert.equal(provider.calls[0].context.explicit_constraints, undefined);
});

test('blueprint is validated before provider call and remains frozen across clarification rounds', async t => {
  const provider = scriptedProvider([{status: 'needs_clarification', questions: [{id: 'target', question: '附加伤害作用于单位还是总部？', options: ['单位', '总部']}]}, {status: 'ok', card: {...manualUnit(), abilities: [{trigger: 'on_play', effects: [{op: 'damage', target: 'enemy_hq', amount: 2}]}]}, assumptions: [], explanation: ''}]);
  const {request, app} = await setup(t, {provider});
  const invalid = [artilleryBlueprint({cost: -1}), artilleryBlueprint({attack: '2'}), artilleryBlueprint({health: 0}), artilleryBlueprint({extra: true}), artilleryBlueprint({kind: 'order', unit_class: null, attack: 0, health: 0, operation_cost: 1}), artilleryBlueprint({keywords: [{id: 'custom.missing', version: 1, params: {}}]})];
  for (const blueprint of invalid) assert.equal((await request('/v1/card-generations', generationBody({card_blueprint: blueprint}))).status >= 400, true);
  assert.equal(provider.calls.length, 0);
  const blueprint = artilleryBlueprint({name: ''}), source = '登场造成2点伤害';
  const first = await request('/v1/card-generations', generationBody({source_text: source, card_blueprint: blueprint}));
  const waiting = await complete(request, first.body.generation_id);
  const continuation = {source_text: source, parent_generation_id: waiting.generation_id, clarification_answers: [{question_id: waiting.result.questions[0].id, answer: '敌方总部'}]};
  assert.equal((await request('/v1/card-generations', generationBody({...continuation, card_blueprint: artilleryBlueprint({cost: 4})}))).status, 409);
  const second = await request('/v1/card-generations', generationBody(continuation));
  const ready = await complete(request, second.body.generation_id); assert.equal(ready.status, 'ready'); assert.equal(ready.result.definition.cost, 3); assert.equal(ready.result.definition.name, manualUnit().name);
  assert.deepEqual(provider.calls[1].context.card_blueprint, artilleryBlueprint()); assert.equal(app.service.store.state.generations[second.body.generation_id].card_blueprint.attack, 2);
});

test('selected keyword references cannot be lost or overwritten, and added effects still require their own numeric correctness', async t => {
  const {app, request} = await setup(t);
  const guard = {id: 'core.guard', version: 1, params: {}}, blitz = {id: 'core.blitz', version: 1, params: {}};
  const blueprint = validateCardBlueprint(artilleryBlueprint({keywords: [guard]}), app.service.store.state.keywords);
  assert.deepEqual(applyCardBlueprint(manualUnit(), blueprint).keywords, [guard]);
  assert.deepEqual(applyCardBlueprint({...manualUnit(), keywords: [guard, blitz]}, blueprint).keywords, [guard, blitz]);
  assert.throws(() => applyCardBlueprint({...manualUnit(), keywords: [{...guard, version: 2}]}, blueprint), error => error.code === 'INVALID_KEYWORD_PARAMS');
  assert.throws(() => applyCardBlueprint({...manualUnit(), keywords: [{...guard, params: {amount: 1}}]}, blueprint), error => error.code === 'INVALID_KEYWORD_PARAMS');
  const provider = scriptedProvider([{status: 'ok', card: {...manualUnit(), abilities: [{trigger: 'on_play', effects: [{op: 'draw', player: 'owner', amount: 3}]}]}, assumptions: [], explanation: ''}]);
  app.service.provider = provider;
  const task = await request('/v1/card-generations', generationBody({source_text: '登场抽1张牌', card_blueprint: blueprint}));
  const failed = await complete(request, task.body.generation_id); assert.equal(failed.status, 'failed'); assert.equal(failed.error.code, 'SEMANTIC_VALIDATION_FAILED');
  assert.equal((await request('/v1/cards')).body.cards.length, 0);
});

test('official adapter restores frozen blueprint before schema validation and does not confuse base attack with effect amount', async () => {
  let sent, attempts = 0;
  const blueprint = artilleryBlueprint({name: '基础数据只读', keywords: [{id: 'core.guard', version: 1, params: {}}]});
  const provider = new DeepSeekProvider({apiKey: 'test-not-real', fetch: async (url, init) => {
    sent = JSON.parse(init.body);
    return new Response(JSON.stringify({choices: [{finish_reason: 'stop', message: {content: JSON.stringify({status: 'ok', card: {...manualUnit(), name: '模型名字', cost: 99, attack: 99, abilities: [{trigger: 'on_play', effects: [{op: 'damage', target: 'enemy_hq', amount: 4}]}]}, assumptions: [], explanation: ''})}}]}), {status: 200});
  }});
  const returned = await provider.generate({kind: 'card', catalog: [], context: {source_text: '登场对敌方总部造成4点伤害', card_blueprint: blueprint}, signal: new AbortController().signal, onAttempt: async () => { attempts++; }});
  assert.equal(attempts, 1); assert.equal(returned.result.card.attack, 2); assert.equal(returned.result.card.cost, 3); assert.equal(returned.result.card.name, blueprint.name);
  assert.equal(returned.result.card.abilities[0].effects[0].amount, 4); assert.deepEqual(returned.result.card.keywords, blueprint.keywords);
  assert.match(sent.messages[0].content, /card_blueprint.*只读基础配置/); assert.match(sent.messages[0].content, /不得用基础数值替代技能数值/);
});

test('keyword registration auto-resume retains player blueprint and selected guard', async t => {
  const blueprint = artilleryBlueprint({keywords: [{id: 'core.guard', version: 1, params: {}}], abilities: [{trigger: 'own_turn_end', effects: [{op: 'heal', target: 'own_hq', amount: 2}]}]});
  const provider = scriptedProvider([{status: 'needs_keyword_registration', proposals: [{name: '桥接补给', description: '登场抽牌', requested_behavior: '登场抽牌'}], questions: []}, {status: 'ok', card: {...manualUnit(), keywords: [{id: 'custom.blueprint_supply', version: 1, params: {amount: 1}}]}, assumptions: [], explanation: ''}]);
  const {request} = await setup(t, {provider});
  const source = '额外带桥接补给';
  const start = await request('/v1/card-generations', generationBody({source_text: source, card_blueprint: blueprint}));
  const parent = await complete(request, start.body.generation_id);
  const definition = await fixture('keywords/example_supply'); definition.id = 'custom.blueprint_supply'; definition.name = '桥接补给';
  const proposal = (await request('/v1/keyword-imports', {request_id: randomUUID(), definition, related_generation_id: parent.generation_id})).body;
  const approved = await request(`/v1/keyword-proposals/${proposal.proposal_id}/confirm`, {request_id: randomUUID(), expected_revision: 1, candidate_hash: proposal.candidate_hash});
  const ready = await complete(request, approved.body.resumed_generation_id);
  assert.equal(ready.status, 'ready'); assert.equal(ready.result.definition.cost, 3); assert.equal(ready.result.definition.unit_class, 'artillery');
  assert.deepEqual(ready.result.definition.keywords.map(ref => ref.id), ['core.guard', 'custom.blueprint_supply']); assert.deepEqual(provider.calls[1].context.card_blueprint, blueprint);
  assert.deepEqual(ready.result.definition.abilities, blueprint.abilities);
});

const drawAbility = (amount = 1, trigger = 'on_play') => ({trigger, effects: [{op: 'draw', player: 'owner', amount}]});

test('fixed visual abilities validate all supported controls and compile locally without a provider', async t => {
  const provider = scriptedProvider([]), {request, app} = await setup(t, {provider});
  const abilities = [
    {trigger: 'on_play', effects: [{op: 'draw', player: 'owner', amount: 2}, {op: 'heal', target: 'own_hq', amount: 3}, {op: 'damage', target: 'enemy_hq', amount: 4}, {op: 'gain_kredits', amount: 1}]},
    {trigger: 'own_turn_start', effects: [{op: 'modify_stats', target: 'self', attack_delta: 1, health_delta: 2, duration: 'battle'}]},
    drawAbility(1, 'own_turn_end'),
    {trigger: 'on_death', effects: [{op: 'gain_kredits', amount: 1}]}
  ];
  const blueprint = artilleryBlueprint({abilities});
  assert.equal(canonical(validateCardBlueprint(blueprint, app.service.store.state.keywords)), canonical(blueprint));
  const preview = await request('/v1/card-drafts', {request_id: randomUUID(), definition: {...manualUnit(), ...blueprint, appearance: {emblem: 'artillery'}}});
  assert.equal(preview.status, 201); assert.deepEqual(preview.body.result.definition.abilities, abilities);
  assert.equal(provider.calls.length, 0); assert.equal((await request('/v1/cards')).body.cards.length, 0);
  const order = artilleryBlueprint({kind: 'order', unit_class: null, attack: 0, health: 0, operation_cost: 0, abilities: [drawAbility(3)]});
  assert.doesNotThrow(() => validateCardBlueprint(order, app.service.store.state.keywords));
  const emptyOrder = {...order, abilities: []};
  assert.doesNotThrow(() => validateCardBlueprint(emptyOrder, app.service.store.state.keywords)); // The model may supply its first effect.
  assert.throws(() => compileCard({...manualUnit(), ...emptyOrder, appearance: {emblem: 'order'}}, app.service.store.state.keywords)); // A final empty order is never playable.
});

test('invalid fixed abilities and expanded budgets are rejected before creating or charging a generation', async t => {
  const provider = scriptedProvider([]), {request, app} = await setup(t, {provider});
  const supply = validateKeyword(await fixture('keywords/example_supply'));
  await app.service.store.transaction(state => { state.keywords['example.supply@1'] = {...supply, registry_status: 'approved'}; });
  const invalid = [
    artilleryBlueprint({abilities: null}), artilleryBlueprint({abilities: 'draw 1'}),
    artilleryBlueprint({abilities: [drawAbility(0)]}), artilleryBlueprint({abilities: [drawAbility(11)]}),
    artilleryBlueprint({abilities: [drawAbility('2')]}),
    artilleryBlueprint({abilities: [{trigger: 'unsupported', effects: [{op: 'draw', player: 'owner', amount: 1}]}]}),
    artilleryBlueprint({abilities: [{trigger: 'on_play', effects: []}]}),
    artilleryBlueprint({abilities: [{trigger: 'on_play', effects: [{op: 'damage', target: 'chosen', amount: 1}]}]}),
    artilleryBlueprint({abilities: [{trigger: 'on_play', effects: [{op: 'summon', token_id: 'unit', amount: 1, row: 'support'}]}]}),
    artilleryBlueprint({abilities: [{trigger: 'on_death', effects: [{op: 'heal', target: 'self', amount: 1}]}]}),
    artilleryBlueprint({abilities: [{trigger: 'on_play', effects: [{op: 'modify_stats', target: 'self', attack_delta: 0, health_delta: 0, duration: 'battle'}]}]}),
    artilleryBlueprint({kind: 'order', unit_class: null, attack: 0, health: 0, abilities: [drawAbility(1, 'own_turn_end')]}),
    artilleryBlueprint({kind: 'order', unit_class: null, attack: 0, health: 0, abilities: [{trigger: 'on_play', effects: [{op: 'heal', target: 'self', amount: 1}]}]}),
    artilleryBlueprint({abilities: Array.from({length: 9}, () => drawAbility())}),
    artilleryBlueprint({abilities: Array.from({length: 7}, () => ({trigger: 'on_play', effects: Array.from({length: 4}, () => ({op: 'draw', player: 'owner', amount: 1}))}))}),
    artilleryBlueprint({abilities: Array.from({length: 8}, () => drawAbility()), keywords: [{id: 'example.supply', version: 1, params: {amount: 1}}]})
  ];
  for (const card_blueprint of invalid) {
    const rejected = await request('/v1/card-generations', generationBody({source_text: '补充其他效果', card_blueprint}));
    assert.ok(rejected.status >= 400, JSON.stringify(card_blueprint));
  }
  assert.equal(provider.calls.length, 0); assert.equal(Object.keys(app.service.store.state.generations).length, 0);
  assert.equal(Object.keys(app.service.store.state.limits).length, 0);
});

test('fixed ability merge preserves ordered player effects and is idempotent across both application layers', () => {
  const fixed = {trigger: 'on_play', effects: [{op: 'draw', player: 'owner', amount: 2}, {op: 'gain_kredits', amount: 1}]};
  const extra = {trigger: 'own_turn_end', effects: [{op: 'heal', target: 'own_hq', amount: 3}]};
  const blueprint = artilleryBlueprint({abilities: [fixed]});
  const once = applyCardBlueprint({...manualUnit(), abilities: [extra, structuredClone(fixed), structuredClone(extra)]}, blueprint);
  assert.deepEqual(once.abilities, [fixed, extra]);
  assert.deepEqual(applyCardBlueprint(once, blueprint), once);
  assert.deepEqual(applyCardBlueprint(manualUnit(), blueprint).abilities, [fixed]);
  once.abilities[0].effects[0].amount = 1;
  assert.equal(blueprint.abilities[0].effects[0].amount, 2);
  // Deliberate player repeats remain exactly as configured, rather than silently changing their effect.
  const repeated = artilleryBlueprint({abilities: [fixed, structuredClone(fixed)]});
  assert.deepEqual(applyCardBlueprint(applyCardBlueprint(manualUnit(), repeated), repeated).abilities, repeated.abilities);
  const legacyCard = {...manualUnit(), abilities: [extra, structuredClone(extra)]};
  assert.deepEqual(applyCardBlueprint(legacyCard, artilleryBlueprint()).abilities, legacyCard.abilities);
});

test('model cannot change or partly repeat a fixed effect under the same trigger and target', () => {
  const blueprint = artilleryBlueprint({abilities: [drawAbility(1)]});
  for (const abilities of [
    [drawAbility(2)],
    [{trigger: 'on_play', effects: [{op: 'draw', player: 'owner', amount: 1}, {op: 'heal', target: 'own_hq', amount: 1}]}],
    [{trigger: 'on_play', effects: [{op: 'draw', player: 'owner', amount: 1}, {op: 'draw', player: 'owner', amount: 1}]}]
  ]) assert.throws(() => applyCardBlueprint({...manualUnit(), abilities}, blueprint), error => error.code === 'BLUEPRINT_ABILITY_CONFLICT');
  const differentTarget = {trigger: 'on_play', effects: [{op: 'draw', player: 'opponent', amount: 1}]};
  assert.deepEqual(applyCardBlueprint({...manualUnit(), abilities: [differentTarget, drawAbility(2, 'own_turn_end')]}, blueprint).abilities, [drawAbility(1), differentTarget, drawAbility(2, 'own_turn_end')]);
});

test('official provider and service together add fixed abilities exactly once without any real model request', async t => {
  let sent, upstreamCalls = 0;
  const fixed = drawAbility(2), extra = {trigger: 'on_play', effects: [{op: 'heal', target: 'own_hq', amount: 1}]};
  const blueprint = artilleryBlueprint({abilities: [fixed]});
  const provider = new DeepSeekProvider({apiKey: 'test-only-not-real', fetch: async (_url, init) => {
    sent = JSON.parse(init.body); upstreamCalls++;
    return new Response(JSON.stringify({choices: [{finish_reason: 'stop', message: {content: JSON.stringify({status: 'ok', card: {...manualUnit(), attack: 99, abilities: [fixed, extra]}, assumptions: [], explanation: ''})}}]}));
  }});
  const {request} = await setup(t, {provider});
  const start = await request('/v1/card-generations', generationBody({source_text: '额外恢复1点生命', card_blueprint: blueprint}));
  const ready = await complete(request, start.body.generation_id);
  assert.equal(ready.status, 'ready'); assert.deepEqual(ready.result.definition.abilities, [fixed, extra]);
  assert.equal(ready.result.definition.attack, 2); assert.equal(upstreamCalls, 1);
  assert.match(sent.messages[0].content, /card\.abilities.*只填写额外能力/);
  assert.deepEqual(JSON.parse(sent.messages[1].content).card_blueprint.abilities, [fixed]);
  assert.equal((await request('/v1/cards')).body.cards.length, 0);
});

test('fixed abilities survive clarification ancestry and cannot be changed in a continuation', async t => {
  const blueprint = artilleryBlueprint({abilities: [drawAbility(2)]});
  const provider = scriptedProvider([{status: 'needs_clarification', questions: [{id: 'time', question: '何时获得资源？', options: []}]}, {status: 'ok', card: {...manualUnit(), abilities: [{trigger: 'own_turn_end', effects: [{op: 'gain_kredits', amount: 1}]}]}, assumptions: [], explanation: ''}]);
  const {request} = await setup(t, {provider});
  const source_text = '额外获得资源';
  const first = await request('/v1/card-generations', generationBody({source_text, card_blueprint: blueprint}));
  const waiting = await complete(request, first.body.generation_id);
  const continuation = {source_text, parent_generation_id: waiting.generation_id, clarification_answers: [{question_id: waiting.result.questions[0].id, answer: '己方回合结束时，获得1点'}]};
  const changed = await request('/v1/card-generations', generationBody({...continuation, card_blueprint: {...blueprint, abilities: [drawAbility(3)]}}));
  assert.equal(changed.status, 409); assert.equal(provider.calls.length, 1);
  const second = await request('/v1/card-generations', generationBody(continuation));
  const ready = await complete(request, second.body.generation_id);
  assert.equal(ready.status, 'ready'); assert.deepEqual(ready.result.definition.abilities[0], blueprint.abilities[0]);
  assert.deepEqual(provider.calls[1].context.card_blueprint, blueprint);
});

test('final fixed plus generated plus expanded keyword budget is enforced after generation', async t => {
  const provider = scriptedProvider([{status: 'ok', card: {...manualUnit(), keywords: [{id: 'example.supply', version: 1, params: {amount: 1}}]}, assumptions: [], explanation: ''}]);
  const {request, app} = await setup(t, {provider});
  const supply = validateKeyword(await fixture('keywords/example_supply'));
  await app.service.store.transaction(state => { state.keywords['example.supply@1'] = {...supply, registry_status: 'approved'}; });
  const card_blueprint = artilleryBlueprint({abilities: ['on_play', 'own_turn_start', 'own_turn_end', 'on_death', 'opponent_turn_start', 'opponent_turn_end', 'on_summon', 'on_attack'].map(trigger => drawAbility(1, trigger))});
  const start = await request('/v1/card-generations', generationBody({source_text: '额外带补给', card_blueprint}));
  assert.equal(start.status, 202);
  const failed = await complete(request, start.body.generation_id);
  assert.equal(failed.status, 'failed'); assert.equal(failed.error.code, 'INVALID_SCHEMA');
  assert.equal(Object.keys(app.service.store.state.drafts).length, 0);
});
