import {ruleCapabilities} from '../src/rule_capabilities.js';
import test from 'node:test';
import {FACTION_ID,factionFixture} from './faction_fixture.js';
import assert from 'node:assert/strict';
import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {CentralMatches, GodotBattleWorker, godotRuntimeEnvironment} from '../src/central_matches.js';
import {compileCard, validateKeyword, docsURL} from '../src/validation.js';
import {ApiError, strictParse} from '../src/codec.js';

const enabled = Boolean(process.env.GODOT_BIN);
test('CZ-287 chosen intel keeps hidden identities private across HTTP, spectators and retries', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks}=await fixture(t,{definitionFactory:name=>({...card(name),kind:'order',unit_class:null,cost:0,operation_cost:0,attack:0,health:0,keywords:[],appearance:{emblem:'order'},abilities:[{trigger:'on_play',effects:[{op:'intel',amount:1,selection:'chosen'},{op:'draw',player:'owner',amount:1}]}]})});
 const room=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body;
 const path='/v1/rooms/'+room.room_id;
 assert.equal((await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]})).status,200);
 const state=async seat=>{central.rates.clear();return (await request(seat,path+'/state')).body;};
 const seat=(await state(0)).state.active_player,enemy=1-seat;
 const original=await state(seat),other=await state(enemy),selected=other.state.players[enemy].hand[1].card;
 const act=async command=>{const s=await state(seat),body={action_id:randomUUID(),expected_state_seq:s.state_seq,command};const response=await request(seat,path+'/actions',body);assert.equal(response.status,200);assert.equal(response.body.action_result.accepted,true,JSON.stringify(response.body));return {body,result:response.body};};
 const pending=(await act({type:'play',hand_id:original.state.players[seat].hand[0].instance_id})).result;
 const choice=pending.state.pending_choice;
 assert.equal(choice.kind,'intel');assert.equal(choice.options.length,other.state.players[enemy].hand.length);
 assert.deepEqual(choice.options,choice.options.map((_,i)=>({hidden:true,hand_position:i})));
 assert.deepEqual(pending.state.players[enemy].hand,[]);
 assert(!JSON.stringify(pending).includes(enemy===0?'ALPHA_private':'BRAVO_private'));
 assert(!(await state(enemy)).state.pending_choice.options);
 const watched=(await request(2,path+'/watch',{seat},'POST',906)).body;
 assert.deepEqual(watched.state.pending_choice.options,choice.options);
 assert.deepEqual(watched.state.players[enemy].hand,[]);
 const reconnect=await state(seat);assert.deepEqual(reconnect.state.pending_choice,choice);
 const foreign=await request(enemy,path+'/actions',{action_id:randomUUID(),expected_state_seq:reconnect.state_seq,command:{type:'choose_card',choice_id:choice.choice_id,option_index:1}});
 assert.equal(foreign.body.action_result.accepted,false);
 const {result,body}=await act({type:'choose_card',choice_id:choice.choice_id,option_index:1});
 assert(!result.state.pending_choice);
 assert.deepEqual(result.state.players[enemy].revealed_hand,[{position:1,card:selected}]);
 assert.equal(result.state.players[seat].deck_count,original.state.players[seat].deck_count-1);
 const retry=(await request(seat,path+'/actions',body)).body;
 assert.equal(retry.state_seq,result.state_seq);assert.deepEqual(retry.state.players,result.state.players);
});

