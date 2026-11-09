import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard,validateKeyword,schemas} from '../src/validation.js';
import {makePrompt,DeepSeekProvider} from '../src/provider.js';
import {editorError,freshCard,defaultEffect,changeKind} from '../../web/model.mjs';
import {collectJobDiagnostic,recordDiagnostic} from '../src/diagnostics.js';

test('a recurring diagnostic reopens without retaining an active resolution',()=>{
 const state={},event={stage:'card',code:'INVALID_SCHEMA',message:'缺少衍生卡'};
 const id=recordDiagnostic(state,event),entry=state.diagnostics[id];
 Object.assign(entry,{status:'resolved',resolved_at:'2026-09-26T00:00:00.000Z',resolution:'已修复输入校验',resolution_version:'0.8.25'});
 recordDiagnostic(state,event);
 assert.equal(entry.status,'open');assert.equal(entry.count,2);
 assert.equal(entry.resolved_at,undefined);assert.equal(entry.resolution,undefined);assert.equal(entry.resolution_version,undefined);
 assert.equal(entry.resolution_history[0].resolution_version,'0.8.25');
});
import {publicCard} from '../src/cloud_catalog.js';
import {labels} from '../../web/model.mjs';
import {checkMechanismIntent} from '../src/mechanism_intent.js';
const card=()=>({...freshCard(),name:'回归测试',cost:1});
const buff={op:'modify_stats',target:'self',attack_delta:1,health_delta:1,duration:'battle'};
const transfer={op:'transfer_card',source:'hand',destination:'hand',mode:'copy',selection:'highest_cost',amount:1};

test('explicit larger-side destruction and combined Pin/Suppress cannot be silently inverted or dropped',()=>{
 const source='消灭数量较多方所有单位并对该方总部造成10点伤害';
 for(const left of ['friendly_unit_count','enemy_unit_count'])for(const cmp of ['gt','lt']){
  const greaterFriendly=(left==='friendly_unit_count')===(cmp==='gt');
  const a={trigger:'next_own_turn_start',premise:{test:'compare',left:{stat:left},cmp,right:{stat:left==='friendly_unit_count'?'enemy_unit_count':'friendly_unit_count'}},effects:[{op:'destroy',target:greaterFriendly?'all_friendly_units':'all_enemy_units'}]};
  assert.doesNotThrow(()=>checkMechanismIntent(source,{abilities:[a]}));
  a.effects[0].target=greaterFriendly?'all_enemy_units':'all_friendly_units';
  assert.throws(()=>checkMechanismIntent(source,{abilities:[a]}),{code:'INTENT_MECHANISM_MISMATCH'});
 }
 assert.throws(()=>checkMechanismIntent('压制并抑制所有单位',{abilities:[{effects:[{op:'suppress',target:'all_enemy_units'}]}]}),{code:'INTENT_MECHANISM_MISMATCH'});
 const c=changeKind(card(),'order');c.play_target={side:'any',row:'any',include_hq:true};c.abilities=[{trigger:'on_play',effects:[{op:'damage',target:'chosen',amount:1}]}];
 assert.match(compileCard(c,{}).rules_text,/任意一方单位或总部/);
});

test('Pin is 压制 and Suppress is 抑制 across generated text, editor and saved card projection',()=>{
 const c=changeKind(card(),'order');c.abilities=[{trigger:'on_play',effects:[{op:'pin',target:'all_enemy_units',turns:1},{op:'suppress',target:'all_enemy_units'}]}];
 const compiled=compileCard(c,{});assert.match(compiled.rules_text,/压制.*抑制/s);assert(!compiled.rules_text.includes('钉住'));
 assert.equal(labels.pin,'压制');assert.equal(labels.suppress,'抑制');
 const old={...compiled,rules_text:'旧版误译',card_id:'test',owner_id:'owner',revision:1};
 assert.equal(publicCard(old,'owner').rules_text,compiled.short_rules_text);assert.equal(old.rules_text,'旧版误译');
 for(const kind of ['card','keyword','mechanism-review']){const prompt=makePrompt(kind,[]);assert(prompt.includes('压制（pin）和抑制（suppress）是两个独立效果'));assert(prompt.includes('同时生成 pin 和 suppress'));}
});

