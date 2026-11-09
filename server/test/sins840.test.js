import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {SINS,mainSin} from '../src/sins.js';
import {compileCard,applyCardBlueprint,validateCardBlueprint} from '../src/validation.js';
import {Store} from '../src/store.js';
import {CardService} from '../src/service.js';
import {SharedDecks} from '../src/shared_decks.js';
import {CloudCatalog} from '../src/cloud_catalog.js';
import {derivedId} from '../src/derived_cards.js';
import {freshCard,blueprint} from '../../web/model.mjs';
import {cardFace,filterCards,filterDefaults} from '../../web/catalog.mjs';
import {sinInfo} from '../../web/sins.mjs';
const unit=()=>({...freshCard(),name:'无阵营试验兵'});
const luminance=hex=>{const v=hex.match(/[\da-f]{2}/gi).map(s=>parseInt(s,16)/255).map(n=>n<=.04045?n/12.92:((n+.055)/1.055)**2.4);return v[0]*.2126+v[1]*.7152+v[2]*.0722;};
test('seven sins: optional schema, frozen blueprint, dark readable palette and independent filters',async()=>{
 assert.equal(SINS.length,7);assert.deepEqual(SINS.map(s=>s.name),['暴怒','色欲','怠惰','暴食','忧郁','傲慢','嫉妒']);
 for(const s of SINS){
  assert.equal(sinInfo(s.id).color,s.color);assert((luminance('f9f4dd')+.05)/(luminance(s.color)+.05)>7,'high text contrast '+s.id);
  assert((await readFile(new URL('../../assets/sins/'+s.id+'.png',import.meta.url))).length>100);
  const d={...unit(),sin:s.id};assert.equal(compileCard(d,{}).definition.sin,s.id);
  const bp=validateCardBlueprint(blueprint(d),{});assert.equal(applyCardBlueprint({...d,sin:'envy'},bp).sin,s.id);
  assert.equal(mainSin(s.id),s.id);assert(!cardFace({definition:d},[]).includes('/workshop/sins/'));
  const html=cardFace({definition:{...d,faction_id:'same'}},[{faction_id:'same',name:'测试阵营',icon_id:'a'.repeat(64)}]);
  assert(html.includes('/v1/card-art/'+'a'.repeat(64)+'.png'));assert(html.includes('data-faction-color="'+s.color+'"'));
 }
 for(const sin of ['greed','wrath;script',{},42,[]]){assert.throws(()=>compileCard({...unit(),sin},{}));assert.throws(()=>mainSin(sin));}
 const old=unit();delete old.sin;assert(!Object.hasOwn(compileCard(old,{}).definition,'sin'));
 assert.equal(compileCard({...old,sin:null},{}).definition.sin,null);assert.equal(sinInfo(null).color,'#303538');
 const records=SINS.map((s,i)=>({card_id:String(i),definition:{...unit(),sin:s.id,faction_id:'same'}}));records.push({definition:old});
 assert.equal(filterCards(records,{...filterDefaults,sin:'envy',faction:'same'}).length,1);assert.equal(filterCards(records,{...filterDefaults,sin:'none'}).length,1);
});
test('author revisions, generated card sins, shared deck save/load without a faction requirement',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'chao-sins840-')),store=await new Store(dir).init();
 try{
  const service=new CardService(store,{configured:false,model:'test'},{requireFactions:true}),catalog=new CloudCatalog(service),decks=new SharedDecks(service);
  const save=async(d,previous)=>{const draft=await service.manualDraft('alice',{request_id:randomUUID(),definition:d});return service.confirmCard('alice',{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash,...(previous?{base_revision:previous.revision}:{})},previous?.card_id);};
  const refs=[];for(let i=0;i<11;i++){const c=await save({...unit(),name:'混合罪孽'+i,sin:i<8?'envy':'gloom'});for(let j=0;j<(i===7||i===10?2:4);j++)refs.push({card_id:c.card_id,revision:1,definition_hash:c.definition_hash});}
  const body={request_id:randomUUID(),name:'双罪孽组合',cards:refs,main_sin:'envy',ally_sin:'gloom'};
  const shared=await decks.publish('alice',body);assert.equal(shared.main_sin,'envy');assert.equal(shared.main_faction_id,'');assert.equal(decks.detail(shared.deck_id).cards.length,11);
  assert.deepEqual(await decks.publish('alice',body),shared);await assert.rejects(decks.publish('alice',{...body,main_sin:'wrath'}),e=>e.code==='IDEMPOTENCY_CONFLICT');
  await assert.rejects(decks.publish('alice',{...body,request_id:randomUUID(),main_sin:'greed'}),e=>e.code==='INVALID_SIN');
  const old=await save({...unit(),sin:null,tokens:[{token_id:'child',name:'罪孽衍生',sin:'lust',unit_class:'infantry',attack:1,health:2,keywords:[]}]});
  const id=derivedId(old.card_id,'child');assert.equal(catalog.card(null,id).definition.sin,'lust');
  await save({...old.definition,sin:'pride'},old);assert.equal(catalog.card(null,old.card_id).definition.sin,'pride');assert.equal(catalog.card(null,old.card_id,1).definition.sin,null);assert.equal(catalog.card(null,id).definition.sin,'lust');
  await store.close();const again=await new Store(dir).init();assert.equal(again.state.shared_decks[shared.deck_id].main_sin,'envy');await again.close();
 }finally{await store.close();await rm(dir,{recursive:true,force:true});}
});
