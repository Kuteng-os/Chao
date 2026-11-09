import {derivedId,resolveCard} from './derived_cards.js';
import {fail, hash} from './codec.js';
import {fields} from './service.js';
import {isAdmin, audit} from './account_roles.js';
import {registryHash, registryEntries} from './validation.js';

export const contentState = (state, kind, id) => state.content_lifecycle?.[kind]?.[id] ?? {};
export const archived = (state, kind, id) => Boolean(contentState(state, kind, id).archived);
export function lifecycleSnapshot(state) { return structuredClone(state.content_lifecycle ?? {cards:{},keywords:{},factions:{}}); }
export function assertKeywordAvailable(state, id) {
  if (contentState(state,'keywords',id).deleted) fail('CONTENT_DELETED','此词条已彻底删除，请创建新的词条身份。',410);
}

function resolveContent(state, kind, id, owner) {
  let records;
  if (kind==='cards') records=Object.hasOwn(state.cards,id)?state.cards[id]:null;
  else if (kind==='factions') records=Object.hasOwn(state.factions,id)?[state.factions[id]]:null;
  else if (kind==='keywords') records=Object.values(state.keywords).filter(k=>k.definition.id===id);
  else fail('NOT_FOUND','内容类别不存在。',404);
  if (!records?.length) fail('NOT_FOUND','内容已删除或不存在。',404);
  const first=records[0], system=kind==='keywords'&&records.some(k=>k.approval_source?.startsWith('engine_')||k.definition.implementation.kind==='builtin');
  if (!(first.owner_id===owner || isAdmin(state,owner))) fail('FORBIDDEN','只能管理自己的内容。',403);
  return {records,system,name:kind==='factions'?first.name:records.at(-1).definition.name};
}

function dependencies(state, kind, id) {
  const cards=[],decks=[];
  const relatedIds=new Set([id]);if(kind==='cards')for(const p of state.cards[id]??[])for(const t of p.definition.tokens)relatedIds.add(derivedId(id,t.token_id));
  if(kind!=='cards') for(const [card_id,versions] of Object.entries(state.cards)) {
    const used=versions.filter(c=>kind==='factions'?c.definition.faction_id===id:c.keyword_bindings.some(b=>b.id===id));
    if(used.length)cards.push({card_id,name:versions.at(-1).definition.name,revisions:used.map(c=>c.revision)});
  }
  for(const deck of Object.values(state.shared_decks)) {
    if(kind==='cards'?(deck.cards.some(c=>relatedIds.has(c.card_id))||relatedIds.has(deck.headquarters?.card_id)):kind==='factions'&&[deck.main_faction_id,deck.ally_faction_id].includes(id))
      decks.push({deck_id:deck.deck_id,name:deck.name,revision:deck.revision});
  }
  return {cards:cards.sort((a,b)=>a.card_id.localeCompare(b.card_id)),decks:decks.sort((a,b)=>a.deck_id.localeCompare(b.deck_id))};
}

export class ContentLifecycle {
  constructor(service) {this.service=service;this.store=service.store;}
  preview(owner,kind,id,state=this.store.state) {
    const {records,system,name}=resolveContent(state,kind,id,owner),related=dependencies(state,kind,id);
    const current=contentState(state,kind,id);
    return {kind,id,name,archived:Boolean(current.archived),versions:records.length,...related,
      can_delete:!system&&!related.cards.length&&(kind==='cards'||!related.decks.length),
      blocked_reason:system?'内置规则不能彻底删除，可归档隐藏。':related.cards.length?'仍有卡牌版本引用此内容，请先删除关联卡牌，或使用归档。':kind!=='cards'&&related.decks.length?'仍有共享牌组选用此阵营，请先修改牌组，或使用归档。':'',
      expected_state:hash({records,current,related})};
  }
  async mutate(owner,kind,id,action,body) {
    fields(body,['request_id','expected_state']);
    if(!['archive','restore','delete'].includes(action))fail('NOT_FOUND','操作不存在。',404);
    return this.service.idem(owner,`content:${kind}:${id}:${action}`,body,state=>{
      const preview=this.preview(owner,kind,id,state);
      if(body.expected_state!==preview.expected_state)fail('REVISION_CONFLICT','内容或关联关系已变化，请重新查看后确认。',409);
      state.content_lifecycle??={cards:{},keywords:{},factions:{}};
      const previous=contentState(state,kind,id),entry={archived:action==='archive',revision:(previous.revision??0)+1};
      if(action==='delete') {
        if(!preview.can_delete)fail('CONTENT_IN_USE',preview.blocked_reason,409,{cards:preview.cards,decks:preview.decks});
        const records=resolveContent(state,kind,id,owner).records;
        entry.deleted=true;entry.hashes=records.map(r=>r.definition_hash).filter(Boolean);
        if(kind==='cards') {
          const deletedIds=new Set([id]);
          for(const parent of records)for(const token of parent.definition.tokens){
            const childId=derivedId(id,token.token_id),child=resolveCard(state,childId,parent.revision);deletedIds.add(childId);
            const childEntry=state.content_lifecycle.cards[childId]??{hashes:[]};childEntry.hashes??=[];
            if(child)childEntry.hashes.push(child.definition_hash);
            Object.assign(childEntry,{deleted:true,archived:false,revision:(childEntry.revision??0)+1});state.content_lifecycle.cards[childId]=childEntry;
          }
          delete state.cards[id];
          for(const deck of Object.values(state.shared_decks)) if((deck.cards.some(c=>deletedIds.has(c.card_id))||deletedIds.has(deck.headquarters?.card_id))) {
            deck.cards=deck.cards.filter(c=>!deletedIds.has(c.card_id));deck.published=false;deck.revision++;
            deck.unavailable_reason='部分卡牌已彻底删除，请补齐后重新上传。';deck.updated_at=new Date().toISOString();
          }
        } else if(kind==='factions') delete state.factions[id];
        else {
          for(const [key,r] of Object.entries(state.keywords))if(r.definition.id===id)delete state.keywords[key];
          for(const [key,catalog] of Object.entries(state.catalogs))if(catalog.some(k=>k.definition.id===id))delete state.catalogs[key];
          state.catalogs[registryHash(state.keywords)]=registryEntries(state.keywords);
        }
        // Purge editable drafts and replay caches; finished match snapshots remain historical records.
        const mentions=value=>{
          if(!value||typeof value!=='object')return false;
          if(Array.isArray(value))return value.some(mentions);
          if(kind==='cards'&&(value.card_id===id||entry.hashes.includes(value.definition_hash)||entry.hashes.includes(value.draft_hash)))return true;
          if(kind==='keywords'&&(value.id===id||value.assigned_id===id))return true;
          if(kind==='factions'&&value.faction_id===id)return true;
          return Object.values(value).some(mentions);
        };
        for(const collection of ['drafts','proposals','generations','idempotency'])
          for(const [key,value] of Object.entries(state[collection]))if(mentions(value))delete state[collection][key];
      }
      state.content_lifecycle[kind][id]=entry;
      audit(state,owner,`content_${action}`,`${kind}:${id}`);
      return {ok:true,kind,id,action,archived:entry.archived,deleted:Boolean(entry.deleted)};
    });
  }
}
