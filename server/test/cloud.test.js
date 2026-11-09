import {FACTION_ID, seedFactions} from './faction_fixture.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createApp} from '../src/index.js';
import {hash} from '../src/codec.js';
import {registryHash} from '../src/validation.js';

const INVITE = 'test-only-central-invite-1234567890';
const provider = {configured: false, model: 'test-only', async generate() { throw new Error('Cloud tests must not call a model'); }};
const unit = (name = '同步测试单位') => ({schema_version: '1.0.0', ruleset_version: 'frontline-1', name, faction_id:FACTION_ID, flavor_text: '', kind: 'unit', unit_class: 'infantry', cost: 2, operation_cost: 1, attack: 2, health: 3, keywords: [], play_target: null, abilities: [], tokens: [], appearance: {emblem: 'infantry'}});
const keyword = () => ({schema_version: '1.0.0', ruleset_version: 'frontline-1', id: 'example.supply', version: 1, name: '补给测试词条', aliases: ['supply-test'], description: '部署时抽指定数量的牌。', parameters: {amount: {type: 'integer', minimum: 1, maximum: 3}}, implementation: {kind: 'template', abilities: [{trigger: 'on_play', effects: [{op: 'draw', player: 'owner', amount: {param: 'amount'}}]}]}});
const syncBody = (definitions, keywords = []) => ({request_id: randomUUID(), cards: definitions.map((definition, i) => ({local_card_id: `local-${i}`, definition, definition_hash: hash(definition)})), keywords});

async function setup(t, options = {}) {
  const dataDir = await mkdtemp(join(tmpdir(), 'chao-central-'));
  let app = await createApp({centralMode: true, inviteToken: INVITE, matches: false, host: '127.0.0.1', port: 0, provider, dataDir, ...options});
  await seedFactions(app.service.store);
  let address = await app.listen(), base = `http://127.0.0.1:${address.port}`, closed = false;
  const request = async (path, body, token, method = body === undefined ? 'GET' : 'POST', extraHeaders = {}) => {
    const response = await fetch(base + path, {method, headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {}), ...extraHeaders}, ...(body !== undefined ? {body: typeof body === 'string' ? body : JSON.stringify(body)} : {})});
    return {status: response.status, body: await response.json()};
  };
  const login = async name => {
    const result = await request('/v1/sessions', {invite_code: INVITE, display_name: name});
    assert.equal(result.status, 201); return result.body;
  };
  const restart = async () => {
    await app.close();
    app = await createApp({centralMode: true, inviteToken: INVITE, matches: false, host: '127.0.0.1', port: 0, provider, dataDir, ...options});
    address = await app.listen(); base = `http://127.0.0.1:${address.port}`;
    return app;
  };
  t.after(async () => { if (!closed) { closed = true; await app.close(); } await rm(dataDir, {recursive: true, force: true}); });
  return {app, request, login, restart, dataDir};
}

test('central startup requires invitation and TLS for non-loopback; default local mode remains separate', async () => {
  await assert.rejects(createApp({centralMode: true, inviteToken: 'short', matches: false}), /REGISTRATION_INVITE_TOKEN/);
  await assert.rejects(createApp({centralMode: true, inviteToken: INVITE, host: '0.0.0.0', matches: false}), /TLS_CERT_FILE/);
  await assert.rejects(createApp({centralMode: true, inviteToken: INVITE, tlsCertFile: 'unused', tlsKeyFile: '', matches: false}), /configured together/);
});

test('central anonymous access is limited to minimal health and invitation sessions', async t => {
  const {request} = await setup(t);
  const health = await request('/health');
  assert.equal(health.status, 200);
  assert.deepEqual(Object.keys(health.body).sort(), ['card_series', 'configured', 'mode', 'model', 'ok', 'rules', 'transport']);
  assert.equal(health.body.rules.revision, 'mechanics-49');
  assert.ok(health.body.rules.operations.includes('set_attack_limit'));
  assert.equal(health.body.mode, 'central');
  for (const path of ['/v1/health', '/v1/me', '/v1/cards', '/v1/keywords', '/v1/rooms']) assert.equal((await request(path)).status, 401, path);
  assert.equal((await request('/v1/card-sync', syncBody([]))).status, 401);
  assert.equal((await request('/v1/sessions', {invite_code: 'wrong', display_name: '测试玩家'})).status, 401);
  assert.equal((await request('/health', undefined, undefined, 'GET', {Origin: 'https://other.example'})).status, 403);
});

