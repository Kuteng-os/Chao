import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createApp} from '../src/index.js';
import {canonical, hash} from '../src/codec.js';
import {applyCardBlueprint, compileCard, validateCardBlueprint, schemaCheck} from '../src/validation.js';
import {DeepSeekProvider, makePrompt} from '../src/provider.js';

function fixture() {
  const token = {token_id: 'fireball', name: '火球术', kind: 'order', cost: 1, operation_cost: 0, unit_class: null, attack: 0, health: 0, keywords: [], abilities: [{trigger: 'on_play', effects: [{op: 'damage', target: 'chosen', amount: 3}]}], play_target: {side: 'enemy', row: 'any'}};
  const blueprint = {name: '火焰大师', kind: 'unit', unit_class: 'bomber', cost: 3, operation_cost: 1, attack: 3, health: 2, keywords: [], abilities: [], tokens: [token], play_target: null, appearance: {emblem: 'bomber'}, rarity: 'standard', effect_mode: 'append'};
  const card = {schema_version: '1.0.0', ruleset_version: 'frontline-1', ...structuredClone(blueprint), flavor_text: '', abilities: [{trigger: 'own_turn_start', effects: [{op: 'create_card', token_id: 'fireball', amount: 1, player: 'owner'}]}]};
  delete card.effect_mode;
  return {token, blueprint, card};
}
const response = card => new Response(JSON.stringify({choices: [{finish_reason: 'stop', message: {reasoning_content: 'private model reasoning', content: JSON.stringify({status: 'ok', card, assumptions: [], explanation: ''})}}]}));
const input = blueprint => ({kind: 'card', catalog: [], context: {source_text: '己方每回合开始时，将1张衍生指令火球术加入手牌。', card_blueprint: blueprint}, signal: new AbortController().signal, onAttempt: async () => {}});

test('fireball echo with optional empty fields compiles on the first attempt without changing the fixed template', async () => {
  const {token, blueprint, card} = fixture(), original = canonical(blueprint);
  validateCardBlueprint(blueprint, {});
  card.tokens[0].counter_trigger = null;
  card.tokens[0].flavor_text = '';
  let calls = 0;
  const provider = new DeepSeekProvider({apiKey: 'test-only', fetch: async () => {calls++; return response(card);}});
  const result = await provider.generate(input(blueprint));
  assert.equal(calls, 1);
  const merged = applyCardBlueprint(result.result.card, blueprint);
  const compiled = compileCard(merged, {}), expected = compileCard(fixture().card, {});
  assert.equal(compiled.compiled_program_hash, expected.compiled_program_hash);
  assert.equal(hash(merged.tokens[0]), hash(token));
  assert.deepEqual(merged.tokens, [token]);
  assert.equal(canonical(blueprint), original);
  assert.deepEqual(merged.abilities, card.abilities);
  assert.match(compiled.rules_text, /己方回合开始/);
  assert(!JSON.stringify(result).includes('private model reasoning'));
  assert.match(makePrompt('card', [], blueprint), /card.tokens 默认只填写本次新增的模板/);
});

test('optional defaults compare equally for legacy units and counters but stored bytes remain exact', () => {
  const legacy = {token_id: 'child', name: '步兵', unit_class: 'infantry', attack: 1, health: 2, keywords: []};
  const counter = {token_id: 'child', name: '反制', kind: 'counter', cost: 1, unit_class: null, attack: 0, health: 0, keywords: [], counter_trigger: 'enemy_order_played', abilities: [{trigger: 'on_reveal', effects: [{op: 'cancel_action'}]}]};
  for (const fixed of [legacy, counter]) {
    const {blueprint, card} = fixture();
    blueprint.tokens = [fixed];
    const defaults = {kind: 'unit', cost: 1, operation_cost: fixed.kind === 'counter' ? 0 : 1, abilities: [], play_target: null, flavor_text: '', ...(fixed.kind === 'counter' ? {} : {counter_trigger: null})};
    card.tokens = [{...defaults, ...structuredClone(fixed)}];
    card.abilities[0].effects[0].token_id = 'child';
    assert.deepEqual(applyCardBlueprint(card, blueprint).tokens, [fixed]);
    blueprint.tokens = structuredClone(card.tokens);
    card.tokens = [structuredClone(fixed)];
    const merged = applyCardBlueprint(card, blueprint);
    assert.deepEqual(merged.tokens, blueprint.tokens);
    assert.doesNotThrow(() => compileCard(merged, {}));
  }
});

