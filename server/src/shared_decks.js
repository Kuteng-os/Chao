import {mainSin} from "./sins.js";
import {headquartersFor,headquartersEnvelope} from './headquarters.js';
import {resolveCard} from './derived_cards.js';
import {randomUUID} from 'node:crypto';
import {fail, hash} from './codec.js';
import {fields} from './service.js';
import {DECK_SIZE, checkDeckCopies, deckFactions, deckComposition} from './deck_rules.js';
import {compileCard} from './validation.js';
import {publicCard} from './cloud_catalog.js';
import {authorFor} from './authorship.js';
import {Factions} from './factions.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[0-9a-f]{64}$/;
function recordsFor(state, refs, followLatest = false) {
  if (!Array.isArray(refs) || refs.length !== DECK_SIZE) fail('INVALID_DECK', '共享牌组需要 40 张卡牌，总部另计。', 422);
  const records = refs.map(ref => {
    fields(ref, ['card_id', 'revision', 'definition_hash']);
    if (typeof ref.card_id !== 'string' || !UUID.test(ref.card_id) || !Number.isSafeInteger(ref.revision) || ref.revision < 1 || typeof ref.definition_hash !== 'string' || !HASH.test(ref.definition_hash)) fail('INVALID_DECK', '卡牌版本引用无效。', 422);
    const card = resolveCard(state,ref.card_id,ref.revision);
    if (!card || card.definition_hash !== ref.definition_hash || hash(card.definition) !== ref.definition_hash) fail('INVALID_DECK', '牌组引用了未发布或不匹配的卡牌版本。', 422);
    return followLatest ? resolveCard(state,ref.card_id) ?? card : card;
  });
  const error = checkDeckCopies(records);
  if (error && !followLatest) fail('INVALID_DECK', error, 422);
  // Verify each frozen program once, never accept client-supplied definitions.
  for (const card of new Set(records)) {
    if (compileCard(card.definition, state.keywords).compiled_program_hash !== card.compiled_program_hash) fail('INVALID_DECK', '卡牌的冻结规则校验失败。', 422);
  }
  return records;
}