test('906 authoritative move creates one enhanced copy with fixed frontline cost and idempotent retry', {skip:!enabled,timeout:30000},async t=>{
 const front={test:'unit_state',target:'self',state:'in_front'};
 const {central,request,decks,owners}=await fixture(t,{definitionFactory:name=>({...card(name),cost:0,operation_cost:1,abilities:[{trigger:'after_move',premise:front,effects:[{op:'transfer_card',source:'self',mode:'copy',destination:'support',selection:'random',amount:1,copy_buff:{attack_delta:2,health_delta:2,duration:'battle'}}]},{trigger:'while_active',premise:front,effects:[{op:'modify_operation_cost',target:'self',cost_set:0,duration:'battle'}]}]})});
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],clientBuild:905,body:{request_id:randomUUID(),deck:decks[0]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 const room=await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]});assert.equal(room.status,201);
 const path='/v1/rooms/'+room.body.room_id;assert.equal((await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]})).status,200);
 const state=async seat=>{central.rates.clear();return (await request(seat,path+'/state')).body;};
 const seat=(await state(0)).state.active_player;
 const act=async(actor,command)=>{const s=await state(actor),body={action_id:randomUUID(),expected_state_seq:s.state_seq,command};const res=await request(actor,path+'/actions',body);assert.equal(res.status,200);assert.equal(res.body.action_result.accepted,true,JSON.stringify(res.body));return {body,result:res.body};};
 await act(seat,{type:'play',hand_id:(await state(seat)).state.players[seat].hand[0].instance_id});
 const uid=(await state(seat)).state.units[0].uid;
 await act(seat,{type:'end_turn'});await act(1-seat,{type:'end_turn'});
 const before=await state(seat);const moved=await act(seat,{type:'move',uid});
 const units=moved.result.state.units;assert.equal(units.length,2);
 const source=units.find(u=>u.uid===uid),copy=units.find(u=>u.uid!==uid);
 assert.equal(source.row,'front');assert.equal(source.operation_cost,0);
 assert.equal(copy.row,'support');assert.equal(copy.attack,source.attack+2);assert.equal(copy.hp,source.max_hp+2);
 assert.deepEqual(copy.card.definition.abilities,source.card.definition.abilities);
 assert.equal(moved.result.state.players[seat].credits,before.state.players[seat].credits-1);
 const retry=(await request(seat,path+'/actions',moved.body)).body;assert.equal(retry.state_seq,moved.result.state_seq);assert.deepEqual(retry.state.units,units);
 const other=await state(1-seat);assert.deepEqual(other.state.units,units);assert.deepEqual(other.state.players[seat].hand,[]);
});
test('multi-unit selection accepts finish, rejects foreign choices and replays once', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks}=await fixture(t,{definitionFactory:name=>({...card(name),kind:'order',unit_class:null,cost:0,operation_cost:0,attack:0,health:0,keywords:[],appearance:{emblem:'order'},abilities:[{trigger:'on_play',effects:[{op:'summon',token_id:'jade',amount:2,row:'support'},{op:'select_units',side:'ally',min:0,max:2,unit_filter:{name_contains:'玉石'}},{op:'destroy',target:'selected_units'},{op:'transfer_card',source:'discard',destination:'support',mode:'move',selection:'random',amount:{stat:'selected_destroyed_count'},filter:{kind:'unit',name_contains:'玉石'}}]}],tokens:[{token_id:'jade',name:'玉石',unit_class:'tank',attack:1,health:2,keywords:[]}]})});
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,id=created.room_id;
 assert.equal((await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1]})).status,200);
 const state=async seat=>{central.rates.clear();return (await request(seat,`/v1/rooms/${id}/state`)).body;};
 const seat=(await state(0)).state.active_player;
 const act=async command=>{const before=await state(seat),body={action_id:randomUUID(),expected_state_seq:before.state_seq,command};const response=await request(seat,`/v1/rooms/${id}/actions`,body);assert.equal(response.status,200,JSON.stringify(response.body));assert.equal(response.body.action_result.accepted,true);return {r:response.body,body};};
 await act({type:'play',hand_id:(await state(seat)).state.players[seat].hand[0].instance_id});
 let pending=await state(seat),choice=pending.state.pending_choice;assert(choice.targets.includes(-1000));assert.equal(choice.targets.length,3);
 const uid=choice.targets.find(x=>x>0);
 const foreign=await request(1-seat,`/v1/rooms/${id}/actions`,{action_id:randomUUID(),expected_state_seq:pending.state_seq,command:{type:'choose_target',choice_id:choice.choice_id,target_uid:uid}});
 assert.equal(foreign.body.action_result.accepted,false);
 await act({type:'choose_target',choice_id:choice.choice_id,target_uid:uid});pending=await state(seat);choice=pending.state.pending_choice;
 assert.deepEqual(choice.selected_units,[uid]);assert(!choice.targets.includes(uid));assert.equal(pending.state.units.length,2);
 const {r,body}=await act({type:'choose_target',choice_id:choice.choice_id,target_uid:-1000});assert(!r.state.pending_choice);assert.equal(r.state.units.length,1);assert.equal(r.state.winner,-1);assert(!r.state.units.some(u=>u.uid===uid));
 const replay=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;assert.equal(replay.state_seq,r.state_seq);assert.deepEqual(replay.state.units,r.state.units);
});
test('sins persist across authoritative rooms and retries without revealing hidden cards', {skip:!enabled,timeout:30000},async t=>{
 const ids=['wrath','lust','sloth','gluttony','gloom','pride','envy'];
 const {central,request,decks,owners}=await fixture(t,{definitionFactory:name=>({...card(name),sin:Number(name.split('_').at(-1))<8?(name.startsWith('ALPHA')?'envy':'wrath'):'gloom'})});
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],clientBuild:839,body:{request_id:randomUUID(),deck:decks[0]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 const body={request_id:randomUUID(),deck:decks[0],main_sin:'envy'};
 const created=await request(0,'/v1/rooms',body);assert.equal(created.status,201);
 const id=created.body.room_id;assert.equal((await request(0,'/v1/rooms',body)).body.room_id,id);
 assert.equal((await request(0,'/v1/rooms',{...body,main_sin:'wrath'})).status,409);
 assert.equal((await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1],main_sin:'greed'})).status,422);
 assert.equal((await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1],main_sin:'wrath'})).status,200);
 for(const seat of [0,1]){
  const s=(await request(seat,`/v1/rooms/${id}/state`)).body.state;
  assert.deepEqual(s.players.map(p=>p.main_sin),['envy','wrath']);
  assert.deepEqual(s.players.map(p=>p.commander_name),['指挥官甲','指挥官乙']);
  assert(!JSON.stringify(s).includes('private_test'));
  assert(s.players[seat].hand.every(h=>ids.includes(h.card.definition.sin)));
  assert.deepEqual(s.players[1-seat].hand,[]);assert.deepEqual(s.players[1-seat].deck,[]);
 }
 assert(!Object.hasOwn(central.rooms.get(id).views[0].players[0],'main_sin'));
});
test('research choices stay private across HTTP, retries, reconnect and timeout', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks}=await fixture(t,{definitionFactory:name=>{
  const d=card(name);Object.assign(d,{kind:'order',unit_class:null,cost:1,operation_cost:0,attack:0,health:0,keywords:[],appearance:{emblem:'order'},abilities:[{trigger:'on_play',effects:[{op:'research',token_ids:['a','b']},{op:'gain_kredits',amount:1}]}],tokens:['a','b'].map(id=>({token_id:id,name:name+'_secret_'+id,unit_class:'tank',attack:2,health:3,keywords:[]}))});return d;
 }});
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,id=created.room_id;
 assert.equal((await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1]})).status,200);
 const state=async seat=>{central.rates.clear();return (await request(seat,`/v1/rooms/${id}/state`)).body;};
 const seat=(await state(0)).state.active_player;
 const act=async(command)=>{const before=await state(seat),body={action_id:randomUUID(),expected_state_seq:before.state_seq,command};const r=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;assert.equal(r.action_result.accepted,true,JSON.stringify(r));return {r,body};};
 await act({type:'play',hand_id:(await state(seat)).state.players[seat].hand[0].instance_id});
 const pending=await state(seat),choice=pending.state.pending_choice,other=await state(1-seat);
 assert.equal(choice.options.length,2);assert(!other.state.pending_choice.options);assert(!JSON.stringify(other).includes('"_resolution"'));
 const watching=await request(2,`/v1/rooms/${id}/watch`,{seat},'POST',ruleCapabilities.battle_rules.minimum_client_build);
 assert.deepEqual(watching.body.state.pending_choice.options,choice.options);
 assert(!central.spectatorSnapshot(central.rooms.get(id),{seat:1-seat}).state.pending_choice.options);
 assert.equal((await request(2,`/v1/rooms/${id}/actions`,{action_id:randomUUID(),expected_state_seq:pending.state_seq,command:{type:'choose_card',choice_id:choice.choice_id,option_index:1}})).status,403);
 const selected=choice.options[1].definition.name;
 const {r,body}=await act({type:'choose_card',choice_id:choice.choice_id,option_index:1});assert.equal(r.state.players[seat].hand.at(-1).card.definition.name,selected);
 const replay=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;assert.equal(replay.state_seq,r.state_seq);assert.deepEqual(replay.state.players[seat].hand,r.state.players[seat].hand);
 await act({type:'play',hand_id:r.state.players[seat].hand[0].instance_id});
 const room=central.rooms.get(id),deadline=room.choiceDeadline;room.lastSeen[seat]=Date.now()-central.offlineAfterMs-1;
 await central.serial(room,()=>central.reconcile(room));assert.equal(room.status,'suspended');
 room.lastSeen=[Date.now(),Date.now()];await central.serial(room,()=>central.reconcile(room));assert.equal(room.status,'active');assert(room.choiceDeadline>=deadline);
 room.choiceDeadline=Date.now()-1;await central.serial(room,()=>central.reconcile(room));assert(!room.views[seat].pending_choice);assert.equal(room.status,'active');
});
test('field replacement is authoritative, public and idempotent across two clients', {skip:!enabled,timeout:30000},async t=>{
 const definitionFactory=name=>({...card(name),kind:'field',unit_class:null,attack:0,health:0,operation_cost:0,appearance:{emblem:'field'},abilities:[{trigger:'while_active',effects:[{op:'modify_stats',target:'all_friendly_units',attack_delta:1,health_delta:0,duration:'battle'}]}]});
 const {request,decks}=await fixture(t,{definitionFactory});
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body;
 const path=`/v1/rooms/${created.room_id}`;
 await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]});
 let state=(await request(0,path+'/state')).body;const first=state.state.active_player;
 state=(await request(first,path+'/state')).body;
 const action={action_id:randomUUID(),expected_state_seq:state.state_seq,command:{type:'play',hand_id:state.state.players[first].hand[0].instance_id}};
 state=(await request(first,path+'/actions',action)).body;
 assert.equal(state.action_result.accepted,true);assert.equal(state.state.field.owner,first);assert.equal(state.state.units.length,0);
 const other=(await request(1-first,path+'/state')).body;assert.deepEqual(other.state.field,state.state.field);assert.deepEqual(other.state.players[first].hand,[]);
 const repeated=(await request(first,path+'/actions',action)).body;assert.equal(repeated.state_seq,state.state_seq);
 await request(first,path+'/actions',{action_id:randomUUID(),expected_state_seq:state.state_seq,command:{type:'end_turn'}});
 state=(await request(1-first,path+'/state')).body;
 state=(await request(1-first,path+'/actions',{action_id:randomUUID(),expected_state_seq:state.state_seq,command:{type:'play',hand_id:state.state.players[1-first].hand[0].instance_id}})).body;
 assert.equal(state.action_result.accepted,true);assert.equal(state.state.field.owner,1-first);assert.equal(state.state.discard.filter(e=>e.card.definition.kind==='field').length,1);
 assert.deepEqual((await request(first,path+'/state')).body.state.field,state.state.field);
 await request(first,path+'/leave',{});
});
test('ordered deployment crosses HTTP authority; retries keep slots and legacy clients must update', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks,owners}=await fixture(t);
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],clientBuild:813,body:{request_id:randomUUID(),deck:decks[0]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,id=created.room_id;
 await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1]});
 let snapshot=(await request(0,`/v1/rooms/${id}/state`)).body;
 const seat=snapshot.state.active_player;
 snapshot=(await request(seat,`/v1/rooms/${id}/state`)).body;
 const hand_id=snapshot.state.players[seat].hand[0].instance_id;
 for(const position of [-1,5,true,'1',1.5]) {
  const bad=await request(seat,`/v1/rooms/${id}/actions`,{action_id:randomUUID(),expected_state_seq:snapshot.state_seq,command:{type:'play',hand_id,position}});
  assert.equal(bad.status,400); assert.equal(bad.body.error.code,'INVALID_REQUEST');
 }
 const body={action_id:randomUUID(),expected_state_seq:snapshot.state_seq,command:{type:'play',hand_id,position:1}};
 const played=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;
 assert.equal(played.action_result.accepted,true);assert.equal(played.state.players[seat].hq_index,0);
 assert.equal(played.state.units[0].line_index,1);
 const retry=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;
 assert.equal(retry.state_seq,played.state_seq);assert.deepEqual(retry.state.units,played.state.units);
 const opponent=(await request(1-seat,`/v1/rooms/${id}/state`)).body;
 assert.deepEqual(opponent.state.units,played.state.units);
 assert.equal(opponent.state.players[seat].hq_index,0);
});
test('main faction is frozen public cosmetic metadata; mixed cards and hidden hands remain private', {skip:!enabled,timeout:30000}, async t=>{
 const {central,request,decks,owners}=await fixture(t);
 const alternate=randomUUID();central.store.state.factions[alternate]={...factionFixture(),faction_id:alternate,name:'另一个主国',color:'#336699'};
 for(const bad of ['__proto__',randomUUID(),null,{},'']) await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],body:{request_id:randomUUID(),deck:decks[0],main_faction_id:bad}}),e=>e.code==='INVALID_FACTION');
 const body={request_id:randomUUID(),deck:decks[0],main_faction_id:alternate};
 const created=(await request(0,'/v1/rooms',body)).body;
 assert.equal((await request(0,'/v1/rooms',body)).body.room_id,created.room_id);
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],body:{...body,main_faction_id:FACTION_ID}}),e=>e.code==='IDEMPOTENCY_CONFLICT');
 // Old clients may omit the cosmetic choice; new clients may pick a registered
 // main faction with no cards in their freely mixed deck.
 await request(1,`/v1/rooms/${created.room_id}/join`,{request_id:randomUUID(),deck:decks[1]});
 for(const seat of [0,1]) {
  const state=(await request(seat,`/v1/rooms/${created.room_id}/state`)).body.state;
  assert.deepEqual(state.players.map(p=>p.main_faction_id),[alternate,FACTION_ID]);
  assert.deepEqual(state.players[1-seat].hand,[]);assert.deepEqual(state.players[1-seat].deck,[]);
  assert(!JSON.stringify(state).includes(seat===0?'BRAVO_private':'ALPHA_private'));
 }
 assert(!Object.hasOwn(central.rooms.get(created.room_id).views[0].players[0],'main_faction_id'),'cosmetic projection must not mutate authoritative state');
});
test('generated cards require build806, preserve hidden hand and play once through authority', {skip:!enabled,timeout:30000},async t=>{
 const definitionFactory=name=>({...card(name),tokens:[{token_id:'ambush',name:'衍生伏击',kind:'counter',cost:0,operation_cost:0,unit_class:null,attack:0,health:0,keywords:[],counter_trigger:'enemy_order_played',abilities:[{trigger:'on_reveal',effects:[{op:'cancel_action'}]}]}],abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:'ambush',player:'owner',amount:1}]}]});
 const {central,request,decks,owners}=await fixture(t,{definitionFactory});
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],clientBuild:805,body:{request_id:randomUUID(),deck:decks[0]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 const room=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,id=room.room_id;
 assert.equal((await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1]})).status,200);
 let p=(await request(0,`/v1/rooms/${id}/state`)).body;const seat=p.state.active_player;p=(await request(seat,`/v1/rooms/${id}/state`)).body;
 const act=async command=>{const body={action_id:randomUUID(),expected_state_seq:p.state_seq,command};p=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;assert(p.action_result.accepted,JSON.stringify(p));return body;};
 await act({type:'play',hand_id:p.state.players[seat].hand[0].instance_id});const generated=p.state.players[seat].hand.find(c=>c.card.generated_token_id==='ambush');assert(generated);assert.equal(generated.card.definition.kind,'counter');
 const other=(await request(1-seat,`/v1/rooms/${id}/state`)).body;assert.deepEqual(other.state.players[seat].hand,[]);
 const body=await act({type:'play',hand_id:generated.instance_id});assert.equal(p.state.players[seat].counters.length,1);
 const retry=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;assert.equal(retry.state_seq,p.state_seq);assert.equal(retry.state.players[seat].counters.length,1);
 assert.deepEqual((await request(1-seat,`/v1/rooms/${id}/state`)).body.state.players[seat].counters,[]);
});
test('named deck summons require build805 and preserve frozen real cards over HTTP retries', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks,owners}=await fixture(t,{definitionFactory:name=>({...card(name),abilities:[{trigger:'on_play',effects:[{op:'summon_from_deck',card_name:name,amount:1}]}]})});
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],clientBuild:804,body:{request_id:randomUUID(),deck:decks[0]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,id=created.room_id;
 await assert.rejects(central.handle({method:'POST',pathname:`/v1/rooms/${id}/join`,owner:owners[1],clientBuild:804,body:{request_id:randomUUID(),deck:decks[1]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 assert.equal((await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1]})).status,200);
 const snapshot=(await request(0,`/v1/rooms/${id}/state`)).body,seat=snapshot.state.active_player;
 const before=(await request(seat,`/v1/rooms/${id}/state`)).body,entry=before.state.players[seat].hand[0];
 const action={action_id:randomUUID(),expected_state_seq:before.state_seq,command:{type:'play',hand_id:entry.instance_id}};
 const after=(await request(seat,`/v1/rooms/${id}/actions`,action)).body;
 assert(after.action_result.accepted);assert.equal(after.state.units.length,2,'summon does not recurse into deployment effects');
 assert.equal(after.state.players[seat].deck_count,before.state.players[seat].deck_count-1);
 assert.deepEqual(after.state.units[0].card,after.state.units[1].card);
 const retry=(await request(seat,`/v1/rooms/${id}/actions`,action)).body;assert.deepEqual(retry.state.units,after.state.units);assert.equal(retry.state_seq,after.state_seq);
 const other=(await request(1-seat,`/v1/rooms/${id}/state`)).body;assert.deepEqual(other.state.units,after.state.units);assert.deepEqual(other.state.players[seat].hand,[]);
});
test('numeric armor requires build804 and authoritative views retain counts across attacks', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks,owners}=await fixture(t,{definitionFactory:name=>({...card(name),health:8,unit_class:'artillery',appearance:{emblem:'artillery'},keywords:[{id:'core.blitz',version:1,params:{}}],abilities:[{trigger:'on_play',effects:[{op:'modify_stacks',target:'self',stack:'heavy_armor',amount:2,duration:'battle'}]}]})});
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],clientBuild:803,body:{request_id:randomUUID(),deck:decks[0]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 const created=await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]});assert.equal(created.status,201);const id=created.body.room_id;
 await assert.rejects(central.handle({method:'POST',pathname:`/v1/rooms/${id}/join`,owner:owners[1],clientBuild:803,body:{request_id:randomUUID(),deck:decks[1]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 assert.equal((await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1]})).status,200);
 const state=async seat=>{central.rates.clear();return (await request(seat,`/v1/rooms/${id}/state`)).body;};
 const act=async(seat,command)=>{const before=await state(seat),body={action_id:randomUUID(),expected_state_seq:before.state_seq,command};const r=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;assert.equal(r.action_result.accepted,true,JSON.stringify(r));return r;};
 if((await state(0)).state.active_player===1)await act(1,{type:'end_turn'});
 await act(0,{type:'play',hand_id:(await state(0)).state.players[0].hand[0].instance_id});await act(0,{type:'end_turn'});
 await act(1,{type:'play',hand_id:(await state(1)).state.players[1].hand[0].instance_id});await act(1,{type:'end_turn'});
 const view=await state(0),attacker=view.state.units.find(u=>u.owner===0),defender=view.state.units.find(u=>u.owner===1);assert.equal(defender.stacks.heavy_armor,2);
 const r=await act(0,{type:'attack',uid:attacker.uid,target_uid:defender.uid});assert.equal(r.state.units.find(u=>u.uid===defender.uid).hp,8-Math.max(0,attacker.attack-2));assert.equal(r.state.units.find(u=>u.uid===defender.uid).stacks.heavy_armor,2);
});
test('death selection survives HTTP retries, disconnect pause and deterministic timeout', {skip:!enabled,timeout:30000},async t=>{
 const salvo=JSON.parse(await readFile(new URL('examples/keywords/example_last_salvo.json',docsURL),'utf8'));
 salvo.implementation.abilities[0].target.timing='trigger';
 const {central,request,decks,owners}=await fixture(t,{definitionFactory:name=>{
  const c=card(name);c.health=8;
  c.keywords=[{id:'core.blitz',version:1,params:{}}];
  if(name.startsWith('ALPHA')){c.health=3;c.abilities=salvo.implementation.abilities;}
  else {c.unit_class='artillery';c.attack=4;c.appearance.emblem='artillery';}
  return c;
 }});
 await assert.rejects(central.handle({method:'POST',pathname:'/v1/rooms',owner:owners[0],body:{request_id:randomUUID(),deck:decks[0]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,id=created.room_id;
 await assert.rejects(central.handle({method:'POST',pathname:`/v1/rooms/${id}/join`,owner:owners[1],body:{request_id:randomUUID(),deck:decks[1]}}),e=>e.code==='CLIENT_UPDATE_REQUIRED');
 assert.equal((await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1]})).status,200);
 const room=central.rooms.get(id);
 const state=async seat=>{central.rates.clear();return (await request(seat,`/v1/rooms/${id}/state`)).body;};
 const act=async(seat,command)=>{const before=await state(seat),body={action_id:randomUUID(),expected_state_seq:before.state_seq,command};const r=(await request(seat,`/v1/rooms/${id}/actions`,body)).body;assert.equal(r.action_result.accepted,true,JSON.stringify(r));return {r,body};};
 if((await state(0)).state.active_player===1)await act(1,{type:'end_turn'});
 await act(0,{type:'end_turn'});await act(1,{type:'end_turn'});
 for(let i=0;i<2;i++)await act(0,{type:'play',hand_id:(await state(0)).state.players[0].hand[0].instance_id});
 await act(0,{type:'end_turn'});
 for(let i=0;i<2;i++)await act(1,{type:'play',hand_id:(await state(1)).state.players[1].hand[0].instance_id});
 let units=(await state(1)).state.units,own=units.filter(u=>u.owner===1),enemies=units.filter(u=>u.owner===0);
 await act(1,{type:'attack',uid:own[0].uid,target_uid:enemies[0].uid});
 let pending=await state(0),choice=pending.state.pending_choice;
 assert.equal(choice.owner,0);assert.equal(pending.state.active_player,1);assert.deepEqual(choice.targets,own.map(u=>u.uid));
 assert(!JSON.stringify(pending).includes('"_resolution"'));assert.equal(pending.state.players[1].hand.length,0);
 const wrong=(await request(1,`/v1/rooms/${id}/actions`,{action_id:randomUUID(),expected_state_seq:pending.state_seq,command:{type:'choose_target',choice_id:choice.choice_id,target_uid:own[1].uid}})).body;
 assert.equal(wrong.action_result.accepted,false);assert.equal(wrong.state_seq,pending.state_seq);
 const {r,body}=await act(0,{type:'choose_target',choice_id:choice.choice_id,target_uid:own[1].uid});
 assert.equal(r.state.units.find(u=>u.uid===own[1].uid).hp,5);assert(!r.state.pending_choice);
 const duplicate=(await request(0,`/v1/rooms/${id}/actions`,body)).body;assert.equal(duplicate.state_seq,r.state_seq);assert.deepEqual(duplicate.state.units,r.state.units);
 // Second death: a dropped chooser gets a pause, then retains the timeout budget.
 await act(1,{type:'attack',uid:own[1].uid,target_uid:enemies[1].uid});
 const deadline=room.choiceDeadline;room.lastSeen[0]=Date.now()-central.offlineAfterMs-1;
 await central.serial(room,()=>central.reconcile(room));assert.equal(room.status,'suspended');
 assert(room.views[0].pending_choice);room.lastSeen=[Date.now(),Date.now()];
 await central.serial(room,()=>central.reconcile(room));assert.equal(room.status,'active');assert(room.choiceDeadline>=deadline);
 room.choiceDeadline=Date.now()-1;
 await central.serial(room,()=>central.reconcile(room));assert(!room.views[0].pending_choice);assert.equal(room.views[0].units.find(u=>u.uid===own[0].uid).hp,5);
});
test('authority preserves card artwork as presentation metadata and hides the opposing hand', {skip:!enabled,timeout:30000}, async t=>{
 const builtin=await Promise.all(['core_blitz','core_guard'].map(async name=>validateKeyword(JSON.parse(await readFile(new URL(`examples/keywords/${name}.json`,docsURL),'utf8')),{allowBuiltin:true})));
 const registry=Object.fromEntries(builtin.map(k=>[`${k.definition.id}@${k.definition.version}`,{...k,registry_status:'approved'}]));
 const decks=[0,1].map(player=>Array.from({length:40},(_,i)=>{
  const c=compileCard(card(`ART_${player}_${Math.floor(i/4)}`),registry);
  return {definition:c.definition,definition_hash:c.definition_hash,compiled_program_hash:c.compiled_program_hash,art_id:(player===0?'a':'b').repeat(64)};
 }));
 const worker=new GodotBattleWorker({godotBin:process.env.GODOT_BIN,projectPath:fileURLToPath(new URL('../..',import.meta.url))});t.after(()=>worker.close());
 const state=await worker.request({command:'setup',decks,keywords:builtin.map(k=>k.definition),seed:42});
 assert(state.views[0].players[0].hand.every(c=>c.card.art_id==='a'.repeat(64)));
 assert.equal(state.views[0].players[1].hand.length,0);
 assert(!JSON.stringify(state.views[0]).includes('b'.repeat(64)));
});
test('real authority hides set counters and cancels an order once over HTTP', {skip:!enabled,timeout:30000},async t=>{
 const {request,decks}=await fixture(t,{definitionFactory:name=>{
  const c={...card(name),unit_class:null,operation_cost:0,attack:0,health:0,kind:name.startsWith('ALPHA')?'counter':'order'};
  c.appearance={emblem:c.kind};
  if(c.kind==='counter'){c.counter_trigger='enemy_order_played';c.abilities=[{trigger:'on_reveal',effects:[{op:'cancel_action'}]}];}
  else c.abilities=[{trigger:'on_play',effects:[{op:'damage',target:'enemy_hq',amount:2}]}];
  return c;
 }});
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,id=created.room_id;
 await request(1,`/v1/rooms/${id}/join`,{request_id:randomUUID(),deck:decks[1]});
 const state=async seat=>(await request(seat,`/v1/rooms/${id}/state`)).body;
 const act=async(seat,command)=>{const before=await state(seat);const result=await request(seat,`/v1/rooms/${id}/actions`,{action_id:randomUUID(),expected_state_seq:before.state_seq,command});assert.equal(result.body.action_result.accepted,true,JSON.stringify(result));return result.body;};
 if((await state(0)).state.active_player===1)await act(1,{type:'end_turn'});
 const own=await state(0);await act(0,{type:'play',hand_id:own.state.players[0].hand[0].instance_id});
 const hidden=await state(1);assert.equal(hidden.state.players[0].counter_count,0);assert.equal(hidden.state.players[0].counters.length,0);assert(!JSON.stringify(hidden).includes('ALPHA_private'));
 await act(0,{type:'end_turn'});
 const opposing=await state(1),hp=opposing.state.players[0].hp;
 const body={action_id:randomUUID(),expected_state_seq:opposing.state_seq,command:{type:'play',hand_id:opposing.state.players[1].hand[0].instance_id}};
 const result=(await request(1,`/v1/rooms/${id}/actions`,body)).body;
 assert.equal(result.action_result.accepted,true);assert.equal(result.state.players[0].hp,hp);assert.equal(result.state.players[0].counter_count,0);assert.equal(result.state.discard.length,2);assert(JSON.stringify(result).includes('ALPHA_private'));
 const replay=(await request(1,`/v1/rooms/${id}/actions`,body)).body;
 assert.equal(replay.state_seq,result.state_seq);assert.equal(replay.state.discard.length,2);
});
test('Godot worker environment preserves OS settings and excludes supervisor credentials', () => {
  const source = {
    Path: 'C:\\Runtime', HOME: '/srv/frontline', TMPDIR: '/tmp/frontline',
    XDG_RUNTIME_DIR: '/run/user/1001', SystemRoot: 'C:\\Windows',
    DEEPSEEK_API_KEY: 'test-provider-key', CARD_API_TOKEN: 'test-card-token',
    REGISTRATION_INVITE_TOKEN: 'test-invite-token', NEW_APPLICATION_SECRET: 'test-future-secret',
    LD_PRELOAD: '/tmp/untrusted.so', NODE_OPTIONS: '--inspect',
  };
  const environment = godotRuntimeEnvironment(source);
  assert.deepEqual(environment, {Path: source.Path, HOME: source.HOME, TMPDIR: source.TMPDIR, XDG_RUNTIME_DIR: source.XDG_RUNTIME_DIR, SystemRoot: source.SystemRoot});
  assert.equal(source.DEEPSEEK_API_KEY, 'test-provider-key', 'filtering must not mutate the supervisor environment');
});
const card = (name) => ({schema_version: '1.0.0', ruleset_version: 'frontline-1', name, flavor_text: '测试夹具', kind: 'unit', unit_class: 'infantry', cost: 1, operation_cost: 0, attack: 2, health: 3, keywords: [], play_target: null, abilities: [], tokens: [], appearance: {emblem: 'infantry'}});
test('derived art travels from frozen HTTP catalog through generation, summon and hidden hands', {skip:!enabled,timeout:30000},async t=>{
 const definitionFactory=name=>({...card(name),tokens:[{token_id:'child',name:'独立卡图衍生兵',unit_class:'infantry',attack:1,health:2,keywords:[]}],abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:'child',player:'owner',amount:1},{op:'summon',token_id:'child',amount:1,row:'support'}]}]});
 const {cards,request,decks}=await fixture(t,{definitionFactory});
 for(const c of cards.values()){c.art={id:'1'.repeat(64)};c.token_art={child:{id:'2'.repeat(64),width:760,height:520}};}
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,path=`/v1/rooms/${created.room_id}`;
 assert.equal((await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]})).status,200);
 let s=(await request(0,path+'/state')).body;const seat=s.state.active_player;s=(await request(seat,path+'/state')).body;
 const body={action_id:randomUUID(),expected_state_seq:s.state_seq,command:{type:'play',hand_id:s.state.players[seat].hand[0].instance_id}};
 s=(await request(seat,path+'/actions',body)).body;assert.equal(s.action_result.accepted,true,JSON.stringify(s));
 assert.equal(s.state.players[seat].hand.at(-1).card.art_id,'2'.repeat(64));
 assert.equal(s.state.units[0].card.art_id,'1'.repeat(64));assert.equal(s.state.units[1].card.art_id,'2'.repeat(64));
 const other=(await request(1-seat,path+'/state')).body;assert.deepEqual(other.state.players[seat].hand,[]);assert.equal(other.state.units[1].card.art_id,'2'.repeat(64));
 assert.deepEqual((await request(seat,path+'/actions',body)).body.state.units,s.state.units);
 await request(seat,path+'/leave',{});
});
async function fixture(t, {definitionFactory = card, ...options} = {}) {
  const registry = {};
  for (const name of ['core_blitz', 'core_guard']) {
    const definition = JSON.parse(await readFile(new URL(`examples/keywords/${name}.json`, docsURL), 'utf8'));
    registry[`${definition.id}@1`] = {...validateKeyword(definition, {allowBuiltin: true}), registry_status: 'approved'};
  }
  const cards = new Map(), decks = [];
  for (const player of ['ALPHA', 'BRAVO']) {
    const refs = [];
    for (let i = 0; i < 11; i++) {
      const compiled = compileCard({sin:i<8?(player==='ALPHA'?'envy':'wrath'):'gloom',...definitionFactory(`${player}_private_${i}`),faction_id:FACTION_ID}, registry), id = randomUUID();
      cards.set(id, {card_id: id, revision: 1, ...compiled});
      for (let n = 0; n < (i===7||i===10?2:4); n++) refs.push({card_id: id, revision: 1, definition_hash: compiled.definition_hash});
    }
    decks.push(refs);
  }
  const store = {state:{factions:{[FACTION_ID]:factionFixture()}},getCard: (id, revision) => cards.get(id)?.revision === revision ? structuredClone(cards.get(id)) : null, listKeywords: () => Object.values(registry)};
  const central = new CentralMatches({store, godotBin: process.env.GODOT_BIN, openingRedraw:false, ...options});
  const owners = [randomUUID(), randomUUID(), randomUUID()], tokens = new Map(owners.map(owner => [`test-${owner}`, owner]));
  store.state.identities=Object.fromEntries(owners.map((owner,index)=>[owner,{display_name:['指挥官甲','指挥官乙','旁观者'][index],private_test:'never expose'}]));
  // Real HTTP requests represent independently authenticated users; account/password
  // authentication is covered by the central index tests, not duplicated here.
  const server = http.createServer(async (req, res) => {
    const send = (status, body) => { res.writeHead(status, {'content-type': 'application/json'}); res.end(JSON.stringify(body)); };
    const owner = tokens.get(String(req.headers.authorization || '').replace(/^Bearer /, ''));
    if (!owner) return send(401, {error: {code: 'UNAUTHORIZED'}});
    try {
      const chunks = []; for await (const chunk of req) chunks.push(chunk);
      const body = chunks.length ? strictParse(Buffer.concat(chunks)) : undefined;
      const result = await central.handle({method: req.method, pathname: new URL(req.url, 'http://localhost').pathname, owner, body, clientBuild:Number(req.headers["x-frontline-client-build"] || 0)});
      send(result?.status || 404, result?.body || {});
    } catch (error) { send(error instanceof ApiError ? error.status : 500, {error: {code: error.code || 'INTERNAL_ERROR', message: error.message}}); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = async (seat, path, body, method = body === undefined ? 'GET' : 'POST', clientBuild = ruleCapabilities.battle_rules.minimum_client_build) => {
    if(body?.deck)body={main_sin:seat===0?'envy':'wrath',ally_sin:'gloom',...body};
    const response = await fetch(base + path, {method, headers: {'x-frontline-client-build':String(clientBuild), 'content-type': 'application/json', authorization: `Bearer test-${owners[seat]}`}, ...(body === undefined ? {} : {body: JSON.stringify(body)})});
    return {status: response.status, body: await response.json()};
  };
  t.after(async () => { await central.close(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); });
  return {central, request, decks, cards, owners, base};
}

test('opening redraw accepts simultaneous seats once, preserves cards and hides hand choices', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks}=await fixture(t,{openingRedraw:true});
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,path=`/v1/rooms/${created.room_id}`;
 const joined=await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]});assert.equal(joined.status,200);
 const a=(await request(0,path+'/state')).body,b=(await request(1,path+'/state')).body;
 assert.deepEqual(a.state.mulligan.confirmed,[false,false]);assert.equal(a.state.players[0].credits,0);
 const command={type:'mulligan',hand_ids:a.state.players[0].hand.map(h=>h.instance_id)};
 const body={action_id:randomUUID(),expected_state_seq:a.state_seq,command};
 const changed=(await request(0,path+'/actions',body)).body;assert.equal(changed.action_result.accepted,true,JSON.stringify(changed));
 assert.equal(changed.state.players[0].deck_count,a.state.players[0].deck_count);
 assert.equal(changed.state.players[0].hand.length,a.state.players[0].hand.length);
 const retry=(await request(0,path+'/actions',body)).body;assert.equal(retry.state_seq,changed.state_seq);assert.deepEqual(retry.state.players[0].hand,changed.state.players[0].hand);
 const watch=(await request(2,path+'/watch',{seat:1},'POST',ruleCapabilities.battle_rules.minimum_client_build)).body;
 assert.deepEqual(watch.state.players[0].hand,[]);assert(!JSON.stringify(watch).includes('ALPHA_private'));
 const concurrent=(await request(1,path+'/actions',{action_id:randomUUID(),expected_state_seq:b.state_seq,command:{type:'mulligan',hand_ids:[]}})).body;
 assert.equal(concurrent.action_result.accepted,true,JSON.stringify(concurrent));assert(!concurrent.state.mulligan);
 const first=concurrent.state.active_player;assert.equal(concurrent.state.players[first].credits,1);
 for(const p of concurrent.state.players)assert.equal(p.deck_count+p.hand_count,40);
 const again=(await request(0,path+'/actions',{action_id:randomUUID(),expected_state_seq:concurrent.state_seq,command})).body;
 assert.equal(again.action_result.accepted,false);assert.equal(again.state_seq,concurrent.state_seq);
 assert.equal(central.rooms.get(created.room_id).mulliganDeadline,null);
});