test('fixed template names, stats, effects, targets and unknown fields remain protected', () => {
  const changes = [t => t.name = '别的卡', t => t.cost = 2, t => t.operation_cost = 1, t => t.attack = 1,
    t => t.abilities[0].effects[0].amount = 4, t => t.play_target.side = 'ally', t => t.flavor_text = '新说明',
    t => t.keywords.push({id: 'core.guard', version: 1, params: {}}), t => t.counter_trigger = 'enemy_order_played',
    t => t.extra = null, t => t.abilities = null, t => delete t.unit_class];
  for (const change of changes) {
    const {blueprint, card} = fixture(), before = canonical(blueprint);
    change(card.tokens[0]);
    assert.throws(() => applyCardBlueprint(card, blueprint), error => error.code === 'BLUEPRINT_TOKEN_CONFLICT' && error.details[0].path.startsWith('/tokens/0/'));
    assert.equal(canonical(blueprint), before);
  }
  const {blueprint, card} = fixture();
  for (const malformed of [null, {}, [null], [[],], [{name: '缺ID'}], [card.tokens[0], card.tokens[0]]]) {
    assert.throws(() => applyCardBlueprint({...card, tokens: malformed}, blueprint), error => error.code === 'INVALID_SCHEMA');
  }
});

test('fixed templates may be omitted while new templates retain full schema validation', () => {
  const {blueprint, card, token} = fixture();
  card.tokens = [];
  assert.deepEqual(applyCardBlueprint(card, blueprint).tokens, [token]);
  const added = {...structuredClone(token), token_id: 'second', name: '另一张衍生牌'};
  card.tokens = [added];
  card.abilities[0].effects.push({op: 'create_card', token_id: 'second', amount: 1, player: 'owner'});
  const merged = applyCardBlueprint(card, blueprint);
  assert.deepEqual(merged.tokens, [token, added]);
  assert.doesNotThrow(() => compileCard(merged, {}));
  added.unknown = '';
  assert.throws(() => schemaCheck('card', applyCardBlueprint(card, blueprint)), error => error.code === 'INVALID_SCHEMA');
});

test('repair receives the real conflict path and can omit the fixed template on retry', async () => {
  const {blueprint, card, token} = fixture();
  let calls = 0;
  const provider = new DeepSeekProvider({apiKey: 'test-only', fetch: async (_url, init) => {
    calls++;
    const candidate = structuredClone(card);
    if (calls === 1) candidate.tokens[0].abilities[0].effects[0].amount = 4;
    else {
      const repair = JSON.parse(JSON.parse(init.body).messages.at(-1).content);
      assert.equal(repair.validation_errors[0].code, 'BLUEPRINT_TOKEN_CONFLICT');
      assert.equal(repair.validation_errors[0].path, '/tokens/0/abilities/0/effects/0/amount');
      assert.match(repair.validation_errors[0].message, /fireball/);
      candidate.tokens = [];
    }
    return response(candidate);
  }});
  const result = await provider.generate(input(blueprint));
  assert.equal(calls, 2);
  assert.deepEqual(result.result.card.tokens, [token]);
  assert.doesNotThrow(() => compileCard(result.result.card, {}));
});

test('exhausted repairs report bounded actionable diagnostics without provider reasoning', async () => {
  const {blueprint, card} = fixture();
  card.tokens[0].cost = 2;
  let calls = 0;
  const provider = new DeepSeekProvider({apiKey: 'test-only', fetch: async () => {calls++; return response(card);}});
  await assert.rejects(provider.generate(input(blueprint)), error => {
    assert.equal(error.code, 'INVALID_MODEL_OUTPUT');
    assert.match(error.message, /火球术/);
    assert.match(error.message, /\/tokens\/0\/cost/);
    assert.equal(error.details[0].code, 'BLUEPRINT_TOKEN_CONFLICT');
    assert(!JSON.stringify(error).includes('private model reasoning'));
    return true;
  });
  assert.equal(calls, 2);
});

test('official adapter and HTTP service append the fireball effect once and keep publication explicit', async t => {
  const {blueprint, card, token} = fixture();
  blueprint.abilities = [{trigger: 'on_play', effects: [{op: 'draw', player: 'owner', amount: 1}]}];
  card.tokens[0].counter_trigger = null;
  card.tokens[0].flavor_text = '';
  const provider = new DeepSeekProvider({apiKey: 'test-only', fetch: async () => response(card)});
  const dataDir = await mkdtemp(join(tmpdir(), 'frontline-token-'));
  const app = await createApp({dataDir, port: 0, provider});
  t.after(async () => {await app.close(); await rm(dataDir, {recursive: true, force: true});});
  const address = await app.listen(), base = `http://127.0.0.1:${address.port}`;
  const response_ = await fetch(base + '/v1/card-generations', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({request_id: randomUUID(), editor_revision: 1, source_text: input(blueprint).context.source_text, clarification_answers: [], schema_version: '1.0.0', ruleset_version: 'frontline-1', card_blueprint: blueprint})});
  assert.equal(response_.status, 202);
  const {generation_id} = await response_.json();
  let job;
  for (let n = 0; n < 200; n++) {
    job = await (await fetch(base + '/v1/card-generations/' + generation_id)).json();
    if (!['queued', 'running'].includes(job.status)) break;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.equal(job.status, 'ready', JSON.stringify(job));
  assert.deepEqual(job.result.definition.tokens, [token]);
  assert.deepEqual(job.result.definition.abilities, [...blueprint.abilities, ...card.abilities]);
  assert.equal(Object.keys(app.service.store.state.cards).length, 0);
});