export class SharedDecks {
  constructor(service) { this.service = service; this.store = service.store; }
  summary(deck, owner, state = this.store.state) {
    return {deck_id: deck.deck_id, revision: deck.revision, name: deck.name, card_count: deck.cards.length, headquarters:structuredClone(deck.headquarters??null), main_sin:mainSin(deck.main_sin),ally_sin:mainSin(deck.ally_sin),main_faction_id:deck.main_faction_id??'', ally_faction_id:'', author: authorFor(state, deck.owner_id), owned_by_me: deck.owner_id === owner, published: deck.published, unavailable_reason:deck.unavailable_reason??'', updated_at: deck.updated_at};
  }
  list(owner = null, mine = false, cursor = '0') {
    if (!/^\d{1,8}$/.test(cursor)) fail('INVALID_REQUEST', '分页位置无效。', 400);
    const all = Object.values(this.store.state.shared_decks).filter(d => mine ? d.owner_id === owner : d.published).sort((a,b) => b.updated_at.localeCompare(a.updated_at) || a.deck_id.localeCompare(b.deck_id));
    const offset = Number(cursor), items = all.slice(offset, offset + 100);
    return {decks: items.map(d => this.summary(d, owner)), next_cursor: offset + 100 < all.length ? String(offset + 100) : null};
  }
  detail(id, owner = null) {
    const state = this.store.state, deck = state.shared_decks[id];
    if (!deck || (!deck.published && deck.owner_id !== owner)) fail('NOT_FOUND', '共享牌组不存在或已撤回。', 404);
    if(deck.unavailable_reason)fail("INVALID_DECK",deck.unavailable_reason,409);
    const records = recordsFor(state, deck.cards, true);
    const validation_error=checkDeckCopies(records)||deckComposition(records,state.factions,deck.main_sin,deck.ally_sin).error;
    const previousHQ=headquartersFor(state,deck.headquarters),candidate=previousHQ?resolveCard(state,previousHQ.card_id):null;
    const hq=candidate?.definition.kind==='hq'?candidate:previousHQ;
    const currentRefs=records.map(card=>({card_id:card.card_id,revision:card.revision,definition_hash:card.definition_hash}));
    const currentHQ=hq?{card_id:hq.card_id,revision:hq.revision,definition_hash:hq.definition_hash}:null;
    if(hq)records.push(hq);const bindings = new Set(records.flatMap(c => c.keyword_bindings.map(b => b.definition_hash)));
    const keywords = Object.values(state.keywords).filter(k => bindings.has(k.definition_hash)).map(k => ({definition: structuredClone(k.definition), definition_hash: k.definition_hash}));
    const ids=new Set([deck.main_faction_id,deck.ally_faction_id,...records.map(c=>c.definition.faction_id)]);
    const factions=[...ids].filter(id=>state.factions[id]).map(id=>new Factions(this.service).public(state.factions[id],owner,state));
    return {deck: {...this.summary(deck, owner), cards: currentRefs, headquarters:currentHQ, validation_error}, cards: [...new Set(records)].map(c => publicCard(c, owner, false, state)), keywords, factions};
  }
  publish(owner, body) {
    fields(body, ['request_id', 'name', 'cards'], ['main_sin','ally_sin','deck_id', 'expected_revision','main_faction_id','ally_faction_id','headquarters']);
    if (typeof body.name !== 'string' || !body.name.trim() || [...body.name.trim()].length > 40 || /[\p{Cc}\p{Cf}]/u.test(body.name)) fail('INVALID_REQUEST', '牌组名称需为 1 至 40 个字符。', 400);
    if (body.deck_id !== undefined && (!UUID.test(body.deck_id) || !Number.isSafeInteger(body.expected_revision) || body.expected_revision < 1)) fail('INVALID_REQUEST', '需要有效的牌组 ID 与版本。', 400);
    if (body.deck_id === undefined && body.expected_revision !== undefined) fail('INVALID_REQUEST', '新牌组无需指定版本。', 400);
    return this.service.idem(owner, 'publish-deck', body, state => {
      const existing = body.deck_id ? state.shared_decks[body.deck_id] : null;
      if (body.deck_id && (!existing || existing.owner_id !== owner)) fail('NOT_FOUND', '只能更新自己的共享牌组。', 404);
      if (existing && existing.revision !== body.expected_revision) fail('REVISION_CONFLICT', '共享牌组已更新，请重新读取后再上传。', 409);
      if (!existing && Object.values(state.shared_decks).filter(d => d.owner_id === owner).length >= 100) fail('RATE_LIMITED', '每个账号最多保存 100 个共享牌组。', 429);
      const records=recordsFor(state, body.cards);
      headquartersFor(state,body.headquarters);
      const selection=deckFactions(records,state.factions,body.main_faction_id??null,body.ally_faction_id??null);
      if(selection.error)fail('INVALID_FACTION',selection.error,422);
      const deck = {deck_id: existing?.deck_id || randomUUID(), revision: (existing?.revision || 0) + 1, name: body.name.trim(), cards: structuredClone(body.cards), owner_id: owner, published: true, updated_at: new Date().toISOString()};
      if(body.headquarters)deck.headquarters=structuredClone(body.headquarters);
      deck.main_sin=mainSin(body.main_sin===undefined?existing?.main_sin:body.main_sin);deck.ally_sin=mainSin(body.ally_sin===undefined?existing?.ally_sin:body.ally_sin);
      if(deck.ally_sin&&deck.ally_sin===deck.main_sin)fail('INVALID_SIN','初始罪孽与附属罪孽不能相同。',422);deck.main_faction_id=selection.main_faction_id;deck.ally_faction_id=selection.ally_faction_id;
      const composition=deckComposition(records,state.factions,deck.main_sin,deck.ally_sin);
      if(composition.error)fail('INVALID_DECK',composition.error,422);
      state.shared_decks[deck.deck_id] = deck;
      return this.summary(deck, owner, state);
    });
  }
  async withdraw(owner, id) {
    return this.store.transaction(state => {
      const deck = state.shared_decks[id];
      if (!deck || deck.owner_id !== owner) fail('NOT_FOUND', '只能撤回自己的共享牌组。', 404);
      if (deck.published) { deck.published = false; deck.revision++; deck.updated_at = new Date().toISOString(); }
      return this.summary(deck, owner, state);
    });
  }
}