test('opening redraw timeout keeps hands, pauses across disconnects and starts first turn once', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks}=await fixture(t,{openingRedraw:true});
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body,path=`/v1/rooms/${created.room_id}`;
 await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]});
 const room=central.rooms.get(created.room_id),deadline=room.mulliganDeadline;
 room.lastSeen[0]=Date.now()-central.offlineAfterMs-1;
 await central.reconcile(room);assert.equal(room.status,'suspended');
 room.choicePausedAt-=1500;room.lastSeen=[Date.now(),Date.now()];await central.reconcile(room);assert(room.mulliganDeadline>=deadline+1500);
 const hand=structuredClone(room.views[0].players[0].hand);
 room.mulliganDeadline=Date.now()-1;await central.reconcile(room);
 assert(!room.views[0].mulligan);assert.deepEqual(room.views[0].players[0].hand.slice(0,hand.length),hand);
 const seq=room.seq;await central.reconcile(room);assert.equal(room.seq,seq);
});

test('spectators have a permanent single-seat perspective and cannot issue player actions', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks,owners}=await fixture(t);
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body;
 const path=`/v1/rooms/${created.room_id}`;
 const watch=(seat,build=ruleCapabilities.battle_rules.minimum_client_build)=>request(2,path+'/watch',{seat},'POST',build);
 assert.equal((await watch(0)).status,409);
 await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]});
 const list=(await request(2,'/v1/rooms')).body.rooms;
 assert.equal(list.length,1);assert.deepEqual(list[0].commanders,['指挥官甲','指挥官乙']);
 assert(!JSON.stringify(list).includes('private'));assert(!JSON.stringify(list).includes(owners[0]));
 assert.equal((await watch(2)).status,400);assert.equal((await watch(0,858)).status,409);assert.match((await watch(0,859)).body.error.message,/0\.9\.6/);
 assert.equal((await request(0,path+'/watch',{seat:0},'POST',ruleCapabilities.battle_rules.minimum_client_build)).status,409);
 const joined=await watch(0);assert.equal(joined.status,200,JSON.stringify(joined));
 const room=central.rooms.get(created.room_id),seq=room.seq,lastSeen=[...room.lastSeen],lastAction=room.lastAction;
 assert.equal(joined.body.spectator,true);assert.equal(joined.body.followed_player,0);
 assert(joined.body.state.players[0].hand.length>0);assert.equal(joined.body.state.players[1].hand.length,0);
 assert(joined.body.state.players.every(p=>p.deck.length===0));assert(!JSON.stringify(joined.body).includes('BRAVO_private'));
 joined.body.state.players[0].hand.length=0;
 assert((await request(2,path+'/state')).body.state.players[0].hand.length>0);
 assert.deepEqual(room.lastSeen,lastSeen);assert.equal(room.lastAction,lastAction);
 for(const [route,body] of [['actions',{action_id:randomUUID(),expected_state_seq:seq,command:{type:'concede'}}],['leave',{}],['emotes',{}]]){
  assert.equal((await request(2,path+'/'+route,body)).status,403);
 }
 assert.equal(room.seq,seq);assert.equal(room.winner,-1);
 assert.equal((await watch(1)).body.error.code,'SPECTATOR_PERSPECTIVE_LOCKED');
 central.rates.clear();
 assert.equal((await request(2,path+'/unwatch',{})).status,200);
 assert.equal((await request(2,path+'/state')).status,403);assert.equal(room.status,'active');
 assert.equal((await watch(1)).status,409);assert.equal((await watch(0)).status,200);
 await request(1,path+'/leave',{});
 const ended=await request(2,path+'/state');assert.equal(ended.body.state.winner,0);assert.equal(ended.body.spectator,true);
 assert.equal((await watch(0)).status,409);
});

