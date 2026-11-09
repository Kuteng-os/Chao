import {FACTION_ID, seedFactions} from './faction_fixture.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createApp} from '../src/index.js';
import {ADMIN_NAMES} from '../src/accounts.js';
const password='test-only-password-123',nextPassword='different-password-456',invite='account-test-invitation-not-production';
const provider={configured:false,model:'test',async generate(){throw Error('No model calls');}};
const card=(cost=1)=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name:'test',faction_id:FACTION_ID,flavor_text:'',kind:'unit',unit_class:'infantry',cost,operation_cost:1,attack:10,health:3,keywords:[{id:'core.guard',version:1,params:{}}],play_target:null,abilities:[],tokens:[],appearance:{emblem:'infantry'}});
const keyword=()=>({schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.test_draw',version:1,name:'补给',aliases:[],description:'抽一张牌',parameters:{},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]}});
async function setup(t){
  const dir=await mkdtemp(join(tmpdir(),'frontline-accounts-'));let app,base;
  async function start(){app=await createApp({dataDir:dir,centralMode:true,inviteToken:invite,registrationMode:'open',matches:false,provider,host:'127.0.0.1',port:0});await seedFactions(app.service.store);const a=await app.listen();base=`http://127.0.0.1:${a.port}`;}
  await start();t.after(async()=>{await app.close();await rm(dir,{recursive:true,force:true});});
  const request=async(path,body,session)=>{const r=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(session?{Authorization:`Bearer ${session.access_token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return {status:r.status,body:await r.json()};};
  const register=async username=>{const r=await request('/v1/accounts/register',{username,password});assert.equal(r.status,201,JSON.stringify(r));return r.body;};
  const admins=async()=>{await app.auth.accounts.bootstrap(ADMIN_NAMES.map(username=>({username,password})));const sessions=[];for(const username of ADMIN_NAMES){const s=(await request('/v1/accounts/login',{username,password})).body;const r=await request('/v1/account/password',{current_password:password,new_password:nextPassword},s);assert.equal(r.status,200);sessions.push(r.body);}return sessions;};
  const publish=async(session,definition=card(),id=null,revision=null)=>{const d=await request('/v1/card-drafts',{request_id:randomUUID(),definition},session);assert.equal(d.status,201,JSON.stringify(d));return request(id?`/v1/cards/${id}/revisions`:'/v1/cards',{request_id:randomUUID(),draft_id:d.body.result.draft_id,draft_hash:d.body.result.draft_hash,...(id?{base_revision:revision}:{})},session);};
  return {get app(){return app;},request,register,admins,publish,dir,async restart(){await app.close();await start();}};
}
test('open registration, Chinese names, normalized uniqueness, reserved admins and hashed persistence',async t=>{
  const s=await setup(t);assert.equal((await s.request('/v1/account-options')).body.registration,'open');
  const player=await s.register('普通玩家');assert.equal(player.role,'player');assert.equal(player.must_change_password,false);
  const latin=await s.register('Player_One');assert.equal((await s.request('/v1/accounts/register',{username:'ｐｌａｙｅｒ_ｏｎｅ',password})).status,409);
  for(const username of ADMIN_NAMES)assert.equal((await s.request('/v1/accounts/register',{username,password})).status,409);
  for(const username of ['__proto__','constructor','prototype'])assert.equal((await s.request('/v1/accounts/register',{username,password})).status,400);
  assert.equal((await s.request('/v1/accounts/register',{username:'提权',password,role:'admin'})).status,400);
  assert.equal((await s.request('/v1/accounts/login',{username:'普通玩家',password:'incorrect password'})).status,401);
  assert.equal((await s.request('/v1/accounts/login',{username:'不存在',password})).status,401);
  const disk=await readFile(join(s.dir,'store.json'),'utf8');assert(!disk.includes(password));assert(!disk.includes(player.access_token));assert.match(disk,/scrypt-32768-8-1/);
  await s.restart();const login=await s.request('/v1/accounts/login',{username:'PLAYER_ONE',password});assert.equal(login.status,200);assert.equal(login.body.owner_id,latin.owner_id);
  const expiry=Object.values(s.app.service.store.state.sessions).find(e=>e.owner_id===login.body.owner_id);assert(expiry.expires_at);
});
test('binding legacy game identity preserves cards and invalidates old sessions and browser links',async t=>{
  const s=await setup(t),old=(await s.request('/v1/sessions',{invite_code:invite,display_name:'旧玩家'})).body;
  const published=await s.publish(old);const code=(await s.request('/v1/browser-sessions',{},old)).body.code;
  const bound=await s.request('/v1/account/link',{username:'绑定玩家',password},old);assert.equal(bound.status,201);assert.equal(bound.body.owner_id,old.owner_id);
  assert.equal((await s.request('/v1/me',undefined,old)).status,401);assert.equal((await s.request('/v1/browser-sessions/exchange',{code})).status,401);
  const view=(await s.request('/v1/cards',undefined,bound.body)).body.cards;assert.equal(view[0].card_id,published.body.card_id);assert.equal(view[0].owned_by_me,true);
  const login=(await s.request('/v1/accounts/login',{username:'绑定玩家',password})).body;assert.equal(login.owner_id,old.owner_id);
  const pairing=(await s.request('/v1/browser-sessions',{},login)).body.code;
  const browser=(await s.request('/v1/browser-sessions/exchange',{code:pairing})).body;assert.equal(browser.owner_id,old.owner_id);assert.equal(browser.username,'绑定玩家');
});
test('configured administrators are idempotently provisioned; initial passwords restrict writes until changed',async t=>{
  const s=await setup(t),entries=ADMIN_NAMES.map(username=>({username,password}));assert(ADMIN_NAMES.includes('ovo'));assert.equal((await s.request('/v1/accounts/register',{username:'OVO',password})).status,409);
  assert.deepEqual((await s.app.auth.accounts.bootstrap(entries)).created,ADMIN_NAMES);assert.deepEqual((await s.app.auth.accounts.bootstrap(entries)).created,[]);
  for(const username of ADMIN_NAMES){const login=(await s.request('/v1/accounts/login',{username,password})).body;assert.equal(login.role,'admin');assert.equal(login.must_change_password,true);
    assert.equal((await s.request('/v1/card-drafts',{request_id:randomUUID(),definition:card()},login)).body.error.code,'PASSWORD_CHANGE_REQUIRED');
    assert.equal((await s.request('/v1/admin/accounts',undefined,login)).status,403);
    assert.equal((await s.request('/v1/account/password',{current_password:password,new_password:password},login)).status,400);
    const changed=(await s.request('/v1/account/password',{current_password:password,new_password:nextPassword},login));assert.equal(changed.status,200);assert.equal(changed.body.must_change_password,false);
    assert.equal((await s.request('/v1/me',undefined,login)).status,401);assert.equal((await s.request('/v1/admin/accounts',undefined,changed.body)).status,200);
  }
});
test('admins revise other authors cards and keyword metadata without taking ownership or changing history',async t=>{
  const s=await setup(t),author=await s.register('原作者'),other=await s.register('其他玩家'),admins=await s.admins();
  const first=(await s.publish(author)).body;
  assert.equal(first.author.name,'原作者');assert.notEqual(first.author.id,author.owner_id);
  assert.equal((await s.publish(other,card(2),first.card_id,1)).status,404);
  for(let i=0;i<admins.length;i++){const update=await s.publish(admins[i],card(i+2),first.card_id,i+1);assert.equal(update.status,201);assert.equal(update.body.owner_id,author.owner_id);}
  assert.equal(s.app.service.store.state.cards[first.card_id][0].definition.cost,1);
  const adminView=(await s.request('/v1/cards',undefined,admins[0])).body.cards[0];assert.equal(adminView.can_edit,true);assert.equal(adminView.owned_by_me,false);assert(!('provenance' in adminView));
  assert.equal(adminView.author.name,'原作者');assert.equal(adminView.author.id,first.author.id);
  const history=(await s.request(`/v1/cards/${first.card_id}?revision=1`,undefined,other)).body;
  assert.deepEqual(history.author,adminView.author);assert.equal(history.definition.cost,1);
  assert.equal((await s.request('/v1/cards',undefined,other)).body.cards[0].can_edit,false);
  const k=keyword(),p=(await s.request('/v1/keyword-imports',{request_id:randomUUID(),definition:k},author)).body;
  assert.equal((await s.request(`/v1/keyword-proposals/${p.proposal_id}/confirm`,{request_id:randomUUID(),expected_revision:p.revision,candidate_hash:p.candidate_hash},author)).status,201);
  const updated={...k,version:2,name:'补给改名',description:'登场时抽一张牌。'};
  assert.equal((await s.request('/v1/keyword-imports',{request_id:randomUUID(),definition:updated},other)).status,409);
  const edit=(await s.request('/v1/keyword-imports',{request_id:randomUUID(),definition:updated},admins[1])).body;
  assert.equal((await s.request(`/v1/keyword-proposals/${edit.proposal_id}/confirm`,{request_id:randomUUID(),expected_revision:edit.revision,candidate_hash:edit.candidate_hash},admins[1])).status,201);
  const state=s.app.service.store.state;assert.equal(state.keywords[k.id+'@2'].owner_id,author.owner_id);assert.equal(state.keywords[k.id+'@1'].definition.name,k.name);assert.equal(JSON.stringify(state.keywords[k.id+'@1'].definition.implementation),JSON.stringify(state.keywords[k.id+'@2'].definition.implementation));
  const defs=(await s.request('/v1/keywords',undefined,admins[1])).body.definitions;assert.equal(defs.find(e=>e.definition.id==='core.guard').can_edit,false);assert.equal(defs.find(e=>e.definition.id===k.id).can_edit,true);
  assert.equal(state.account_audit.filter(e=>e.action==='admin_card_revision').length,ADMIN_NAMES.length);
});
test('reset revokes every device and pairing code, returns temporary password once, forbids ordinary players',async t=>{
  const s=await setup(t),player=await s.register('密码测试'),admin=(await s.admins())[0];
  const second=(await s.request('/v1/accounts/login',{username:'密码测试',password})).body;
  const pairing=(await s.request('/v1/browser-sessions',{},player)).body.code;
  assert.equal((await s.request('/v1/admin/password-reset',{owner_id:admin.owner_id},player)).status,403);
  assert.equal((await s.request('/v1/admin/accounts',undefined,player)).status,403);
  const reset=await s.request('/v1/admin/password-reset',{owner_id:player.owner_id},admin);assert.equal(reset.status,200);
  for(const old of [player,second])assert.equal((await s.request('/v1/me',undefined,old)).status,401);
  assert.equal((await s.request('/v1/browser-sessions/exchange',{code:pairing})).status,401);
  assert.equal((await s.request('/v1/accounts/login',{username:'密码测试',password})).status,401);
  const temporary=(await s.request('/v1/accounts/login',{username:'密码测试',password:reset.body.temporary_password})).body;assert.equal(temporary.must_change_password,true);
  const changed=(await s.request('/v1/account/password',{current_password:reset.body.temporary_password,new_password:nextPassword},temporary)).body;
  const disk=await readFile(join(s.dir,'store.json'),'utf8');assert(!disk.includes(reset.body.temporary_password));
  const listing=await s.request('/v1/admin/accounts',undefined,admin);assert(!JSON.stringify(listing).includes('scrypt'));assert(!JSON.stringify(listing).includes('temporary_password'));
  assert.equal((await s.request('/v1/logout',{},changed)).status,200);assert.equal((await s.request('/v1/me',undefined,changed)).status,401);
});
test('negative deployment cost reports exact field; invalid draw produces no unrelated branch errors',async t=>{
  const s=await setup(t),player=await s.register('数值测试');let r=await s.request('/v1/card-drafts',{request_id:randomUUID(),definition:card(-1)},player);
  assert.equal(r.status,422);assert.equal(r.body.error.message,'部署费用不能小于 0。');assert.deepEqual(r.body.error.details,[{path:'/cost',code:'INVALID_SCHEMA',message:'部署费用不能小于 0。'}]);
  assert.equal((await s.request('/v1/card-drafts',{request_id:randomUUID(),definition:card(0)},player)).status,201);
  const c=card();c.abilities=[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:0}]}];r=await s.request('/v1/card-drafts',{request_id:randomUUID(),definition:c},player);assert.equal(r.status,422);assert.match(r.body.error.message,/效果组 1 · 效果 1 · 数量不能小于 1/);assert.equal(r.body.error.details.length,1);
});