test('provider repairs a reversed explicit comparison within the existing two-attempt budget',async()=>{
 const c=changeKind(card(),'order');c.abilities=[{trigger:'next_own_turn_start',premise:{test:'compare',left:{stat:'friendly_unit_count'},cmp:'gt',right:{stat:'enemy_unit_count'}},effects:[{op:'destroy',target:'all_enemy_units'}]}];
 let calls=0;const bodies=[];
 const p=new DeepSeekProvider({apiKey:'test',fetch:async(_u,args)=>{
  bodies.push(JSON.parse(args.body));const candidate=structuredClone(c);if(++calls===2)candidate.abilities[0].effects[0].target='all_friendly_units';
  return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify({status:'ok',card:candidate,assumptions:[],explanation:''})}}]}));
 }});
 const out=await p.generate({kind:'card',catalog:[],context:{source_text:'消灭数量较多方所有单位'},signal:new AbortController().signal,onAttempt:async()=>{}});
 assert.equal(calls,2);assert.equal(out.result.card.abilities[0].effects[0].target,'all_friendly_units');
 assert(bodies[1].messages.at(-1).content.includes('INTENT_MECHANISM_MISMATCH'));
});
test('collected trigger, copy, aura, equipment and combat variants compile with useful text',()=>{
 const cases=[
 {trigger:'own_unit_deployed',limit:1,effects:[buff]},
 {trigger:'enemy_unit_deployed',limit:1,effects:[buff]},
 {trigger:'on_attacked',effects:[{op:'damage',target:'trigger_unit',amount:2}]},
 {trigger:'on_damaged',damage_step:2,effects:[{op:'modify_stacks',target:'self',stack:'heavy_armor',amount:1,duration:'battle'}]},
 {trigger:'on_death',effects:[{...transfer,source:'self',destination:'deck'}]},
 {trigger:'on_play',effects:[transfer]},
 {trigger:'on_play',effects:[{...transfer,source:'discard',destination:'support',mode:'move',filter:{kind:'unit'}}]},
 {trigger:'on_death',effects:[{...transfer,source:'deck',destination:'source_position',mode:'move',filter:{faction_id:'11111111-1111-4111-8111-111111111111'}}]},
 {trigger:'while_active',effects:[{...buff,health_delta:0,attack_delta:{equipment:'剑',scale:2}}]},
 {trigger:'while_active',premise:{test:'compare',left:{stat:'enemy_front_count'},cmp:'gt',right:0},effects:[{...buff,health_delta:0,attack_delta:5}]},
 {trigger:'on_play',effects:[{op:'set_combat_damage_multiplier',target:'self',against:'any',target_row:'front',attack_delta:10,multiplier:1,applies_to:'attack',duration:'battle'}]}
 ];
 for(const a of cases){const c=card();c.abilities=[a];const r=compileCard(c,{});assert(r.rules_text&&!/undefined|\[object Object\]/.test(r.rules_text),JSON.stringify(a));}
 const s=changeKind(card(),'order');s.abilities=[{trigger:'next_own_order_played',effects:[{...transfer,source:'deck',mode:'move',filter:{kind:'unit',event_faction:true,event_cost_distance:1}}]}];assert.match(compileCard(s,{}).rules_text,/费用差不超过1/);
 for(const trigger of ['next_own_turn_start','next_opponent_turn_start']){s.abilities[0]={trigger,effects:[{op:'draw',player:'owner',amount:2}]};assert(compileCard(s,{}));}
});
test('extensions stay bounded and event context cannot be fabricated',()=>{
 for(const a of [
 {trigger:'on_play',damage_step:2,effects:[buff]},
 {trigger:'on_play',limit:1,effects:[buff]},
 {trigger:'on_play',effects:[{op:'damage',target:'trigger_unit',amount:1}]},
 {trigger:'while_active',premise:{test:'compare',left:{stat:'source_attack'},cmp:'gt',right:0},effects:[{...buff,health_delta:0}]},
 {trigger:'while_active',effects:[buff]},
 {trigger:'on_play',effects:[{...transfer,source:'self',mode:'move'}]},
 {trigger:'on_play',effects:[{...transfer,filter:{event_faction:true}}]},
 {trigger:'on_play',effects:[{...transfer,filter:{min_cost:5,max_cost:2}}]},
 ]){const c=card();c.abilities=[a];assert.throws(()=>compileCard(c,{}),JSON.stringify(a));}
 const d={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.reflect',version:1,name:'反伤',description:'受到攻击时对攻击者造成X伤害。',aliases:[],parameters:{x:{type:'integer',minimum:1,maximum:10}},implementation:{kind:'template',abilities:[{trigger:'on_attacked',effects:[{op:'damage',target:'trigger_unit',amount:{param:'x'}}]}]}};assert(validateKeyword(d));d.parameters.x.maximum=11;assert.throws(()=>validateKeyword(d));
});
test('editor avoids empty token and invalid counter target submissions, optional fields stay optional',()=>{
 const c=card();c.abilities=[{trigger:'on_play',effects:[{op:'summon',token_id:'',amount:1}]}];assert.match(editorError(c),/先添加衍生卡/);
 c.abilities=[{trigger:'on_play',effects:[{op:'damage',target:'trigger_unit',amount:1}]}];assert.match(editorError(c),/没有触发单位/);
 c.abilities=[];c.keywords=[{id:'core.guard',version:2,params:{}}];const o=changeKind(c,'order');assert.equal(o.keywords.length,0);assert.match(editorError(o),/至少一个效果/);
 const e=defaultEffect(schemas.card.definitions.effect.oneOf.find(e=>e.properties.op.const==='transfer_card'));assert(!Object.hasOwn(e,'filter'));assert.equal(e.amount,1);
});
test('clarification is not logged as a defect; actual errors stay retained',()=>{
 const s={};collectJobDiagnostic(s,{kind:'mechanism-review',status:'awaiting_confirmation',result:{questions:[{question:'哪一方回合？'}],missing_capabilities:[]}});assert(!s.diagnostics);
 collectJobDiagnostic(s,{kind:'card',status:'failed',error:{code:'INVALID_SCHEMA',message:'缺少衍生卡'},result:{}});assert.equal(Object.values(s.diagnostics)[0].category,'validation');
});
test('all provider stages receive current bounded mechanisms, and transient errors retry without changing intent',async()=>{
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[]);for(const text of ['mechanics-20','damage_step','transfer_card','next_own_turn_start','equipment','target_row'])assert(p.includes(text));}
 let attempts=0,calls=0;const request=[];
 const provider=new DeepSeekProvider({apiKey:'test',fetch:async(_url,args)=>{request.push(JSON.parse(args.body));if(++calls===1)return new Response('',{status:503,headers:{'retry-after':'0'}});return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify({status:'review',formal_text:'每次受伤后处理累计损伤。',questions:[],missing_capabilities:[]})}}]}));}});
 const r=await provider.generate({kind:'mechanism-review',catalog:[],context:{source_text:'每受2伤重甲加1'},signal:new AbortController().signal,onAttempt:async()=>{attempts++;}});assert.equal(attempts,2);assert.equal(r.result.status,'review');assert.deepEqual(request[0].messages,request[1].messages);assert.equal(request[1].thinking.type,'enabled');
});