test('spectator heartbeats cannot keep absent players alive or lift the audience limit', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks,owners}=await fixture(t,{offlineAfterMs:1000,disconnectGraceMs:1000});
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body;
 const path=`/v1/rooms/${created.room_id}`;
 await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]});
 await request(2,path+'/watch',{seat:1},'POST',ruleCapabilities.battle_rules.minimum_client_build);
 const room=central.rooms.get(created.room_id);
 room.lastSeen[0]=Date.now()-2000;room.lastSeen[1]=Date.now();
 assert.equal((await request(2,path+'/state')).body.status,'suspended');
 assert.deepEqual(room.absent,[0]);assert(room.deadline);
 room.deadline=Date.now()-1;
 assert.equal((await request(2,path+'/state')).body.state.winner,1);
 room.spectators.get(owners[2]).lastSeen=Date.now()-2000;
 for(let n=0;n<64;n++)room.spectators.set(randomUUID(),{seat:0,active:true,lastSeen:Date.now()});
 assert.equal((await request(2,path+'/state')).body.error.code,'SPECTATOR_LIMIT');
});

test('Godot spectator client joins, polls, leaves and reconnects without surrendering a player', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks,owners,base}=await fixture(t);
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body;
 await request(1,`/v1/rooms/${created.room_id}/join`,{request_id:randomUUID(),deck:decks[1]});
 const child=spawn(process.env.GODOT_BIN,['--headless','--path',central.projectPath,'--script','res://tests/test_spectator_http.gd'],{windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,CLOUD_TEST_URL:base,CLOUD_TEST_TOKEN_C:`test-${owners[2]}`,CLOUD_TEST_ROOM:created.room_id}});
 let output='';child.stdout.on('data',s=>output+=s);child.stderr.on('data',s=>output+=s);
 const timer=setTimeout(()=>child.kill(),20000);timer.unref();
 const code=await new Promise((resolve,reject)=>{child.on('exit',resolve);child.on('error',reject)});clearTimeout(timer);
 assert.equal(code,0,output);assert.match(output,/SPECTATOR_HTTP: 8 checks, 0 failures/);assert.doesNotMatch(output,/SCRIPT ERROR/);
 const room=central.rooms.get(created.room_id);assert.equal(room.status,'active');assert.equal(room.winner,-1);
});

