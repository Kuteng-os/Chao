import {ruleCapabilities} from '../src/rule_capabilities.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createApp} from '../src/index.js';
import {compileCard} from '../src/validation.js';
import {FACTION_ID,factionFixture} from './faction_fixture.js';
import {MatchArchive,summarizeMatch} from '../src/match_archive.js';

test('authoritative battle persists private history and public versioned metrics exactly once',{skip:!process.env.GODOT_BIN,timeout:45000},async t=>{
 const dir=await mkdtemp(join(tmpdir(),'frontline-stats-'));
 let app=await createApp({centralMode:true,inviteToken:'a'.repeat(32),dataDir:dir,godotBin:process.env.GODOT_BIN});
 let address=await app.listen(0),url=`http://127.0.0.1:${address.port}`;
 t.after(async()=>{await app.close();await rm(dir,{recursive:true,force:true});});
 const request=async(token,path,body,method=body?'POST':'GET')=>{const response=await fetch(url+path,{method,headers:{'Content-Type':'application/json','X-Frontline-Client-Build':String(ruleCapabilities.battle_rules.minimum_client_build),...(token?{authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
 const accounts=[];for(let i=0;i<3;i++){const r=await request(null,'/v1/accounts/register',{username:'stat-private-'+i,password:'analysis-password-123'});assert.equal(r.status,201);accounts.push(r.data);}
 const profile=await request(accounts[0].access_token,'/v1/profile',{display_name:'新昵称',avatar:'wings',avatar_color:'#aaccee',bio:'统计测试'},'PATCH');assert.equal(profile.status,200);assert.equal(profile.data.username,'stat-private-0');assert.equal((await request(accounts[0].access_token,'/v1/me')).data.avatar,'wings');
 assert.equal((await request(accounts[0].access_token,'/v1/profile',{display_name:'x',avatar:'invalid',avatar_color:'#aaccee',bio:''},'PATCH')).status,422);
 const refs=[];await app.service.store.transaction(state=>{state.factions[FACTION_ID]=factionFixture();for(let i=0;i<10;i++){const id=randomUUID(),definition={schema_version:'1.0.0',ruleset_version:'frontline-1',name:'统计指令'+i,flavor_text:'',kind:'order',unit_class:null,cost:1,operation_cost:0,attack:0,health:0,keywords:[],play_target:null,abilities:[{trigger:'on_play',effects:[{op:'gain_kredits',amount:1},{op:'damage',target:'enemy_hq',amount:7}]}],tokens:[],appearance:{emblem:'order'},faction_id:FACTION_ID};const c={card_id:id,revision:1,...compileCard(definition,state.keywords)};state.cards[id]=[c];for(let j=0;j<4;j++)refs.push({card_id:id,revision:1,definition_hash:c.definition_hash});}});
 const a=accounts[0].access_token,b=accounts[1].access_token;
 const created=await request(a,'/v1/rooms',{request_id:randomUUID(),deck:refs,main_sin:'wrath',ally_sin:'gloom'});assert.equal(created.status,201);const id=created.data.room_id;
 assert.equal((await request(b,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:refs,main_sin:'wrath',ally_sin:'gloom'})).status,200);
 assert.equal((await request(a,`/v1/me/matches/${id}`)).status,409);
 for(const [seat,playerToken] of [a,b].entries()){
  const opening=(await request(playerToken,`/v1/rooms/${id}/state`)).data;
  const swap=await request(playerToken,`/v1/rooms/${id}/actions`,{action_id:randomUUID(),expected_state_seq:opening.state_seq,command:{type:'mulligan',hand_ids:seat===0?[opening.state.players[0].hand[0].instance_id]:[]}});
  assert.equal(swap.data.action_result.accepted,true,JSON.stringify(swap.data));
 }
 let state=(await request(a,`/v1/rooms/${id}/state`)).data,seat=state.state.active_player,token=accounts[seat].access_token;
 state=(await request(token,`/v1/rooms/${id}/state`)).data;
 let first=true;
 while(state.state.winner===-1){const action={action_id:randomUUID(),expected_state_seq:state.state_seq,command:{type:'play',hand_id:state.state.players[seat].hand[0].instance_id}};const result=await request(token,`/v1/rooms/${id}/actions`,action);assert.equal(result.data.action_result.accepted,true);state=result.data;if(first){const repeated=await request(token,`/v1/rooms/${id}/actions`,action);assert.equal(repeated.data.state_seq,state.state_seq);first=false;}}
 const history=(await request(a,`/v1/me/matches/${id}`)).data;assert.equal(history.status,'ended');assert.equal(history.players[seat].totals.hq_damage,20);assert.equal(history.players[seat].totals.overkill,1);assert.equal(history.players[seat].totals.play,3);assert(!JSON.stringify(history.players).includes('owner_id'));assert(history.events.some(e=>e.kind==='opening_draw'));
 assert.equal(history.events.filter(e=>e.kind==='opening_draw').length,9,'kept opening hands counted exactly once');
 assert.equal((await request(accounts[2].access_token,`/v1/me/matches/${id}`)).status,404);assert.equal((await request(null,'/v1/me/matches')).status,401);
 const stats=(await request(null,'/v1/public/statistics?days=0')).data;assert.equal(stats.matches,1);assert.equal(stats.totals.play,3);assert.equal(stats.cards.reduce((n,c)=>n+c.hq_damage,0),20);assert(!JSON.stringify(stats).includes('stat-private'));assert(!JSON.stringify(stats).includes(accounts[0].owner_id));assert(stats.cards.every(c=>c.revision===1&&c.games===2&&c.win_rate===50));
 assert.equal((await request(token,'/v1/me/statistics?days=0')).data.wins,1);
 await app.close();app=await createApp({centralMode:true,inviteToken:'a'.repeat(32),dataDir:dir,godotBin:process.env.GODOT_BIN});address=await app.listen(0);url=`http://127.0.0.1:${address.port}`;assert.equal((await request(a,'/v1/me/matches')).data.total,1);assert.equal((await request(null,'/v1/public/statistics?days=0')).data.totals.play,3);
});

test('generated contributions keep original version attribution without inflating ordinary plays',()=>{
 const ref={card_id:'maker',revision:2,definition_hash:'makerhash',name:'母卡',kind:'unit'};
 const events=['play','create','generated_play','generated_deploy'].map(kind=>({kind,owner:0,amount:1,card_ref:ref,definition_hash:ref.definition_hash,generated:kind!=='play',generated_token_id:'child'}));
 events.push({kind:'damage',owner:0,target_owner:1,amount:3,attempted:3,hq:true,card_ref:ref,generated:true});
 const s=summarizeMatch({players:[{owner_id:'a'},{owner_id:'b'}],decks:[[ref],[]],events});
 assert.equal(s.players[0].totals.play,1);assert.equal(s.players[0].totals.generated_play,1);assert.equal(s.players[0].cards[0].generated_deploy,1);assert.equal(s.players[0].cards[0].hq_damage,3);assert.equal(s.players[0].cards[0].revision,2);
});

test('aborted matches and truncated telemetry never inflate win rates; versions remain separate',()=>{
 const record={match_id:randomUUID(),players:[{owner_id:'a',display_name:'A'},{owner_id:'b',display_name:'B'}],decks:[[{card_id:'one',revision:1,definition_hash:'x',name:'牌',faction_id:'f',kind:'unit'}],[{card_id:'one',revision:2,definition_hash:'y',name:'牌',faction_id:'f',kind:'unit'}]],events:[],status:'ended',winner:0,started_at:new Date().toISOString(),first_player:0,turns:5,duration_seconds:40};
 const store={directory:tmpdir(),state:{factions:{f:{name:'阵营'}},match_index:{a:summarizeMatch(record),b:summarizeMatch({...record,status:'aborted'}),c:summarizeMatch({...record,telemetry_truncated:true})}}};const archive=new MatchArchive(store);const stats=archive.stats(new URLSearchParams('days=0'));assert.equal(stats.matches,1);assert.equal(stats.excluded,2);assert.equal(stats.cards.length,2);assert.deepEqual(stats.cards.map(c=>c.win_rate).sort(),[0,100]);assert.equal(archive.stats(new URLSearchParams('min_games=2')).cards.length,0);assert.throws(()=>archive.stats(new URLSearchParams('days=-1')));
});
