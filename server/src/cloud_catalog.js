import {cardSeries,currentCardSeries,seriesCatalog} from './card_series.js';
import {latestCards,allDerivedCards} from './derived_cards.js';
import {validateMedia} from './card_media.js';
import {archived,lifecycleSnapshot,contentState,assertKeywordAvailable} from './content_lifecycle.js';
import {randomUUID} from 'node:crypto';
import {canonical, fail} from './codec.js';
import {fields} from './service.js';
import {compileCard, validateKeyword, registryHash, registryEntries, rulesText, cardPresentation} from './validation.js';

import {authorFor} from './authorship.js';
import {isAdmin} from './account_roles.js';
import {requireCardFaction} from './factions.js';

const HASH = /^[0-9a-f]{64}$/;
const CARD_FIELDS = ['card_id', 'revision', 'definition', 'definition_hash', 'canonical_definition', 'keyword_bindings', 'compiled_program_hash', 'compiler_version', 'interpreter_version', 'rules_text', 'created_at', 'art', 'token_art', 'derived_from', 'available_revisions'];

/** Explicit public projection: author prompts and job metadata never enter shared responses. */
export function publicCard(card, owner, admin = false, state = {}) {
  const result = Object.fromEntries(CARD_FIELDS.filter(key => Object.hasOwn(card, key)).map(key => [key, structuredClone(card[key])]));
  // Derived display text follows current terminology without rewriting frozen card revisions.
  Object.assign(result,cardPresentation(card.definition,state.keywords??{},card.compiled_program?.expanded_definition??card.definition));
  result.series = cardSeries(card);
  result.owned_by_me = card.owner_id === owner;
  result.can_edit = result.owned_by_me || admin;
  result.author=authorFor(state,card.owner_id);
  result.archived=Boolean(card.derived_from?.retired)||archived(state,"cards",card.derived_from?.card_id??card.card_id);
  return result;
}

export class CloudCatalog {
  constructor(service, options = {}) {
    this.service = service;
    this.store = service.store;
    this.syncMinuteLimit = options.syncMinuteLimit ?? 10;
    this.maxCardsPerOwner = options.maxCardsPerOwner ?? 10000;
    this.maxKeywordsPerOwner = options.maxKeywordsPerOwner ?? 2048;
  }

  cards(owner) {
    return {card_series:seriesCatalog(this.store.state),lifecycle:lifecycleSnapshot(this.store.state), cards: latestCards(this.store.state).map(card => publicCard(card, owner, isAdmin(this.store.state,owner), this.store.state))};
  }

  card(owner, id, revision) {
    const card = this.store.getCard(id, revision);
    if (!card) fail('NOT_FOUND', '未找到此卡牌或修订。', 404);
    return publicCard(card, owner, isAdmin(this.store.state,owner), this.store.state);
  }

