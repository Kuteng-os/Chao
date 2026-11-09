import {cardSeries} from './card_series.js';
import {createHash} from 'node:crypto';
import {compileCard,walkEffects} from './validation.js';

// A token keeps its identity across source-card revisions; no duplicate writable
// registry is created. Old decks resolve the exact source revision they froze.
export function derivedId(cardId, tokenId) {
  const bytes=createHash('sha256').update('chao-derived-v1\0'+cardId+'\0'+tokenId).digest().subarray(0,16);
  bytes[6]=(bytes[6]&15)|80;bytes[8]=(bytes[8]&63)|128;
  const hex=bytes.toString('hex');return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
const compiledCache=new Map();
function materialize(state,parent,token) {
  const key=parent.definition_hash+':'+parent.compiled_program_hash+':'+token.token_id;
  let compiled=compiledCache.get(key);
  if(!compiled){
    const library=parent.definition.tokens,expanded=parent.compiled_program.expanded_definition.tokens;
    const reachable=new Set();
    const visit=id=>{if(reachable.has(id))return;reachable.add(id);const t=expanded.find(t=>t.token_id===id);for(const a of t?.abilities??[])for(const e of walkEffects(a.effects)){if(e.token_id)visit(e.token_id);if(e.on_kill_summon)visit(e.on_kill_summon);for(const id of e.token_ids??[])visit(id);}};
    for(const a of expanded.find(t=>t.token_id===token.token_id)?.abilities??[])for(const e of walkEffects(a.effects)){if(e.token_id)visit(e.token_id);if(e.on_kill_summon)visit(e.on_kill_summon);for(const id of e.token_ids??[])visit(id);}
    const d=structuredClone(token);delete d.token_id;
    d.kind??='unit';d.cost??=1;d.operation_cost??=d.kind==='unit'?1:0;d.abilities??=[];d.play_target??=null;d.flavor_text??='';
    if(parent.definition.veteran?.token_id===token.token_id)for(const key of ['sin','rarity'])if(!Object.hasOwn(d,key)&&Object.hasOwn(parent.definition,key))d[key]=parent.definition[key];
    d.rarity??='standard';d.deck_building??='generated_only';
    d.schema_version=parent.definition.schema_version;d.ruleset_version=parent.definition.ruleset_version;
    d.appearance={emblem:d.kind==='unit'?d.unit_class:d.kind};
    if(parent.definition.faction_id)d.faction_id=parent.definition.faction_id;
    d.tokens=library.filter(t=>reachable.has(t.token_id)).map(t=>structuredClone(t));
    compiled=compileCard(d,state.keywords);
    if(compiledCache.size>=2048)compiledCache.delete(compiledCache.keys().next().value);
    compiledCache.set(key,compiled);
  }
  return {card_id:derivedId(parent.card_id,token.token_id),revision:parent.revision,series:cardSeries(parent),...structuredClone(compiled),owner_id:parent.owner_id,created_at:parent.created_at,interpreter_version:parent.interpreter_version,compiler_version:parent.compiler_version,
    art:parent.token_art?.[token.token_id]??null,token_art:Object.fromEntries(compiled.definition.tokens.filter(t=>parent.token_art?.[t.token_id]).map(t=>[t.token_id,structuredClone(parent.token_art[t.token_id])])),
    derived_from:{card_id:parent.card_id,revision:parent.revision,token_id:token.token_id,name:parent.definition.name,retired:!(state.cards[parent.card_id]?.at(-1)?.definition.tokens??[]).some(t=>t.token_id===token.token_id)},
    available_revisions:(state.cards[parent.card_id]??[parent]).filter(p=>p.definition.tokens.some(t=>t.token_id===token.token_id)).map(p=>p.revision).reverse()};
}
export function latestCards(state) {
  const records=[];
  for(const id of Object.keys(state.cards).sort()){
    const p=state.cards[id].at(-1);records.push(p);
    const last=new Map();for(const version of state.cards[id])for(const token of version.definition.tokens)last.set(token.token_id,{version,token});
    for(const {version,token} of last.values())records.push(materialize(state,version,token));
  }
  return records;
}
export function resolveCard(state,id,revision=null) {
  const ordinary=state.cards[id];
  if(ordinary)return revision===null?ordinary.at(-1):ordinary.find(c=>c.revision===revision)??null;
  for(const versions of Object.values(state.cards)){
    const parents=revision===null?[...versions].reverse():versions.filter(p=>p.revision===revision);
    for(const parent of parents)for(const token of parent.definition.tokens)if(derivedId(parent.card_id,token.token_id)===id)return materialize(state,parent,token);
  }
  return null;
}

export function allDerivedCards(state){
 const records=[];for(const versions of Object.values(state.cards))for(const p of versions)for(const t of p.definition.tokens)records.push(materialize(state,p,t));return records;
}