test('cloud rooms use an actual Godot authority, seat-bound HTTP actions and private views', {skip: !enabled, timeout: 30000}, async t => {
  const {central, request, decks} = await fixture(t);
  const create = {request_id: randomUUID(), deck: decks[0]};
  const created = await request(0, '/v1/rooms', create);
  assert.equal(created.status, 201); assert.equal(created.body.status, 'waiting'); assert.equal(created.body.state, null);
  const id = created.body.room_id;
  assert.equal((await request(0, '/v1/rooms', create)).body.room_id, id);
  assert.equal((await request(0, '/v1/rooms', {...create, deck: decks[1]})).status, 409);
  assert.equal((await request(0, '/v1/rooms', {request_id: randomUUID(), deck: decks[0]})).status, 409);
  assert.equal((await request(2, `/v1/rooms/${id}/state`)).status, 403);
  const injected = structuredClone(decks[1]); injected[0].definition = card('客户端注入');
  assert.equal((await request(1, `/v1/rooms/${id}/join`, {request_id: randomUUID(), deck: injected})).status, 400);
  const badHash = structuredClone(decks[1]); badHash[0].definition_hash = '0'.repeat(64);
  assert.equal((await request(1, `/v1/rooms/${id}/join`, {request_id: randomUUID(), deck: badHash})).body.error.code, 'CARD_HASH_MISMATCH');
  const joined = await request(1, `/v1/rooms/${created.body.code}/join`, {request_id: randomUUID(), deck: decks[1]});
  assert.equal(joined.status, 200, JSON.stringify(joined.body)); assert.equal(joined.body.local_player, 1); assert.equal(joined.body.status, 'active');
  assert.ok(central.rooms.get(id).worker.child.pid > 0, 'a separate Godot process is authoritative');
  const own = (await request(0, `/v1/rooms/${id}/state`)).body;
  for (const [seat, packet] of [[0, own], [1, joined.body]]) {
    assert.equal(packet.state.players[1 - seat].hand.length, 0);
    assert.ok(packet.state.players.every(player => player.deck.length === 0));
    assert.ok(packet.state.players[seat].hand.length > 0);
    assert.equal(JSON.stringify(packet).includes(seat === 0 ? 'BRAVO_private' : 'ALPHA_private'), false);
    assert.equal(packet.state.seed, undefined); assert.equal(packet.state.rng_state, undefined);
  }
  const active = own.state.active_player, waiting = 1 - active, activeState = active ? joined.body : own;
  const wrongTurn = await request(waiting, `/v1/rooms/${id}/actions`, {action_id: randomUUID(), expected_state_seq: own.state_seq, command: {type: 'end_turn'}});
  assert.equal(wrongTurn.body.action_result.accepted, false); assert.equal(wrongTurn.body.state_seq, own.state_seq);
  const forged = await request(waiting, `/v1/rooms/${id}/actions`, {action_id: randomUUID(), expected_state_seq: own.state_seq, command: {type: 'end_turn', player: active}});
  assert.equal(forged.status, 400);
  const play = {action_id: randomUUID(), expected_state_seq: own.state_seq, command: {type: 'play', hand_id: activeState.state.players[active].hand[0].instance_id}};
  const played = await request(active, `/v1/rooms/${id}/actions`, play);
  assert.equal(played.status, 200); assert.equal(played.body.action_result.accepted, true); assert.equal(played.body.state.units.length, 1);
  const repeated = await request(active, `/v1/rooms/${id}/actions`, play);
  assert.equal(repeated.body.state_seq, played.body.state_seq); assert.equal(repeated.body.state.units.length, 1);
  assert.equal((await request(active, `/v1/rooms/${id}/actions`, {...play, command: {type: 'concede'}})).status, 409);
  const stale = await request(active, `/v1/rooms/${id}/actions`, {...play, action_id: randomUUID(), command: {type: 'end_turn'}});
  assert.equal(stale.body.action_result.code, 'STALE_STATE');
  const ended = await request(waiting, `/v1/rooms/${id}/leave`, {});
  assert.equal(ended.body.state.winner, active); assert.equal(ended.body.status, 'ended');
  assert.equal((await request(active, `/v1/rooms/${id}/state`)).body.state.winner, active);
  assert.equal(central.rooms.get(id).worker, null, 'finished match releases the Godot worker');
});

