import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard,validateKeyword} from '../src/validation.js';
import {latestCards} from '../src/derived_cards.js';
import {makePrompt} from '../src/provider.js';
import {freshCard,changeKind} from '../../web/model.mjs';
import {recordDiagnostic,collectJobDiagnostic,markResolved,initializeReports,authorReports,inbox,readMessage,resumeContext,resolveDiagnostic} from '../src/diagnostics.js';
const card=()=>({...freshCard(),name:'测试'}),r=(op,extra={})=>({op,target:'self',duration:'battle',...extra});

test('new incident rules compile on cards and reusable keywords with bounded values',()=>{
 const operations=[r('set_combat_priority',{applies_to:'both'}),r('grant_unit_class',{unit_class:'fighter'}),r('modify_incoming_damage',{amount:2,damage_kind:'both'}),r('grant_order_target_reward',{amount:1})];
 for(const op of operations){const d=card();d.abilities=[{trigger:'on_play',effects:[op]}];assert.doesNotThrow(()=>compileCard(d,{}));const kw={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.test',version:1,name:'机制',description:'测试',aliases:[],parameters:{},implementation:{kind:'template',abilities:d.abilities}};assert.doesNotThrow(()=>validateKeyword(kw));}
 for(const trigger of ['after_attack','after_move','after_action','own_unit_died','enemy_unit_died']){const d=card();d.abilities=[{trigger,effects:[{op:'draw',player:'owner',amount:1}]}];assert.doesNotThrow(()=>compileCard(d,{}));assert.throws(()=>compileCard(changeKind(d,'order'),{}));}
 for(const op of [r('modify_incoming_damage',{amount:0,damage_kind:'both'}),r('modify_incoming_damage',{amount:101,damage_kind:'both'}),r('grant_order_target_reward',{amount:4}),r('grant_unit_class',{unit_class:'navy'})]){const d=card();d.abilities=[{trigger:'on_play',effects:[op]}];assert.throws(()=>compileCard(d,{}));}
 const d=changeKind(card(),'order');d.play_target={side:'any',row:'any',include_hq:true};d.abilities=[{trigger:'on_play',effects:operations.slice(2).map(e=>({...e,target:'chosen',duration:'end_of_turn'}))}];assert.doesNotThrow(()=>compileCard(d,{}));
 for(const kind of ['card','keyword','mechanism-review'])assert.match(makePrompt(kind,[]),/交战先手.*主动行动后.*阵亡监听.*指令选中奖励/s);
});
test('unreferenced, self-recursive and mutually recursive templates remain valid library records',()=>{
 const d=card();const token=id=>({token_id:id,name:id,unit_class:'infantry',attack:1,health:1,keywords:[],abilities:[]});d.tokens=[token('a'),token('b')];
 for(const cyclic of [false,true]){
  if(cyclic){d.tokens[0].abilities=[{trigger:'on_death',effects:[{op:'create_card',token_id:'a',player:'owner',amount:1},{op:'create_card',token_id:'b',player:'owner',amount:1}]}];d.tokens[1].abilities=[{trigger:'on_death',effects:[{op:'create_card',token_id:'a',player:'owner',amount:1}]}];}
  const c=compileCard(d,{}),state={keywords:{},cards:{parent:[{card_id:'parent',revision:1,owner_id:'author',...c}]}};
  const all=latestCards(state);assert.equal(all.length,3);for(const item of all)assert.equal(compileCard(item.definition,{}).compiled_program_hash,item.compiled_program_hash);
 }
 d.tokens[0].abilities[0].effects[0].token_id='missing';assert.throws(()=>compileCard(d,{}),/不存在/);
});
test('report numbers, author privacy, reopen, resolution notifications and resume are stable',()=>{
 const s={diagnostics:{},generations:{},accounts:{},identities:{}};
 const job={generation_id:'g',conversation_id:'c',round:1,owner_id:'a',kind:'mechanism-review',target_kind:'card',card_blueprint:card(),source_text:'机制',status:'awaiting_confirmation',history:[{answers:[{question:'范围',answer:'所有交战'}]}],result:{missing_capabilities:['先手'],questions:[]}};s.generations.g=job;
 collectJobDiagnostic(s,job);const number=job.diagnostic_number;assert.match(number,/^CZ-\d{6}$/);const report=s.diagnostics[job.diagnostic_id];
 assert.equal(authorReports(s,'a',number).items.length,1);assert.throws(()=>authorReports(s,'b',number),{code:'NOT_FOUND'});assert.deepEqual(authorReports(s,'b').items,[]);
 assert.throws(()=>resumeContext(s,'a',number),{code:'NOT_READY'});assert.throws(()=>resolveDiagnostic(s,'b',report.id),{code:'FORBIDDEN'});
 markResolved(s,report,{resolution:'先手已验证',version:'0.8.31'});markResolved(s,report);assert.equal(inbox(s,'a').items.length,1);assert.equal(inbox(s,'b').items.length,0);
 const m=inbox(s,'a').items[0];assert(!('owner_id' in m));assert.throws(()=>readMessage(s,'b',m.id),{code:'NOT_FOUND'});readMessage(s,'a',m.id);assert.equal(inbox(s,'a').unread,0);
 assert.deepEqual(resumeContext(s,'a',number).history,job.history);assert.throws(()=>resumeContext(s,'b',number),{code:'NOT_FOUND'});
 collectJobDiagnostic(s,job);assert.equal(job.diagnostic_number,number);assert.equal(report.status,'open');assert.equal(report.resolution_history.length,1);assert.throws(()=>resumeContext(s,'a',number),{code:'NOT_READY'});
 const old=structuredClone(s);initializeReports(old);assert.equal(old.diagnostics[report.id].number,number);
 const id=recordDiagnostic(s,{stage:'draft',code:'BAD',owner:'b',message:'bad sk-secret password=hidden'});assert.notEqual(s.diagnostics[id].number,number);assert(!s.diagnostics[id].message.includes('sk-secret'));
});
