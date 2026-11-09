import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
import {Store} from '../src/store.js';
import {createApp} from '../src/index.js';
import {CardService} from '../src/service.js';
import {CloudCatalog} from '../src/cloud_catalog.js';
import {initializeCardSeries,seriesCatalog} from '../src/card_series.js';
import {catalogUpdates} from '../src/catalog_updates.js';
import {derivedId} from '../src/derived_cards.js';
import {compileCard} from '../src/validation.js';
import {freshCard} from '../../web/model.mjs';
import {filterCards,filterDefaults,cleanFilters,filtersUI} from '../../web/catalog.mjs';
const factionId='11111111-1111-4111-8111-111111111111';
const definition=name=>({...freshCard(),name,faction_id:factionId});
const withToken=name=>({...definition(name),abilities:[{trigger:'on_play',effects:[{op:'summon',token_id:'child',amount:1,row:'support'}]}],tokens:[{token_id:'child',name:'衍生单位',unit_class:'infantry',attack:1,health:1,keywords:[]}]});
const stored=(d,revision=1,card_id=randomUUID())=>({card_id,revision,...compileCard(d,{}),owner_id:'author',created_at:'2026-10-03',compiler_version:'card-compiler-1',interpreter_version:'interpreter-1'});

test('central HTTP health and public catalog agree on the opened series',async()=>{
 const dataDir=await mkdtemp(join(tmpdir(),'series-http-'));
 const app=await createApp({dataDir,host:'127.0.0.1',port:0,centralMode:true,inviteToken:'test-series-token-123456789',matches:false,provider:{configured:false}});
 try{
  const address=await app.listen(0),origin=`http://127.0.0.1:${address.port}`;
  for(const path of ['/health','/v1/public/cards']){
   const response=await fetch(origin+path);assert.equal(response.status,200);
   assert.deepEqual((await response.json()).card_series,{current:2,available:[1,2],revision:1,entries:[{id:1,name:'第一期'},{id:2,name:'第二期'}]});
  }
 }finally{await app.close();await rm(dataDir,{recursive:true,force:true});}
});
test('series migration preserves frozen definitions, archives and old revisions, and is idempotent',()=>{
 const first=stored(withToken('第一期')),second=stored(withToken('第一期修改'),2,first.card_id);
 const state={cards:{[first.card_id]:[first,second]},content_lifecycle:{cards:{[first.card_id]:{archived:true}}},shared_decks:{example:{cards:[{card_id:first.card_id,revision:1,definition_hash:first.definition_hash}]}}};
 const before=structuredClone(state);initializeCardSeries(state);
 assert.deepEqual(seriesCatalog(state),{current:2,available:[1,2],revision:1,entries:[{id:1,name:'第一期'},{id:2,name:'第二期'}]});for(const record of state.cards[first.card_id])assert.equal(record.series,1);
 const without=structuredClone(state);delete without.card_series;for(const record of without.cards[first.card_id])delete record.series;assert.deepEqual(without,before);
 // The compiler uses null-prototype maps, which structuredClone normalizes.
 const migrated=structuredClone(state);initializeCardSeries(state);assert.deepEqual(structuredClone(state),migrated);
});
test('new registration is series two; revisions and derived cards keep source series across restart and sync',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'chao-series-'));let store=await new Store(dir).init();
 try{
  const old=stored(withToken('旧牌'));await store.transaction(s=>{s.cards[old.card_id]=[old];s.factions[factionId]={faction_id:factionId,name:'测试',color:'#334455',role:'major',owner_id:'author'};s.content_lifecycle.cards[old.card_id]={archived:true};});
  await store.close();store=await new Store(dir).init();let service=new CardService(store,{configured:false,model:'test'}),catalog=new CloudCatalog(service);
  const save=async(d,previous)=>{const draft=await service.manualDraft('author',{request_id:randomUUID(),definition:d});return service.confirmCard('author',{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash,...(previous?{base_revision:previous.revision}:{})},previous?.card_id);};
  assert.equal(catalog.card(null,old.card_id).series,1);assert.equal(catalog.card(null,derivedId(old.card_id,'child')).series,1);
  const revised=await save(withToken('旧牌改名'),old);assert.equal(revised.series,1);assert.equal(catalog.card(null,old.card_id,1).series,1);
  const fresh=await save(withToken('第二期'));assert.equal(fresh.series,2);assert.equal(catalog.card(null,derivedId(fresh.card_id,'child')).series,2);
  const next=await save(withToken('第二期修改'),fresh);assert.equal(next.series,2);
  const existingSync=await catalog.sync('author',{request_id:randomUUID(),cards:[{local_card_id:old.card_id,definition:old.definition,definition_hash:old.definition_hash}],keywords:[]});assert.equal(existingSync.cards[0].series,1);
  const local=stored(definition('本地新牌'));const added=await catalog.sync('author',{request_id:randomUUID(),cards:[{local_card_id:local.card_id,definition:local.definition,definition_hash:local.definition_hash}],keywords:[]});assert.equal(added.cards[0].series,2);
  assert.equal(service.health().card_series.current,2);
  await store.close();store=await new Store(dir).init();catalog=new CloudCatalog(new CardService(store,{configured:false,model:'test'}));
  assert.equal(catalog.card(null,fresh.card_id).series,2);assert.equal(catalog.card(null,old.card_id).series,1);
  assert.equal(catalog.card(null,old.card_id,1).compiled_program_hash,old.compiled_program_hash);
 }finally{await store.close();await rm(dir,{recursive:true,force:true});}
});
test('series filters compose, include legacy records, and metadata invalidates incremental cache once',()=>{
 const a=stored(definition('旧步兵')),b={...stored({...definition('新指令'),kind:'order',unit_class:null,attack:0,health:0,operation_cost:0,appearance:{emblem:'order'},abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]}),series:2};
 assert.deepEqual(filterCards([a,b],{...filterDefaults,series:'1'}).map(x=>x.card_id),[a.card_id]);
 assert.deepEqual(filterCards([a,b],{...filterDefaults,series:'2',kind:'order',q:'新'}).map(x=>x.card_id),[b.card_id]);
 assert.equal(filterCards([a,b],{...filterDefaults,series:'2',kind:'unit'}).length,0);
 assert.equal(cleanFilters({series:'2'}).series,'2');assert.match(filtersUI(filterDefaults,[a,b],[],[],'',2),/全部卡包/);
 const snapshot={cards:[a,b],keywords:[],factions:[],lifecycle:{}};const before=catalogUpdates({},snapshot);a.series=1;
 const changed=catalogUpdates(before.fingerprints,snapshot);assert.deepEqual(changed.cards.map(x=>x.card_id),[a.card_id]);assert.equal(catalogUpdates(changed.fingerprints,snapshot).cards.length,0);
});