test('authority enforces attack limits and cost layers across duplicate, stale and forged client actions', {skip: !enabled, timeout: 30000}, async t => {
  const definitionFactory = name => ({...card(name), unit_class:'artillery', operation_cost:1, keywords:[{id:'core.blitz',version:1,params:{}}], abilities:[{trigger:'on_play',effects:[{op:'set_attack_limit',target:'self',attacks:2,duration:'battle'},{op:'modify_operation_cost',target:'self',cost_delta:-1,duration:'battle'}]}]});
  const {request,decks} = await fixture(t,{definitionFactory});
  const room = (await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body;
  await request(1,`/v1/rooms/${room.id || room.room_id}/join`,{request_id:randomUUID(),deck:decks[1]});
  const path = `/v1/rooms/${room.room_id}`;
  let packet = (await request(0,`${path}/state`)).body;
  const player = packet.state.active_player;
  packet = (await request(player,`${path}/state`)).body;
  const action = async command => {
    const body = {action_id:randomUUID(),expected_state_seq:packet.state_seq,command};
    const response = await request(player,`${path}/actions`,body);
    assert.equal(response.status,200,JSON.stringify(response.body)); packet = response.body;
    return body;
  };
  await action({type:'play',hand_id:packet.state.players[player].hand[0].instance_id});
  assert.equal(packet.action_result.accepted,true);
  const uid = packet.state.units[0].uid, beforeHp = packet.state.players[1-player].hp;
  assert.equal(packet.state.units[0].operation_cost,0);
  const first = await action({type:'attack',uid,target_uid:-1});
  assert.equal(packet.state.units[0].attacks_used,1);
  const repeated = await request(player,`${path}/actions`,first);
  assert.equal(repeated.body.state_seq,packet.state_seq);
  assert.equal(repeated.body.state.units[0].attacks_used,1,'retry cannot consume twice');
  const forged = await request(player,`${path}/actions`,{action_id:randomUUID(),expected_state_seq:packet.state_seq,command:{type:'attack',uid,target_uid:-1,attacks_used:0}});
  assert.equal(forged.status,400,'client cannot reset its counter');
  await action({type:'attack',uid,target_uid:-1});
  assert.equal(packet.action_result.accepted,true);
  assert.equal(packet.state.players[1-player].hp,beforeHp-4);
  const seq = packet.state_seq;
  await action({type:'attack',uid,target_uid:-1});
  assert.equal(packet.action_result.accepted,false); assert.equal(packet.state_seq,seq);
  assert.equal(packet.state.units[0].attacks_used,2);
  const opponent = (await request(1-player,`${path}/state`)).body;
  assert.deepEqual(opponent.state.units,packet.state.units,'both players receive same counters');
  assert.deepEqual(opponent.state.players[player].hand,[],'new state still conceals enemy hand');
  await request(player,`${path}/leave`,{});
});

test('cloud rooms enforce capacity, registry compilation and independent disconnect lifecycle', {skip: !enabled, timeout: 30000}, async t => {
  const {central, request, decks, cards} = await fixture(t, {maxRooms: 1, offlineAfterMs: 1000, disconnectGraceMs: 1000, bothOfflineGraceMs: 1000});
  const created = (await request(0, '/v1/rooms', {request_id: randomUUID(), deck: decks[0]})).body, id = created.room_id;
  assert.equal((await request(2, '/v1/rooms', {request_id: randomUUID(), deck: decks[1]})).body.error.code, 'ROOM_LIMIT');
  const firstCard = cards.get(decks[1][0].card_id), expectedHash = firstCard.compiled_program_hash;
  firstCard.compiled_program_hash = '0'.repeat(64);
  const rejected = await request(1, `/v1/rooms/${id}/join`, {request_id: randomUUID(), deck: decks[1]});
  assert.equal(rejected.body.error.code, 'COMPILED_PROGRAM_MISMATCH');
  firstCard.compiled_program_hash = expectedHash;
  assert.equal((await request(1, `/v1/rooms/${id}/join`, {request_id: randomUUID(), deck: decks[1]})).body.status, 'active');
  const room = central.rooms.get(id), before = room.seq;
  room.lastSeen[1] = Date.now() - 2000;
  await central.serial(room, () => central.reconcile(room));
  assert.equal(room.status, 'suspended'); assert.equal(room.seq, before + 1); assert.equal(room.views[0].suspended, true);
  const resumed = await request(1, `/v1/rooms/${id}/state`);
  assert.equal(resumed.body.status, 'active'); assert.equal(resumed.body.state.suspended, false);
  room.lastSeen[1] = Date.now() - 2000;
  await central.serial(room, () => central.reconcile(room));
  room.deadline = Date.now() - 1;
  await central.serial(room, () => central.reconcile(room));
  assert.equal(room.status, 'ended'); assert.equal(room.views[0].winner, 0); assert.equal(room.worker, null);
});

test('Godot cloud controller creates, polls, acts and leaves through the HTTP boundary', {skip: !enabled, timeout: 30000}, async t => {
  const {base, owners, decks, central} = await fixture(t);
  const emoteId=randomUUID();central.store.state.emotes={[emoteId]:{emote_id:emoteId,scale_percent:150}};
  const projectPath = fileURLToPath(new URL('../..', import.meta.url));
  const child = spawn(process.env.GODOT_BIN, ['--headless', '--path', projectPath, '--script', 'res://tests/test_cloud_controller.gd'], {windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env: {...process.env, CLOUD_TEST_EMOTE_ID:emoteId,CLOUD_TEST_URL: base, CLOUD_TEST_TOKEN_A: `test-${owners[0]}`, CLOUD_TEST_TOKEN_B: `test-${owners[1]}`, CLOUD_TEST_DECKS: JSON.stringify(decks)}});
  let output = ''; child.stdout.on('data', chunk => { output += chunk; }); child.stderr.on('data', chunk => { output += chunk; });
  const timer = setTimeout(() => child.kill(), 20000); timer.unref();
  const code = await new Promise((resolve, reject) => { child.on('exit', resolve); child.on('error', reject); }); clearTimeout(timer);
  assert.equal(code, 0, output); assert.match(output, /CLOUD_CONTROLLER_PASS checks=19/); assert.doesNotMatch(output, /SCRIPT ERROR|CLOUD_CONTROLLER_FAIL/);
});


test('HQ is independently frozen through HTTP join and has public defense/draw rules', {skip:!enabled,timeout:30000},async t=>{
 const {central,request,decks,cards}=await fixture(t);
 const hqDef={...card('玩家总部'),kind:'hq',cost:0,unit_class:null,attack:0,operation_cost:0,health:37,draw_rule:{base:2},appearance:{emblem:'hq'},faction_id:FACTION_ID};
 const id=randomUUID(),c={card_id:id,revision:1,...compileCard(hqDef,{})};cards.set(id,c);
 central.store.state.cards={[id]:[c]};central.store.state.keywords={};
 const ref={card_id:id,revision:1,definition_hash:c.definition_hash};
 const requestBody={request_id:randomUUID(),deck:decks[0],headquarters:ref};
 const created=await request(0,'/v1/rooms',requestBody);assert.equal(created.status,201,JSON.stringify(created));
 const joined=await request(1,`/v1/rooms/${created.body.room_id}/join`,{request_id:randomUUID(),deck:decks[1]});assert.equal(joined.status,200,JSON.stringify(joined));
 for(const seat of [0,1]){
  const s=(await request(seat,`/v1/rooms/${created.body.room_id}/state`)).body.state;
  assert.equal(s.players[0].hp,37);assert.equal(s.players[0].headquarters.definition.draw_rule.base,2);assert.equal(s.players[1].hp,20);assert.deepEqual(s.players[1].headquarters,{});
  assert(!s.units.some(u=>u.card.definition.kind==='hq'));assert(s.players[seat].hand.every(e=>e.card.definition.kind!=='hq'));
 }
 assert.equal(central.rooms.get(created.body.room_id).deckRefs[0].length,40);
});


test('permanent death copies update both deck counts and survive HTTP retry exactly once', {skip:!enabled,timeout:30000},async t=>{
 const definitionFactory=name=>({...card(name),abilities:[
  {trigger:'on_play',effects:[{op:'modify_stats',target:'self',attack_delta:2,health_delta:2,duration:'match'}]},
  {trigger:'own_turn_end',effects:[{op:'destroy',target:'self'}]},
  {trigger:'on_death',effects:['deck','hand'].map(destination=>({op:'transfer_card',source:'self',destination,mode:'copy',selection:'random',amount:1}))}
 ]});
 const {central,request,decks}=await fixture(t,{definitionFactory});
 const created=(await request(0,'/v1/rooms',{request_id:randomUUID(),deck:decks[0]})).body;
 const path=`/v1/rooms/${created.room_id}`;
 assert.equal((await request(1,path+'/join',{request_id:randomUUID(),deck:decks[1]})).status,200);
 let s=(await request(0,path+'/state')).body;const seat=s.state.active_player;
 s=(await request(seat,path+'/state')).body;
 const deckBefore=s.state.players[seat].deck_count;
 const original=s.state.players[seat].hand[0].card;
 const act=async(command)=>{central.rates.clear();const body={action_id:randomUUID(),expected_state_seq:s.state_seq,command};s=(await request(seat,path+'/actions',body)).body;assert.equal(s.action_result.accepted,true,JSON.stringify(s));return body;};
 await act({type:'play',hand_id:s.state.players[seat].hand[0].instance_id});
 assert.equal(s.state.units[0].attack,original.definition.attack+2);
 const body=await act({type:'end_turn'});
 assert.equal(s.state.units.length,0);
 assert.equal(s.state.players[seat].deck_count,deckBefore+1);
 const copy=s.state.players[seat].hand.at(-1).card;
 assert.equal(copy.definition_hash,original.definition_hash);
 assert.equal(copy.match_layers.length,1);
 assert.equal(copy.match_layers[0].layer.attack_delta,2);
 const other=(await request(1-seat,path+'/state')).body;
 assert.equal(other.state.players[seat].deck_count,deckBefore+1);
 assert.deepEqual(other.state.players[seat].deck,[]);assert.deepEqual(other.state.players[seat].hand,[]);
 assert(!other.state.presentation_events.some(e=>e.kind==='deck_insert'));
 const retry=(await request(seat,path+'/actions',body)).body;
 assert.equal(retry.state_seq,s.state_seq);
 assert.equal(retry.state.players[seat].deck_count,deckBefore+1);
 assert.deepEqual(retry.state.players[seat].hand,s.state.players[seat].hand);
 await request(seat,path+'/leave',{});
});