test('session tokens are unique 256-bit credentials persisted as hashes; account metadata is isolated', async t => {
  const {request, login, dataDir} = await setup(t);
  const a = await login('玩家甲'), b = await login('玩家乙');
  assert.match(a.access_token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(Buffer.from(a.access_token, 'base64url').length, 32);
  assert.notEqual(a.access_token, b.access_token); assert.notEqual(a.owner_id, b.owner_id);
  const me=(await request('/v1/me',undefined,a.access_token)).body;assert.deepEqual(me,{owner_id:a.owner_id,display_name:'玩家甲',avatar:'commander',avatar_color:'#c5a36b',bio:'',created_at:me.created_at});assert(Number.isFinite(Date.parse(me.created_at)));
  assert.equal((await request('/v1/me', undefined, 'x'.repeat(43))).status, 401);
  assert.equal((await request('/v1/sessions', {invite_code: INVITE, display_name: '玩家', owner_id: a.owner_id})).status, 400);
  const disk = await readFile(join(dataDir, 'store.json'), 'utf8');
  assert.ok(!disk.includes(a.access_token) && !disk.includes(b.access_token) && !disk.includes(INVITE));
  const state = JSON.parse(disk); assert.equal(Object.keys(state.sessions).length, 2);
  assert.ok(Object.keys(state.sessions).every(key => /^[0-9a-f]{64}$/.test(key)));
});

test('published cards are shared but prompts, jobs and revision writes remain private', async t => {
  const {app, request, login} = await setup(t);
  const a = await login('创作者'), b = await login('读者');
  const draft = await request('/v1/card-drafts', {request_id: randomUUID(), definition: unit()}, a.access_token);
  assert.equal(draft.status, 201);
  const jobId = randomUUID();
  await app.service.store.transaction(state => {
    state.drafts[draft.body.result.draft_id].provenance = {source_kind: 'model', source_text: 'PRIVATE PLAYER PROMPT', provider_request_id: 'PRIVATE PROVIDER ID'};
    state.generations[jobId] = {owner_id: a.owner_id, generation_id: jobId, status: 'needs_clarification', result: {questions: []}};
  });
  const stored = await request('/v1/cards', {request_id: randomUUID(), draft_id: draft.body.result.draft_id, draft_hash: draft.body.result.draft_hash}, a.access_token);
  assert.equal(stored.status, 201);
  const otherView = await request('/v1/cards', undefined, b.access_token), ownView = await request('/v1/cards', undefined, a.access_token);
  assert.equal(otherView.body.cards.length, 1);
  assert.equal(otherView.body.cards[0].owned_by_me, false); assert.equal(ownView.body.cards[0].owned_by_me, true);
  for (const field of ['provenance', 'owner_id', 'source_text', 'provider_request_id']) assert.ok(!Object.hasOwn(otherView.body.cards[0], field));
  assert.ok(!JSON.stringify(otherView.body).includes('PRIVATE'));
  assert.equal((await request(`/v1/cards/${stored.body.card_id}?revision=1`, undefined, b.access_token)).status, 200);
  assert.equal((await request(`/v1/card-generations/${jobId}`, undefined, b.access_token)).status, 404);
  const foreignDraft = await request('/v1/card-drafts', {request_id: randomUUID(), definition: unit('自己的草稿')}, b.access_token);
  const attempt = await request(`/v1/cards/${stored.body.card_id}/revisions`, {request_id: randomUUID(), base_revision: 1, draft_id: foreignDraft.body.result.draft_id, draft_hash: foreignDraft.body.result.draft_hash}, b.access_token);
  assert.equal(attempt.status, 404);
});

test('offline sync atomically registers templates, compiles cards, deduplicates and retries idempotently', async t => {
  const {app, request, login} = await setup(t);
  const a = await login('同步甲'), b = await login('同步乙');
  const definition = unit(); definition.keywords = [{id: 'example.supply', version: 1, params: {amount: 2}}];
  const body = syncBody([definition, definition], [keyword()]);
  const first = await request('/v1/card-sync', body, a.access_token);
  assert.equal(first.status, 200); assert.equal(first.body.cards.length, 1); assert.equal(first.body.mappings.length, 2);
  assert.equal(first.body.mappings[0].card_id, first.body.mappings[1].card_id);
  assert.equal(first.body.cards[0].definition_hash, hash(definition)); assert.equal(first.body.cards[0].owned_by_me, true);
  assert.equal(first.body.keyword_registry_hash, registryHash(app.service.store.state.keywords));
  assert.deepEqual((await request('/v1/card-sync', body, a.access_token)).body, first.body);
  assert.equal(app.service.store.state.sync_limits[a.owner_id].length, 1);
  const collision = structuredClone(body); collision.cards[0].local_card_id = 'changed';
  assert.equal((await request('/v1/card-sync', collision, a.access_token)).status, 409);
  const shared = await request('/v1/card-sync', syncBody([definition], [keyword()]), b.access_token);
  assert.equal(shared.status, 200); assert.equal(shared.body.cards[0].card_id, first.body.cards[0].card_id); assert.equal(shared.body.cards[0].owned_by_me, false);
  assert.equal(Object.keys(app.service.store.state.cards).length, 1);
  const snapshot = app.service.store.getCard(first.body.cards[0].card_id, 1); snapshot.definition.attack = 20;
  assert.equal(app.service.store.getCard(snapshot.card_id).definition.attack, 2);
  const keywords = app.service.store.listKeywords(); keywords[0].definition.name = 'mutated';
  assert.notEqual(app.service.store.listKeywords()[0].definition.name, 'mutated');
});

test('sync validation failure rolls back all cards, newly registered keywords and idempotency records', async t => {
  const {app, request, login} = await setup(t);
  const account = await login('原子同步');
  const body = syncBody([unit('有效一'), unit('有效二')], [keyword()]); body.cards[1].definition_hash = '0'.repeat(64);
  const result = await request('/v1/card-sync', body, account.access_token);
  assert.equal(result.status, 422); assert.equal(result.body.error.code, 'HASH_MISMATCH');
  assert.equal(Object.keys(app.service.store.state.cards).length, 0);
  assert.ok(!app.service.store.state.keywords['example.supply@1']);
  assert.ok(!app.service.store.state.idempotency[`${account.owner_id}:${body.request_id}`]);
  assert.ok(!app.service.store.state.sync_limits[account.owner_id]);
});

test('sync freezes exact keyword versions and rejects altered builtins, bad ranges and unknown fields', async t => {
  const {app, request, login} = await setup(t);
  const account = await login('不可变目录');
  const first = await request('/v1/card-sync', syncBody([], [keyword()]), account.access_token); assert.equal(first.status, 200);
  const changed = keyword(); changed.parameters.amount.maximum = 2;
  assert.equal((await request('/v1/card-sync', syncBody([], [changed]), account.access_token)).status, 409);
  const builtin = structuredClone(app.service.store.state.keywords['core.blitz@1'].definition); builtin.description += 'changed';
  assert.equal((await request('/v1/card-sync', syncBody([], [builtin]), account.access_token)).status, 409);
  const invalid = keyword(); invalid.id = 'example.bad'; invalid.parameters.amount.maximum = 11;
  assert.equal((await request('/v1/card-sync', syncBody([], [invalid]), account.access_token)).status, 422);
  const badCard = unit(); badCard.server_trusted = true;
  assert.equal((await request('/v1/card-sync', syncBody([badCard]), account.access_token)).status, 422);
  assert.equal(app.service.store.state.keywords['example.supply@1'].definition.parameters.amount.maximum, 3);
});

test('central sync and registration enforce bounded counts, request bytes and independent quotas', async t => {
  const {request, login} = await setup(t, {syncMinuteLimit: 1});
  const account = await login('限额测试');
  assert.equal((await request('/v1/card-sync', syncBody(Array.from({length: 101}, (_, i) => unit(`牌${i}`))), account.access_token)).status, 400);
  const huge = JSON.stringify({request_id: randomUUID(), cards: [], keywords: [], padding: 'x'.repeat(262144)});
  assert.equal((await request('/v1/card-sync', huge, account.access_token)).status, 413);
  const body = syncBody([]);
  assert.equal((await request('/v1/card-sync', body, account.access_token)).status, 200);
  assert.equal((await request('/v1/card-sync', body, account.access_token)).status, 200);
  assert.equal((await request('/v1/card-sync', syncBody([]), account.access_token)).status, 429);
});

test('failed invitation attempts count toward persistent registration quota', async t => {
  const {request, restart} = await setup(t, {registrationLimit: 1});
  assert.equal((await request('/v1/sessions', {invite_code: 'wrong', display_name: '玩家'})).status, 401);
  await restart();
  assert.equal((await request('/v1/sessions', {invite_code: INVITE, display_name: '玩家'})).status, 429);
});

test('cloud identity, catalog and exact synchronization mappings survive process restart', async t => {
  const {request, login, restart} = await setup(t);
  const account = await login('持久账户'), body = syncBody([unit()]);
  const before = await request('/v1/card-sync', body, account.access_token); assert.equal(before.status, 200);
  await restart();
  assert.equal((await request('/v1/me', undefined, account.access_token)).body.owner_id, account.owner_id);
  const library = await request('/v1/cards', undefined, account.access_token); assert.equal(library.body.cards[0].card_id, before.body.cards[0].card_id);
  assert.deepEqual((await request('/v1/card-sync', body, account.access_token)).body, before.body);
});

test('central match routes are integrated after account authentication and remain lazy without Godot', async t => {
  const {app, request, login} = await setup(t, {matches: undefined});
  const account = await login('房间玩家');
  assert.ok(app.matches);
  assert.equal((await request('/v1/rooms')).status, 401);
  assert.deepEqual((await request('/v1/rooms', undefined, account.access_token)).body, {rooms: []});
  assert.equal(app.matches.rooms.size, 0);
  // No user may choose their authenticated owner via arbitrary request fields.
  const bad = await request('/v1/rooms', {owner: 'someone-else', request_id: randomUUID(), deck: []}, account.access_token);
  assert.equal(bad.status, 400);
});
