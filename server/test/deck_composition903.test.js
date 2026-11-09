import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {deckComposition} from '../src/deck_rules.js';
import {CentralMatches} from '../src/central_matches.js';
import {createApp} from '../src/index.js';
import {compileCard} from '../src/validation.js';
import {freshCard} from '../../web/model.mjs';
import {FACTION_ID,seedFactions} from './faction_fixture.js';

test('30/10 quota and faction categories apply to every card kind and partial builds',()=>{
 const registry={large:{category:'large'},normal:{},small:{category:'small'}};
 const make=(n=30)=>Array.from({length:40},(_,i)=>({name:'卡'+i,sin:i<n?'wrath':'gloom',faction_id:i<n?'large':'small',kind:['unit','order','counter','field'][i%4]}));
 assert.equal(deckComposition(make(),registry,'wrath','gloom').error,'');
 for(const n of [0,29,31,40])assert(deckComposition(make(n),registry,'wrath','gloom').error);
 const cards=make();cards[0].faction_id='small';assert.match(deckComposition(cards,registry,'wrath','gloom').error,/小阵营/);
 cards[0].faction_id='large';cards[39].faction_id='large';assert.match(deckComposition(cards,registry,'wrath','gloom').error,/大阵营/);
 cards.forEach(d=>d.faction_id='normal');assert.equal(deckComposition(cards,registry,'wrath','gloom').error,'');
 delete cards[0].faction_id;assert.equal(deckComposition(cards,registry,'wrath','gloom').error,'');
 cards[0].sin='envy';assert.match(deckComposition(cards,registry,'wrath','gloom').error,/主、副罪孽/);
 for(const sin of [null,undefined,'']){cards[0].sin=sin;assert.equal(deckComposition(cards,registry,'wrath','gloom').error,'');}
 const neutral=make().map(d=>({...d,sin:null}));assert.equal(deckComposition(neutral,registry,'wrath','gloom').error,'');
 for(const pair of [['',''],['wrath','wrath'],['wrath',''],['greed','gloom']])assert(deckComposition(make(),registry,...pair).error);
 assert.equal(deckComposition(make().slice(0,4),registry,'wrath','gloom',false).error,'');
 assert(deckComposition(make().slice(0,4),registry,'wrath','gloom',true).error);
 const excess=make();excess.push({...excess[0]});assert.match(deckComposition(excess,registry,'wrath','gloom',false).error,/30张/);
 const bad=make();bad[0].faction_id='missing';assert.match(deckComposition(bad,registry,'wrath','gloom').error,/阵营不存在/);
 bad[0].kind='hq';assert.match(deckComposition(bad,registry,'wrath','gloom').error,/总部/);
});

test('faction editor, shared decks and authority enforce composition without altering existing decks',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'composition903-'));
 const app=await createApp({dataDir:dir,centralMode:true,registrationMode:'open',inviteToken:'composition-test-only-123456789',matches:false,provider:{configured:false},host:'127.0.0.1',port:0});
 t.after(async()=>{await app.close();await rm(dir,{recursive:true,force:true});});
 const address=await app.listen(0),origin=`http://127.0.0.1:${address.port}`;
 const request=async(path,body,token,method=body?'POST':'GET')=>{const r=await fetch(origin+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};};
 const a=(await request('/v1/accounts/register',{username:'组牌作者',password:'test-only-903-password'})).data;
 const b=(await request('/v1/accounts/register',{username:'另一作者',password:'test-only-903-password'})).data;
 await seedFactions(app.service.store);
 const store=app.service.store,refs=[];
 await store.transaction(s=>{
  s.factions[FACTION_ID].owner_id=a.owner_id;
  for(let i=0;i<11;i++){
   const card={card_id:randomUUID(),revision:1,owner_id:a.owner_id,series:1,created_at:new Date().toISOString(),...compileCard({...freshCard(),name:'组合'+i,faction_id:FACTION_ID,sin:i<8?'wrath':'gloom'},s.keywords)};
   s.cards[card.card_id]=[card];for(let j=0;j<(i===7||i===10?2:4);j++)refs.push({card_id:card.card_id,revision:1,definition_hash:card.definition_hash});
  }
 });
 const publish={request_id:randomUUID(),name:'双罪孽牌组',cards:refs,main_sin:'wrath',ally_sin:'gloom'};
 const saved=await request('/v1/decks',publish,a.access_token);assert.equal(saved.status,201,JSON.stringify(saved));
 assert.equal((await request('/v1/decks',{...publish,request_id:randomUUID(),ally_sin:'envy'},a.access_token)).status,422);
 const previous=structuredClone(store.state.shared_decks[saved.data.deck_id]);
 const factions=(await request('/v1/factions',undefined,a.access_token)).data.factions;
 assert.equal(factions.find(f=>f.faction_id===FACTION_ID).category,'normal','legacy roles do not imply new faction category');
 const patch={request_id:randomUUID(),name:'阵营分类测试',color:'#334455',icon_id:null,category:'large',base_revision:store.state.factions[FACTION_ID].revision};
 assert.equal((await request('/v1/factions/'+FACTION_ID,patch,b.access_token,'PATCH')).status,404);
 assert.equal((await request('/v1/factions/'+FACTION_ID,{...patch,category:'unknown'},a.access_token,'PATCH')).status,400);
 assert.equal((await request('/v1/factions/'+FACTION_ID,patch,a.access_token,'PATCH')).status,200);
 const detail=(await request('/v1/public/decks/'+saved.data.deck_id)).data;
 assert.match(detail.deck.validation_error,/大阵营/);assert.deepEqual(store.state.shared_decks[saved.data.deck_id],previous,'invalid existing deck remains editable');
 const central=new CentralMatches({store});t.after(()=>central.close());
 const create=()=>central.handle({method:'POST',pathname:'/v1/rooms',owner:a.owner_id,clientBuild:906,body:{request_id:randomUUID(),deck:refs,main_sin:'wrath',ally_sin:'gloom'}});
 await assert.rejects(create(),e=>e.code==='INVALID_DECK'&&/大阵营/.test(e.message));
 const normal={...patch,category:'normal',request_id:randomUUID(),base_revision:patch.base_revision+1};
 assert.equal((await request('/v1/factions/'+FACTION_ID,normal,a.access_token,'PATCH')).status,200);
 const created=await create();assert.equal(created.status,201);
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms/'+created.body.room_id+'/join',owner:b.owner_id,clientBuild:906,body:{request_id:randomUUID(),deck:refs,main_sin:'wrath',ally_sin:'envy'}}),e=>e.code==='INVALID_DECK');
 assert.equal((await request('/v1/public/decks/'+saved.data.deck_id)).data.deck.validation_error,'');
});
