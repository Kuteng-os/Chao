import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,validateCardBlueprint,applyCardBlueprint} from '../src/validation.js';
import {freshCard,blueprint,readyCard} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
import {CardService} from '../src/service.js';
// Retired online generation limit; the DSH plugin pages the rules. 0.9.10 schema additions need the headroom.
const PROMPT_LIMIT=210000;
const order=name=>({...freshCard(),name,kind:'order',unit_class:null,attack:0,health:0,operation_cost:0,appearance:{emblem:'order'}});
const selector={side:'ally',card_name:'第4集团军“兔子”'};
const repeated={...order('火力集中'),cost:5,abilities:[{trigger:'on_play',repeat:{count_units:selector},effects:[{op:'damage',target:'all_enemy_units',amount:1},{op:'damage',target:'enemy_hq',amount:1}]}]};
const discounted={...order('单点狙杀'),cost:7,cost_reduction:{per_unit:selector,amount:2},play_target:{side:'enemy',row:'any'},abilities:[{trigger:'on_play',effects:[{op:'damage',target:'chosen',amount:6}]}]};
writeFileSync(new URL('../../tests/fixtures834.json',import.meta.url),JSON.stringify({cards:[repeated,discounted].map(d=>compileCard(d,{}))}));
test('66/67 shared contract, text, fixed blueprint and model know repeat/discount',()=>{
 for(const c of [repeated,discounted]){const result=compileCard(c,{});assert(!result.rules_text.includes('[object Object]'));validateCardBlueprint(blueprint(c),{});assert.deepEqual(readyCard(c,[]),c);}
 assert.match(compileCard(repeated,{}).rules_text,/重复.*兔子.*次/);
 assert.match(compileCard(discounted,{}).rules_text,/费用减少.*兔子.*最低0/);
 const bp=blueprint(discounted),extra=order('额外');extra.abilities=[];
 assert.deepEqual(applyCardBlueprint(extra,bp).cost_reduction,discounted.cost_reduction);
 extra.cost_reduction={...discounted.cost_reduction,amount:1};assert.throws(()=>applyCardBlueprint(extra,bp),/减费/);
 const newMechanism=applyCardBlueprint(discounted,blueprint(order('新卡')));assert.equal(newMechanism.cost_reduction.amount,2);assert.equal(newMechanism.cost,3);
 const keyword={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.repeat',version:1,name:'反复轰击',description:'按单位数逐次伤害',aliases:[],parameters:{},implementation:{kind:'template',abilities:repeated.abilities}};
 assert(validateKeyword(keyword));
 for(const kind of ['card','keyword','mechanism-review']){const text=makePrompt(kind,[]);assert(text.includes('cost_reduction'));assert(text.includes('repeat'));assert(Buffer.byteLength(text)<PROMPT_LIMIT);}
});
test('reject invalid repeats, ambiguous selectors and invalid discounts',()=>{
 for(const repeat of [-1,0,17,1.5,{stat:'source_attack'},{count_units:{side:'all'}},{count_units:{side:'ally',card_name:' '}}]){const c=structuredClone(repeated);c.abilities[0].repeat=repeat;assert.throws(()=>compileCard(c,{}));}
 const aura=freshCard();aura.name='无效光环';aura.abilities=[{trigger:'while_active',repeat:2,effects:[{op:'modify_stats',target:'self',attack_delta:1,health_delta:0,duration:'battle'}]}];assert.throws(()=>compileCard(aura,{}));
 for(const reduction of [{per_unit:selector,amount:0},{per_unit:selector,amount:13},{per_unit:{side:'ally',card_name:' 兔子'},amount:2},{per_unit:selector,amount:2,formula:'*'}])assert.throws(()=>compileCard({...discounted,cost_reduction:reduction},{}));
});
test('68/69 previously exhausted account can continue; configurable quota stays bounded',async()=>{
 let calls=0;
 const owner='author',day=new Date(Date.now()+8*3600000).toISOString().slice(0,10);
 const state={limits:{[owner]:{day,attempts:50,created:[]}},generations:{},keywords:{},factions:{}};
 const store={state,transaction:async fn=>fn(state)};
 const provider={generate:async ({onAttempt})=>{await onAttempt();calls++;return {result:{status:'review',formal_text:'请确认范围。',questions:[{id:'q',question:'统计哪一方？',options:['己方','敌方']}],missing_capabilities:[]}};}};
 const service=new CardService(store,provider);service.keywords=()=>({definitions:[]});
 assert.equal(service.dailyLimit,500);
 const job=id=>({generation_id:id,kind:'mechanism-review',target_kind:'card',status:'queued',owner_id:owner,source_text:'测试',card_blueprint:order('测试'),round:1,history:[],attempts:0});
 state.generations.one=job('one');await service.run('one');assert.equal(calls,1);assert.equal(state.generations.one.status,'awaiting_confirmation');assert.equal(state.limits[owner].attempts,51);
 service.dailyLimit=51;state.generations.two=job('two');await service.run('two');assert.equal(calls,1);assert.equal(state.generations.two.error.code,'RATE_LIMITED');assert.match(state.generations.two.error.message,/51.*北京时间.*00:00.*会话/);
 state.limits[owner].day='2020-01-01';state.generations.three=job('three');await service.run('three');assert.equal(calls,2);assert.equal(state.limits[owner].attempts,1);
 assert.throws(()=>new CardService(store,provider,{dailyLimit:0}));assert.equal(new CardService(store,provider,{dailyLimit:250}).dailyLimit,250);
});
