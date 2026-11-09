import {FACTION_ID, seedFactions} from './faction_fixture.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID, createHash} from 'node:crypto';
import {PNG} from 'pngjs';
import {createApp} from '../src/index.js';
import {hash} from '../src/codec.js';
const provider={configured:false, model:'test', async generate(){throw Error('No model calls');}};
const inviteToken='isolated-test-only-invite-123456789';
const unit=i=>({sin:i<8?'wrath':'gloom',schema_version:'1.0.0',ruleset_version:'frontline-1',name:'共享测试 '+i,faction_id:FACTION_ID,flavor_text:'',kind:'unit',unit_class:'infantry',cost:2,operation_cost:1,attack:2,health:3,keywords:[],play_target:null,abilities:[],tokens:[],appearance:{emblem:'infantry'}});
async function fixture(t, factionIds = [FACTION_ID]){
  const dataDir=await mkdtemp(join(tmpdir(),'frontline-decks-'));
  const options={centralMode:true,inviteToken,matches:false,host:'127.0.0.1',port:0,provider,dataDir};
  let app=await createApp(options), address=await app.listen(), base=`http://127.0.0.1:${address.port}`;
  t.after(async()=>{await app.close();await rm(dataDir,{recursive:true,force:true});});
  async function req(path,body,token,method=body===undefined?'GET':'POST'){
    if(path==='/v1/decks'&&body&&!body.deck_id)body={main_sin:'wrath',ally_sin:'gloom',...body};
    const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});
    return {status:r.status,body:r.headers.get('content-type').includes('image/')?Buffer.from(await r.arrayBuffer()):await r.json()};
  }
  await seedFactions(app.service.store);
  await app.service.store.transaction(state=>{for(const id of factionIds)if(!state.factions[id])state.factions[id]={...state.factions[FACTION_ID],faction_id:id,name:'自建 '+id,role:'ally'};});
  const a=(await req('/v1/sessions',{invite_code:inviteToken,display_name:'牌组作者'})).body;
  const b=(await req('/v1/sessions',{invite_code:inviteToken,display_name:'另一玩家'})).body;
  const published=await req('/v1/card-sync',{request_id:randomUUID(),cards:Array.from({length:11},(_,i)=>{const definition={...unit(i),faction_id:factionIds[i%factionIds.length]};return {local_card_id:'card-'+i,definition,definition_hash:hash(definition)};}),keywords:[]},a.access_token);
  assert.equal(published.status,200);
  const cards=published.body.cards, refs=cards.flatMap((c,i)=>Array.from({length:i===7||i===10?2:4},()=>({card_id:c.card_id,revision:c.revision,definition_hash:c.definition_hash})));
  return {req,a,b,cards,refs,get app(){return app;},async restart(){await app.close();app=await createApp(options);address=await app.listen();base=`http://127.0.0.1:${address.port}`;}};
}

