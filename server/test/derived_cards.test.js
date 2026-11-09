import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
import {Store} from '../src/store.js';
import {CardService} from '../src/service.js';
import {CloudCatalog} from '../src/cloud_catalog.js';
import {derivedId,resolveCard} from '../src/derived_cards.js';
import {SharedDecks} from '../src/shared_decks.js';
import {ContentLifecycle} from '../src/content_lifecycle.js';
import {checkDeckCopies} from '../src/deck_rules.js';
import {compileCard} from '../src/validation.js';
import {freshCard} from '../../web/model.mjs';
const id='11111111-1111-4111-8111-111111111111';
function parent(){return {...freshCard(),name:'生成者',faction_id:id,abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:'a',player:'owner',amount:1}]}],tokens:[{token_id:'a',name:'衍生指令',kind:'order',cost:1,operation_cost:0,unit_class:null,attack:0,health:0,keywords:[],abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:'b',player:'owner',amount:1}]}]},{token_id:'b',name:'衍生单位',unit_class:'infantry',attack:1,health:2,keywords:[]}]};}
const record=(d,revision=1,card_id=id)=>({card_id,revision,...compileCard(d,{}),owner_id:'alice',created_at:'2026-09-26',interpreter_version:'interpreter-1',compiler_version:'card-compiler-1'});
test('derived catalog uses stable identities, frozen dependencies, default exclusion and sound versions',()=>{
 const first=record(parent()),state={cards:{[id]:[first]},keywords:{}};
 const a=resolveCard(state,derivedId(id,'a')),b=resolveCard(state,derivedId(id,'b'));
 assert.equal(a.definition.deck_building,'generated_only');assert.match(checkDeckCopies([a]),/尚未获准/);
 assert.equal(a.definition.tokens.length,1);assert.equal(a.definition.tokens[0].token_id,'b');assert.equal(b.definition.tokens.length,0);
 assert.equal(b.definition.kind,'unit');assert.equal(b.definition.health,2);assert.equal(b.definition.faction_id,id);
 assert.equal(compileCard(a.definition,{}).compiled_program_hash,a.compiled_program_hash);
 const second=parent();second.tokens[0].deck_building='allowed';second.tokens[0].rarity='elite';second.tokens[0].media={sounds:{play:'a'.repeat(64)}};
 state.cards[id].push(record(second,2));const latest=resolveCard(state,a.card_id);
 assert.equal(latest.card_id,a.card_id);assert.equal(latest.revision,2);assert.equal(latest.definition.media.sounds.play,'a'.repeat(64));assert.equal(checkDeckCopies([latest]),'');assert.match(checkDeckCopies([latest,latest]),/最多携带 1/);
 assert.equal(resolveCard(state,a.card_id,1).definition_hash,a.definition_hash);assert.equal(resolveCard(state,a.card_id,1).definition.media,undefined);
 assert.deepEqual(latest.available_revisions,[2,1]);
});
test('author revision, shared decks, archive, retirement, delete and media authorization',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'chao-derived-')),store=await new Store(dir).init();
 try{
  const service=new CardService(store,{configured:false,model:'test'}),catalog=new CloudCatalog(service),decks=new SharedDecks(service),life=new ContentLifecycle(service);
  await store.transaction(s=>{s.factions[id]={faction_id:id,name:'测试',color:'#334455',role:'major',owner_id:'alice'};s.sound_assets['a'.repeat(64)]={owners:['alice'],duration:1};});
  async function save(d,previous,owner='alice'){const draft=await service.manualDraft(owner,{request_id:randomUUID(),definition:d});return service.confirmCard(owner,{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash,...(previous?{base_revision:previous.revision}:{})},previous?.card_id);}
  const p=await save(parent()),aId=derivedId(p.card_id,'a');
  let child=catalog.card('alice',aId);assert(child.can_edit);assert.equal(catalog.card('bob',aId).can_edit,false);assert.equal(catalog.cards(null).cards.length,3);
  assert(!JSON.stringify(catalog.cards(null)).includes('owner_id'));assert(!JSON.stringify(catalog.cards(null)).includes('provenance'));
  const change=parent();change.tokens[0].sin='wrath';change.tokens[0].deck_building='allowed';change.tokens[0].media={sounds:{play:'a'.repeat(64)}};
  await assert.rejects(save(change,p,'bob'));const revised=await save(change,p);child=catalog.card('alice',aId);assert.equal(child.revision,2);
  const remaining=[];await store.transaction(s=>{for(let i=0;i<11;i++){const d={...freshCard(),sin:i<8?'wrath':'gloom',name:'普通'+i,faction_id:id},c={...record(d,1,randomUUID())};s.cards[c.card_id]=[c];for(let j=0;j<(i===0?3:i===7||i===10?2:4);j++)remaining.push({card_id:c.card_id,revision:1,definition_hash:c.definition_hash});}});
  const publish=c=>decks.publish('bob',{request_id:randomUUID(),name:'含衍生牌',main_sin:'wrath',ally_sin:'gloom',cards:[{card_id:c.card_id,revision:c.revision,definition_hash:c.definition_hash},...remaining]});
  await assert.rejects(publish(catalog.card(null,aId,1)),/尚未获准/);const shared=await publish(child);assert.equal(decks.detail(shared.deck_id).cards.find(c=>c.card_id===aId).definition.media.sounds.play,'a'.repeat(64));
  const before=life.preview('alice','cards',p.card_id);assert.equal(before.decks.length,1);await life.mutate('alice','cards',p.card_id,'archive',{request_id:randomUUID(),expected_state:before.expected_state});assert(catalog.card(null,aId).archived);assert(decks.detail(shared.deck_id));
  const removed={...parent(),abilities:[],tokens:[]};await save(removed,revised);assert(catalog.cards(null).cards.find(c=>c.card_id===aId).derived_from.retired);assert(decks.detail(shared.deck_id));
  const preview=life.preview('alice','cards',p.card_id);await life.mutate('alice','cards',p.card_id,'delete',{request_id:randomUUID(),expected_state:preview.expected_state});
  assert.equal(store.getCard(aId,2),null);assert(store.state.content_lifecycle.cards[aId].deleted);assert.equal(store.state.shared_decks[shared.deck_id].published,false);assert.throws(()=>decks.detail(shared.deck_id,'bob'));
 }finally{await store.close();await rm(dir,{recursive:true,force:true});}
});
