import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard,validateKeyword} from '../src/validation.js';
import {ruleCapabilities,rulesSummary} from '../src/rule_capabilities.js';
import {makePrompt} from '../src/provider.js';

const card=effect=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name:'遗赠',flavor_text:'',kind:'unit',unit_class:'infantry',cost:1,operation_cost:1,attack:2,health:3,keywords:[],play_target:null,abilities:[{trigger:'on_death',effects:[effect]}],tokens:[],appearance:{emblem:'infantry'}});
const keyword=effect=>({schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.jade_search',version:1,name:'遗赠',description:'阵亡时从牌组召唤玉石。',aliases:[],parameters:{x:{type:'integer',minimum:1,maximum:3}},implementation:{kind:'template',abilities:[{trigger:'on_death',effects:[{...effect,amount:{param:'x'}}]}]}});
test('named deck operations compile directly and as independently registered parameterized keywords',()=>{
 for(const op of ['search_deck','summon_from_deck']){
  const effect={op,card_name:'玉石',amount:1},direct=compileCard(card(effect),{});
  assert.match(direct.rules_text,/玉石/);assert.equal(direct.definition.tokens.length,0);
  const kw=keyword(effect),validated=validateKeyword(kw),registry={[kw.id+'@1']:{...validated,registry_status:'approved'}};
  for(const x of [1,2,3]){const c=card(effect);c.abilities=[];c.keywords=[{id:kw.id,version:1,params:{x}}];assert.equal(compileCard(c,registry).compiled_program.expanded_definition.abilities[0].effects[0].amount,x);}
  kw.parameters.x.maximum=4;assert.throws(()=>validateKeyword(kw));
 }
});
test('named deck operations reject unsafe names, unsupported selectors and invalid quantities',()=>{
 for(const op of ['search_deck','summon_from_deck']){
  const e={op,card_name:'玉石',amount:1};
  for(const name of ['',' ',' 玉石','玉石 ','玉\n石','玉'.repeat(65)])assert.throws(()=>compileCard(card({...e,card_name:name}),{}));
  for(const amount of [0,4,-1,true,1.5,{stat:'source_base_health'}])assert.throws(()=>compileCard(card({...e,amount}),{}));
  for(const extra of [{player:'opponent'},{card_id:'x'},{row:'front'},{random:true}])assert.throws(()=>compileCard(card({...e,...extra}),{}));
 }
});
test('all model stages know card names are not keyword references and do not substitute tokens',()=>{
 assert.equal(ruleCapabilities.revision,'mechanics-49');assert(!ruleCapabilities.unsupported.includes('search_deck'));
 for(const op of ['search_deck','summon_from_deck']){assert(ruleCapabilities.operations.includes(op));assert(ruleCapabilities.template_operations.includes(op));}
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[]);assert.match(p,/summon_from_deck/);assert.match(p,/玉石/);assert.match(p,/卡名不是词条/);}
 assert.match(rulesSummary,/后援线已满/);
});