test('free faction deck keeps an unrelated nominal main through sharing and restart',async t=>{
  const ids=[FACTION_ID,randomUUID(),randomUUID()],nominal=randomUUID();
  const f=await fixture(t,ids),{req,a,refs}=f;
  await f.app.service.store.transaction(state=>{state.factions[nominal]={...state.factions[FACTION_ID],faction_id:nominal,name:'名义主国',role:'ally'};});
  const body={request_id:randomUUID(),name:'自由混编',cards:refs,main_faction_id:nominal,ally_faction_id:ids[1]};
  const published=await req('/v1/decks',body,a.access_token);
  assert.equal(published.status,201);assert.equal(published.body.main_faction_id,nominal);assert.equal(published.body.ally_faction_id,'');
  const id=published.body.deck_id;
  const detail=(await req('/v1/public/decks/'+id)).body;
  assert.equal(detail.deck.main_faction_id,nominal);
  assert.deepEqual(new Set(detail.cards.map(c=>c.definition.faction_id)),new Set(ids));
  assert.deepEqual(new Set(detail.factions.map(c=>c.faction_id)),new Set([...ids,nominal]));
  await f.restart();
  const restored=(await req('/v1/public/decks/'+id)).body;
  assert.equal(restored.deck.main_faction_id,nominal);assert.equal(restored.deck.ally_faction_id,'');
  assert.deepEqual(restored.deck.cards,refs);
});
test('shared decks: auth, validation, pagination, revisions, copy, withdrawal and durable restart',async t=>{
  const f=await fixture(t),{req,a,b,refs}=f;
  const body={request_id:randomUUID(),name:'测试牌组',cards:refs};
  assert.equal((await req('/v1/decks',body)).status,401);
  assert.equal((await req('/v1/decks',{...body,request_id:randomUUID(),cards:refs.slice(1)},a.access_token)).status,422);
  const excess=structuredClone(refs);excess[4]=excess[0];
  assert.equal((await req('/v1/decks',{...body,request_id:randomUUID(),cards:excess},a.access_token)).status,422);
  const invalid=structuredClone(refs);invalid[0].definition_hash='0'.repeat(64);
  assert.equal((await req('/v1/decks',{...body,request_id:randomUUID(),cards:invalid},a.access_token)).status,422);
  const first=await req('/v1/decks',body,a.access_token);assert.equal(first.status,201);
  assert.deepEqual((await req('/v1/decks',body,a.access_token)).body,first.body);
  assert.equal((await req('/v1/public/decks')).body.decks.length,1);
  assert.equal((await req('/v1/public/decks?cursor=bad')).status,400);
  const id=first.body.deck_id,detail=(await req('/v1/public/decks/'+id)).body;
  assert.equal(detail.deck.author.name,'牌组作者');assert.equal(detail.cards.length,11);assert.deepEqual(detail.deck.cards,refs);
  assert.ok(!JSON.stringify(detail).includes('owner_id')&&!JSON.stringify(detail).includes('provenance'));
  assert.equal((await req('/v1/decks',{...body,request_id:randomUUID(),deck_id:id,expected_revision:1},b.access_token)).status,404);
  assert.equal((await req('/v1/decks',{...body,request_id:randomUUID(),name:'复制牌组'},b.access_token)).status,201);
  const updated=await req('/v1/decks',{...body,request_id:randomUUID(),deck_id:id,expected_revision:1,name:'改名'},a.access_token);
  assert.equal(updated.body.revision,2);
  assert.equal((await req('/v1/decks',{...body,request_id:randomUUID(),deck_id:id,expected_revision:1},a.access_token)).status,409);
  assert.equal((await req('/v1/decks/'+id,undefined,b.access_token,'DELETE')).status,404);
  assert.equal((await req('/v1/decks/'+id,undefined,a.access_token,'DELETE')).status,200);
  assert.equal((await req('/v1/public/decks/'+id)).status,404);
  assert.equal((await req('/v1/decks?mine=1',undefined,a.access_token)).body.decks[0].published,false);
  await f.restart();
  assert.equal((await req('/v1/public/decks')).body.decks.length,1);
  assert.equal((await req('/v1/decks/'+id,undefined,a.access_token)).body.deck.name,'改名');
});
test('optional card art: normalized pixels, ownership, immutable versions, removal and old clients',async t=>{
  const {req,a,b,cards,restart}=await fixture(t);
  const png=PNG.sync.write({width:4,height:4,data:Buffer.alloc(64,200)}), body={png_base64:png.toString('base64')};
  assert.equal((await req('/v1/card-art',body)).status,401);
  assert.equal((await req('/v1/card-art',{png_base64:Buffer.from('<svg/>').toString('base64')},a.access_token)).status,422);
  const huge=Buffer.from(png);huge.writeUInt32BE(100000,16);
  assert.equal((await req('/v1/card-art',{png_base64:huge.toString('base64')},a.access_token)).status,422);
  const uploaded=await req('/v1/card-art',body,a.access_token);assert.equal(uploaded.status,201);
  const art=uploaded.body.art;
  const image=await req('/v1/card-art/'+art.id+'.png');assert.equal(image.status,200);assert.equal(createHash('sha256').update(image.body).digest('hex'),art.id);
  async function publish(token,definition,context={},imageFields={}){
    const draft=await req('/v1/card-drafts',{request_id:randomUUID(),definition},token);assert.equal(draft.status,201);
    return req(context.id?'/v1/cards/'+context.id+'/revisions':'/v1/cards',{request_id:randomUUID(),draft_id:draft.body.result.draft_id,draft_hash:draft.body.result.draft_hash,...(context.id?{base_revision:context.revision}:{}),...imageFields},token);
  }
  assert.equal((await publish(b.access_token,unit(22),{},{art_id:art.id})).status,422);
  const card=cards[0];
  const revised=await publish(a.access_token,card.definition,{id:card.card_id,revision:1},{art_id:art.id});assert.equal(revised.status,201);
  assert.equal(revised.body.definition_hash,card.definition_hash);assert.equal(revised.body.art.id,art.id);
  assert.equal((await req('/v1/cards/'+card.card_id+'?revision=1',undefined,a.access_token)).body.art,undefined);
  assert.equal((await publish(b.access_token,unit(22),{},{art_id:art.id})).status,201);
  const inherited=await publish(a.access_token,card.definition,{id:card.card_id,revision:2});assert.equal(inherited.body.art.id,art.id);
  const removed=await publish(a.access_token,card.definition,{id:card.card_id,revision:3},{art_id:null});assert.equal(removed.body.art,undefined);
  assert.equal((await req('/v1/cards/'+card.card_id+'?revision=2',undefined,a.access_token)).body.art.id,art.id);
  await restart();assert.equal((await req('/v1/card-art/'+art.id+'.png')).status,200);
});


