import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {Store} from '../src/store.js';
import {CardService} from '../src/service.js';
import {CloudCatalog} from '../src/cloud_catalog.js';
import {selectTokenArt,selectArt,tokenArtIds} from '../src/card_art.js';
import {derivedId} from '../src/derived_cards.js';
import {catalogUpdates} from '../src/catalog_updates.js';
import {freshCard} from '../../web/model.mjs';
const art=n=>String(n).repeat(64),faction=randomUUID();
const definition=()=>({...freshCard(),name:'图像生成者',faction_id:faction,tokens:[
 {token_id:'a',name:'衍生指令',kind:'order',cost:0,operation_cost:0,unit_class:null,attack:0,health:0,keywords:[],abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:'b',player:'owner',amount:1}]}]},
 {token_id:'b',name:'衍生步兵',unit_class:'infantry',attack:1,health:2,keywords:[]}
]});
test('derived art revisions, inherited libraries, access control, removal and deltas',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'chao-art839-')),store=await new Store(dir).init();
 try{
  const service=new CardService(store,{configured:false,model:'test'}),catalog=new CloudCatalog(service);
  await store.transaction(s=>{s.factions[faction]={faction_id:faction,name:'测试',color:'#334455',role:'major',owner_id:'alice'};for(const n of [1,2,3,4])s.card_art[art(n)]={width:760,height:520,owners:[n===4?'bob':'alice']};});
  const save=async(d,previous,ids,owner='alice')=>{const draft=await service.manualDraft(owner,{request_id:randomUUID(),definition:d});return service.confirmCard(owner,{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash,...(previous?{base_revision:previous.revision}:{art_id:art(1)}),...(ids===undefined?{}:{token_art_ids:ids})},previous?.card_id);};
  const first=await save(definition(),null,{a:art(2),b:art(3)}),a=derivedId(first.card_id,'a'),b=derivedId(first.card_id,'b');
  assert.equal(catalog.card(null,a).art.id,art(2));assert.equal(catalog.card(null,b).art.id,art(3));
  assert.deepEqual(tokenArtIds(catalog.card(null,a)),{b:art(3)});assert.deepEqual(tokenArtIds(catalog.card(null,b)),{});
  assert.equal(catalog.card(null,first.card_id).art.id,art(1));
  const projection=()=>({cards:catalog.cards(null).cards,keywords:[],factions:[],lifecycle:{}});
  const manifest=catalogUpdates({},projection()).fingerprints;
  await assert.rejects(save(definition(),first,{a:art(3)},'bob'));
  for(const ids of [{a:art(4)},{missing:art(2)},{a:null},{a:'bad'},[],null])await assert.rejects(save(definition(),first,ids),e=>e.code==='INVALID_ART');
  assert.equal(store.state.cards[first.card_id].length,1);
  const changed=await save(definition(),first,{a:art(3),b:art(2)});
  assert.equal(changed.definition_hash,first.definition_hash);assert.equal(changed.compiled_program_hash,first.compiled_program_hash);
  assert.equal(catalog.card(null,a,1).art.id,art(2));assert.equal(catalog.card(null,a,2).art.id,art(3));
  assert.equal(catalog.card(null,a,1).token_art.b.id,art(3));
  assert.equal(catalogUpdates(manifest,projection()).cards.length,3);
  assert.equal(selectArt(store.state,'bob',art(2)).id,art(2),'published derived art may be reused like ordinary art');
  const oldClient=await save(definition(),changed,undefined);assert.deepEqual(oldClient.token_art,changed.token_art);
  const cleared=await save(definition(),oldClient,{});assert.equal(catalog.card(null,a).art,null);assert.equal(catalog.card(null,b).art,null);assert.equal(cleared.art.id,art(1));
  const deleted={...definition(),tokens:[]};const final=await save(deleted,cleared,undefined);assert.deepEqual(final.token_art,{});assert.equal(catalog.card(null,a,1).art.id,art(2));
  assert.deepEqual(selectTokenArt(store.state,'alice',undefined,definition().tokens,first.token_art),first.token_art);
 }finally{await store.close();await rm(dir,{recursive:true,force:true});}
});