  async sync(owner, body) {
    fields(body, ['request_id', 'cards', 'keywords']);
    if (!Array.isArray(body.cards) || body.cards.length > 100 || !Array.isArray(body.keywords) || body.keywords.length > 256) fail('INVALID_REQUEST', '每批最多同步 100 张卡牌和 256 个词条。', 400);
    if (Buffer.byteLength(canonical(body), 'utf8') > 262144) fail('INPUT_TOO_LONG', '同步请求超过 256 KiB。', 413);
    const localIds = new Set();
    for (const card of body.cards) {
      fields(card, ['local_card_id', 'definition', 'definition_hash']);
      if (typeof card.local_card_id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(card.local_card_id) || localIds.has(card.local_card_id)) fail('INVALID_REQUEST', '本地卡牌 ID 无效或重复。', 400);
      if (typeof card.definition_hash !== 'string' || !HASH.test(card.definition_hash)) fail('INVALID_REQUEST', '卡牌哈希格式无效。', 400);
      localIds.add(card.local_card_id);
    }
    return this.service.idem(owner, 'central-card-sync', body, state => {
      const now = Date.now();
      const recent = (state.sync_limits[owner] || []).filter(time => now - time < 60000);
      if (recent.length >= this.syncMinuteLimit) fail('RATE_LIMITED', '同步过于频繁，请稍后继续。', 429);
      state.sync_limits[owner] = [...recent, now];
      let ownedKeywords = Object.values(state.keywords).filter(entry => entry.owner_id === owner).length;
      const workBudget={remaining:250000};
      for (const input of body.keywords) {
        const checked = validateKeyword(input, {allowBuiltin: true,workBudget});
        const definition = checked.definition, id = `${definition.id}@${definition.version}`;
        assertKeywordAvailable(state,definition.id);
        const existing = state.keywords[id];
        if (existing) {
          if (existing.definition_hash !== checked.definition_hash || canonical(existing.definition) !== canonical(definition)) fail('KEYWORD_VERSION_CONFLICT', `词条 ${id} 已有不同内容，不能覆盖。`, 409);
          if (existing.registry_status !== 'approved') fail('KEYWORD_NOT_REGISTERED', `词条 ${id} 目前不可用于新卡牌。`, 409);
          continue;
        }
        if (definition.implementation.kind === 'builtin') fail('KEYWORD_VERSION_CONFLICT', '内置词条必须与服务器已登记定义完全一致。', 409);
        if (Object.values(state.keywords).some(entry => entry.definition.id === definition.id && entry.owner_id !== owner)) fail('KEYWORD_VERSION_CONFLICT', '只能由原作者为已有词条登记新版本。', 409);
        this.checkKeywordName(state, definition);
        if (++ownedKeywords > this.maxKeywordsPerOwner) fail('RATE_LIMITED', '当前玩家同步的词条数量已达到上限。', 429);
        state.keywords[id] = {...checked, owner_id: owner, registry_status: 'approved', approval_source: 'automatic_validation', confirmation_source: 'local_sync', validator_version: 'validator-1', approved_at: new Date(now).toISOString()};
      }
      const byHash = new Map();
      let ownedCards = 0;
      for (const id of Object.keys(state.cards).sort()) {
        const versions = state.cards[id];
        if (versions[0]?.owner_id === owner) ownedCards++;
        // Exact published historical revisions are valid frozen references too.
        for (const card of [...versions].reverse()) if (!byHash.has(card.definition_hash)) byHash.set(card.definition_hash, card);
      }
      for(const derived of allDerivedCards(state))if(!byHash.has(derived.definition_hash))byHash.set(derived.definition_hash,derived);
      const cards = [], mappings = [], included = new Set();
      for (const local of body.cards) {
        const compiled = compileCard(local.definition, state.keywords);
        validateMedia(state,owner,compiled.definition);
        if (compiled.definition_hash !== local.definition_hash) fail('HASH_MISMATCH', `本地卡牌 ${local.local_card_id} 的定义哈希不匹配。`, 422);
        let stored = byHash.get(compiled.definition_hash);
        if (stored && stored.compiled_program_hash !== compiled.compiled_program_hash) fail('HASH_MISMATCH', '已发布卡牌依赖与当前编译结果不一致。', 409);
        if (!stored) {
          if(contentState(state,"cards",local.local_card_id).deleted || Object.values(state.content_lifecycle?.cards??{}).some(e=>e.deleted&&e.hashes?.includes(local.definition_hash)))fail("CONTENT_DELETED","同步内容已彻底删除，不能自动重新上传。",410);
          requireCardFaction(compiled.definition,state.factions);
          if (++ownedCards > this.maxCardsPerOwner) fail('RATE_LIMITED', '当前玩家同步的卡牌数量已达到上限。', 429);
          stored = {card_id: randomUUID(), revision: 1, series:currentCardSeries(state), ...compiled, interpreter_version: 'interpreter-1', compiler_version: 'card-compiler-1', provenance: {source_kind: 'json_import'}, owner_id: owner, created_at: new Date(now).toISOString()};
          state.cards[stored.card_id] = [stored];
          byHash.set(stored.definition_hash, stored);
        }
        mappings.push({local_card_id: local.local_card_id, card_id: stored.card_id});
        const frozenId = `${stored.card_id}@${stored.revision}`;
        if (!included.has(frozenId)) { included.add(frozenId); cards.push(publicCard(stored, owner, isAdmin(state,owner), state)); }
      }
      const keyword_registry_hash = registryHash(state.keywords);
      state.catalogs[keyword_registry_hash] = registryEntries(state.keywords);
      return {cards, mappings, keyword_registry_hash};
    });
  }

  checkKeywordName(state, definition) {
    const namespace = definition.id.split('.')[0];
    const labels = new Set([definition.name, ...definition.aliases].map(label => label.trim().toLocaleLowerCase('en-US')));
    for (const entry of registryEntries(state.keywords)) {
      if (entry.definition.id === definition.id || entry.definition.id.split('.')[0] !== namespace) continue;
      if ([entry.definition.name, ...entry.definition.aliases].some(label => labels.has(label.trim().toLocaleLowerCase('en-US')))) fail('KEYWORD_NAME_CONFLICT', '同一命名空间已有使用此名称或别名的词条，请明确词条身份。', 409);
    }
  }
}