test('HQ shared references survive restart and bundle import separately from forty cards',async t=>{
 const f=await fixture(t),{req,a,refs}=f;
 const definition={...unit('总部'),kind:'hq',unit_class:null,cost:0,attack:0,operation_cost:0,health:30,draw_rule:{base:1},appearance:{emblem:'hq'}};
 const sync=await req('/v1/card-sync',{request_id:randomUUID(),cards:[{local_card_id:'hq',definition,definition_hash:hash(definition)}],keywords:[]},a.access_token);assert.equal(sync.status,200,JSON.stringify(sync));
 const h=sync.body.cards[0],headquarters={card_id:h.card_id,revision:h.revision,definition_hash:h.definition_hash};
 const p=await req('/v1/decks',{request_id:randomUUID(),name:'携带总部',cards:refs,headquarters},a.access_token);assert.equal(p.status,201,JSON.stringify(p));
 const id=p.body.deck_id;
 await f.restart();
 const detail=(await req('/v1/public/decks/'+id)).body;
 assert.equal(detail.deck.cards.length,40);assert.deepEqual(detail.deck.headquarters,headquarters);assert.equal(detail.cards.filter(c=>c.definition.kind==='hq').length,1);assert.equal(detail.cards.find(c=>c.definition.kind==='hq').definition.health,30);
 assert.equal((await req('/v1/decks',{request_id:randomUUID(),name:'假总部',cards:refs,headquarters:refs[0]},a.access_token)).status,422);
 const draft=await req('/v1/card-drafts',{request_id:randomUUID(),definition:{...definition,health:35}},a.access_token);assert.equal(draft.status,201);
 const revision=await req('/v1/cards/'+h.card_id+'/revisions',{request_id:randomUUID(),base_revision:1,draft_id:draft.body.result.draft_id,draft_hash:draft.body.result.draft_hash},a.access_token);assert.equal(revision.status,201);
 const updated=(await req('/v1/public/decks/'+id)).body;
 assert.equal(updated.deck.headquarters.revision,2);assert.equal(updated.cards.find(c=>c.definition.kind==='hq').definition.health,35);assert.equal(updated.deck.cards.length,40);
 assert.deepEqual(f.app.service.store.state.shared_decks[id].headquarters,headquarters);
});

test('deck sin pair is nominal, persists, and shared copies follow published revisions without rewriting history',async t=>{
 const f=await fixture(t),{req,a,refs,cards}=f;
 const body={request_id:randomUUID(),name:'双罪孽构筑',cards:refs,main_sin:'wrath',ally_sin:'gloom'};
 const p=await req('/v1/decks',body,a.access_token);assert.equal(p.status,201);assert.equal(p.body.ally_sin,'gloom');
 assert.equal((await req('/v1/decks',{...body,request_id:randomUUID(),ally_sin:'wrath'},a.access_token)).status,422);
 assert.equal((await req('/v1/decks',{...body,request_id:randomUUID(),ally_sin:'invalid'},a.access_token)).status,422);
 const legacy={...body,request_id:randomUUID(),deck_id:p.body.deck_id,expected_revision:1};delete legacy.ally_sin;
 const legacyResult=await req('/v1/decks',legacy,a.access_token);assert.equal(legacyResult.status,201);assert.equal(legacyResult.body.ally_sin,'gloom');
 const previous=structuredClone(f.app.service.store.state.shared_decks[p.body.deck_id]);
 const old=cards[0];
 const draft=await req('/v1/card-drafts',{request_id:randomUUID(),definition:{...old.definition,attack:7,cost:4,rarity:'elite',sin:'envy'}},a.access_token);
 assert.equal(draft.status,201);
 const revised=await req('/v1/cards/'+old.card_id+'/revisions',{request_id:randomUUID(),base_revision:1,draft_id:draft.body.result.draft_id,draft_hash:draft.body.result.draft_hash},a.access_token);
 assert.equal(revised.status,201);
 const detail=await req('/v1/public/decks/'+p.body.deck_id);assert.equal(detail.status,200);
 assert.equal(detail.body.deck.cards.length,40);assert.equal(detail.body.deck.cards.filter(r=>r.card_id===old.card_id&&r.revision===2).length,4);
 assert.equal(detail.body.cards.find(r=>r.card_id===old.card_id).definition.attack,7);
 assert.ok(detail.body.deck.validation_error,'Rarity changes remain visible as editable draft without silently dropping copies');
 assert.deepEqual(f.app.service.store.state.shared_decks[p.body.deck_id],previous,'Read updates do not mutate shared history');
 assert.equal((await req('/v1/cards/'+old.card_id+'?revision=1',undefined,a.access_token)).body.definition_hash,old.definition_hash);
 await f.restart();
 const restored=(await req('/v1/public/decks/'+p.body.deck_id)).body;
 assert.equal(restored.deck.ally_sin,'gloom');assert.equal(restored.deck.cards[0].revision,2);
});
