import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,validateCardBlueprint} from '../src/validation.js';
import {freshCard,changeKind,blueprint,editorError} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
import {resumeContext,authorReports} from '../src/diagnostics.js';
import {createReview} from '../src/mechanism_reviews.js';
const base=(name,kind='unit')=>({...changeKind(freshCard(),kind),name,health:kind==='unit'?8:0});
const schedule=(effects,extra={})=>({op:'schedule',trigger:'next_own_turn_start',effects,...extra});
const ignite={...base('点燃','order'),play_target:{side:'enemy',row:'any'},abilities:[{trigger:'on_play',effects:[schedule([{op:'damage',target:'chosen',amount:3}],{repeat:'each_turn',lifetime:'target'})]}]};
const rhino={...base('犀牛'),abilities:[{trigger:'on_damaged',damage_step:2,limit:100,effects:[schedule([{op:'modify_stacks',target:'self',stack:'heavy_armor',amount:1,duration:'battle'}],{lifetime:'source'})]}]};
const token={token_id:'evolution',name:'进化单位',kind:'unit',unit_class:'tank',cost:2,operation_cost:1,attack:5,health:7,keywords:[],play_target:null,abilities:[{trigger:'on_summon',effects:[{op:'gain_hq_defense',player:'owner',amount:1}]}]};
const evolution={...base('玉化'),tokens:[token],abilities:[{trigger:'on_play',effects:[schedule([{op:'transform',target:'self',token_id:'evolution',inherit:'none'}],{after_turns:3,lifetime:'source'})]},{trigger:'on_death',effects:[{op:'damage',target:'enemy_hq',amount:10}]}]};
const cancel={...base('反制预备'),abilities:[{trigger:'on_play',effects:[{op:'prepare_counter',duration:'match'}]}]};
const cards=[ignite,rhino,evolution,cancel];
writeFileSync(new URL('../../tests/reports848.json',import.meta.url),JSON.stringify({cards:cards.map(c=>compileCard(c,{}))}));
test('114-124 schemas, blueprints, keywords and concise descriptions',()=>{
 for(const c of cards){assert.equal(editorError(c),'');assert.doesNotThrow(()=>validateCardBlueprint(blueprint(c),{}));const compiled=compileCard(c,{});assert(!/undefined|\[object/.test(compiled.rules_text));}
 for(const c of [rhino,evolution,cancel])assert.doesNotThrow(()=>validateKeyword({schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.regression848',version:1,name:'回归',description:'机制回归',aliases:[],parameters:{},implementation:{kind:'template',abilities:c.abilities}}));
});
test('scheduled state is explicit and bounded',()=>{
 const invalid=(card,fn)=>{const c=structuredClone(card);fn(c);assert.throws(()=>compileCard(c,{}));};
 invalid(ignite,c=>c.play_target=null);
 invalid(ignite,c=>c.abilities[0].effects[0].lifetime='source');
 invalid(rhino,c=>c.abilities[0].effects[0].lifetime='target');
 invalid(rhino,c=>c.abilities[0].limit=1000);
 invalid(rhino,c=>c.abilities[0].effects[0].times=2);
 invalid(rhino,c=>c.abilities[0].effects[0].effects=[schedule([{op:'noop'}])]);
 invalid(evolution,c=>c.tokens[0]={...changeKind(base('指令'),'order'),token_id:'evolution'});
 invalid(evolution,c=>c.abilities[0].effects[0].effects[0].token_id='absent');
 invalid(ignite,c=>c.abilities[0].effects=[{op:'prepare_counter',duration:'battle'}]);
});
test('latest capabilities are present in all three generation prompts',()=>{
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[],blueprint(ignite));for(const term of ['mechanics-49','prepare_counter','transform','each_turn','limit 现在允许1..999'])assert(p.includes(term),term);assert(Buffer.byteLength(p)<200000);}
});
test('resolved keyword reports resume the latest clarified rules and original name',async()=>{
 const old={generation_id:'old',owner_id:'author',kind:'mechanism-review',target_kind:'keyword',suggested_name:'玉化',source_text:'三个回合后进化',card_blueprint:null,conversation_id:'conversation',round:1,history:[]};
 const latest={...old,generation_id:'latest',round:4,history:[{formal_text:'第三个己方回合开始进化',answers:[{answer:'原位置，不继承强化，不结算阵亡'}]}]};
 const state={diagnostics:{report:{number:'CZ-000121',owner_id:'author',generation_id:'old',status:'resolved'}},generations:{old,latest},keywords:{}};
 assert.equal(authorReports(state,'author').items[0].can_resume,true);assert.equal(resumeContext(state,'author','CZ-000121').history.length,1);
 const service={async idem(owner,kind,body,fn){return fn(state);},rate(){},schedule(){}};
 const result=await createReview(service,'author',{kind:'keyword',report_number:'CZ-000121',request_id:'request'});
 const job=state.generations[result.generation_id];assert.equal(job.suggested_name,'玉化');assert.deepEqual(job.history,latest.history);assert.equal(job.card_blueprint,null);
 assert.throws(()=>resumeContext(state,'other','CZ-000121'));
});
