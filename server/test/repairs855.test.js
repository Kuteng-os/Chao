import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,builtinDefinitions} from '../src/validation.js';
import {validatePremise,premiseText} from '../src/premises.js';
import {premiseSummary} from '../../web/mechanism.mjs';
const registry=Object.fromEntries(builtinDefinitions.map(d=>[d.id+'@'+d.version,{...validateKeyword(d,{allowBuiltin:true}),registry_status:'approved'}]));
const f=JSON.parse(readFileSync(new URL('../../tests/fixtures/repairs855.json',import.meta.url),'utf8'));
test('855 returned-instance discount and previous own-turn deployment compile in cards and templates',()=>{
 const hashes={};for(const [key,def] of Object.entries(f)){const c=compileCard(def,registry);hashes[key]={definition_hash:c.definition_hash,compiled_program_hash:c.compiled_program_hash};assert.doesNotMatch(c.rules_text,/undefined|NaN/);}
 writeFileSync(new URL('../../tests/fixtures/parity855.json',import.meta.url),JSON.stringify(hashes));
 const kw={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'test.history',version:1,name:'历史回手',aliases:[],description:'回手后减费',parameters:{},implementation:{kind:'template',abilities:[{trigger:'on_play',premise:f.history.abilities[0].premise,effects:[{op:'return_to_hand',target:'self',cost_delta:-2,duration:'end_of_turn'}]}]}};
 assert.doesNotThrow(()=>validateKeyword(kw));
 assert.match(compileCard(f.bounce,registry).rules_text,/本回合内该牌下次打出费用-2/);
 for(const text of [premiseText(f.history.abilities[0].premise),premiseSummary(f.history.abilities[0].premise)])assert.match(text,/己方上个回合部署过.*忧郁/);
});
test('return-cost duration is bounded and paired; ambiguous partial modifiers are rejected',()=>{
 for(const change of [e=>delete e.duration,e=>delete e.cost_delta,e=>e.cost_delta=0,e=>e.cost_delta=-13,e=>e.duration='match',e=>e.target='own_hq']){
  const c=structuredClone(f.bounce);change(c.abilities[0].effects[0]);assert.throws(()=>compileCard(c,registry));
 }
 const c=structuredClone(f.bounce);delete c.abilities[0].effects[0].duration;delete c.abilities[0].effects[0].cost_delta;assert.doesNotThrow(()=>compileCard(c,registry));
});
test('deployment history accepts stable card filters, rejects live state or arbitrary queries',()=>{
 for(const filter of [{},{sin:'gloom'},{unit_classes:['fighter','bomber'],name_contains:'追击'},{card_name:'目标',faction_id:'408c3c32-19c5-49ce-9a9d-055c38d516ba'}]){
  const p={test:'deployed_last_turn',player:'opponent',filter};assert.doesNotThrow(()=>validatePremise(p));
  const c=structuredClone(f.history);c.abilities[0].premise=p;assert.doesNotThrow(()=>compileCard(c,registry));
 }
 for(const filter of [{sin:'unknown'},{row:'front'},{attack:{cmp:'gt',value:2}},{name_contains:'   '},{side:'enemy'}]){
  const c=structuredClone(f.history);c.abilities[0].premise.filter=filter;assert.throws(()=>compileCard(c,registry));
 }
});
