import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateKeyword} from '../src/validation.js';
import {freshCard,blueprint} from '../../web/model.mjs';
import {makePrompt,promptSchema} from '../src/provider.js';
import {schemas} from '../src/validation.js';
import Ajv from 'ajv';
import {ruleCapabilities} from '../src/rule_capabilities.js';
// Retired online generation limit; the DSH plugin pages the rules. 0.9.10 schema additions need the headroom.
const PROMPT_LIMIT=210000;

const front={test:'unit_state',target:'self',state:'in_front'};
const free={trigger:'while_active',premise:front,effects:[{op:'modify_operation_cost',target:'self',cost_set:0,duration:'battle'}]};
const copy={op:'transfer_card',source:'self',destination:'support',mode:'copy',selection:'random',amount:1,copy_buff:{attack_delta:2,health_delta:2,duration:'battle'}};
const card={...freshCard(),name:'游骑兵合成师',kind:'unit',unit_class:'infantry',cost:5,operation_cost:1,attack:5,health:5,keywords:[],abilities:[{trigger:'after_move',premise:front,effects:[copy]},free]};
const keyword={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.frontline_cost',version:1,name:'前线协同',aliases:[],description:'前线行动费为0。',parameters:{},implementation:{kind:'template',abilities:[free]}};
const compileAbilities=abilities=>compileCard({...card,abilities},{});

test('906 frontline fixed operation cost and enhanced full self-copy compile without changing old definitions',()=>{
 const fixtures={ranger:card,permanent:{...card,name:'永久复制测试',abilities:[{trigger:'after_move',premise:front,effects:[{...copy,copy_buff:{...copy.copy_buff,duration:'match'}}]},free]},plain:{...card,name:'白板',abilities:[]}};
 const hashes=Object.fromEntries(Object.entries(fixtures).map(([key,value])=>[key,compileCard(value,{}).compiled_program_hash]));
 writeFileSync(new URL('../../tests/fixtures/repairs906.json',import.meta.url),JSON.stringify({fixtures,hashes,keyword},null,2));
 assert.match(compileCard(card,{}).detailed_text,/行动费.*0/);
 assert.match(compileCard(card,{}).detailed_text,/\+2\/\+2/);
 assert.doesNotThrow(()=>validateKeyword(keyword));
 assert.doesNotThrow(()=>validateKeyword({...keyword,id:'custom.copy_buff',implementation:{kind:'template',abilities:[card.abilities[0]]}}));
 for(const state of ['in_front','in_support'])assert.doesNotThrow(()=>compileAbilities([{...free,premise:{...front,state}}]));
 assert.doesNotThrow(()=>compileAbilities([{...free,premise:{test:'not',item:front}}]));
 const ajv=new Ajv({strict:false});
 const validate=ajv.compile(JSON.parse(promptSchema(schemas.card)));
 assert(validate(card),JSON.stringify(validate.errors));
 for(const effect of [{...free.effects[0],cost_delta:-1},{...copy,copy_buff:{...copy.copy_buff,duration:'forever'}}]){
  const bad={...card,abilities:[{trigger:'on_play',effects:[effect]}]};
  assert(!validate(bad),'compact contract must retain new field constraints');
 }
});

test('906 all generation paths know exact frontline costs and enhanced self-copy',()=>{
 assert.equal(ruleCapabilities.battle_rules.minimum_client_build,906);
 assert.equal(ruleCapabilities.revision,'mechanics-49');
 for(const kind of ['card','keyword','mechanism-review']){
  for(const bp of [null,blueprint(card),blueprint(card,'append'),blueprint(card,'replace')]){
   const prompt=makePrompt(kind,[],bp);
   for(const text of ['cost_set:0','copy_buff','after_move'])assert(prompt.includes(text),kind+' '+text);
   assert(Buffer.byteLength(prompt)<PROMPT_LIMIT,kind+' prompt too large: '+Buffer.byteLength(prompt));
  }
 }
});

test('906 new cost and copy fields are bounded and cannot introduce recursive aura queries',()=>{
 for(const fields of [{cost_set:13},{cost_set:-1},{cost_set:0,cost_delta:-1},{}]){
  const effect={op:'modify_operation_cost',target:'self',duration:'battle',...fields};
  assert.throws(()=>compileAbilities([{...free,effects:[effect]}]));
 }
 assert.throws(()=>compileAbilities([{...free,effects:[{op:'modify_operation_cost',target:'self',cost_delta:0,duration:'battle'}]}]));
 for(const premise of [{...front,target:'trigger_unit'},{...front,state:'has_attacked'},{test:'unit_keyword',target:'self',keyword_id:'core.blitz',state:'current'}])assert.throws(()=>compileAbilities([{...free,premise}]));
 for(const change of [{mode:'move'},{destination:'hand'},{copy_buff:{attack_delta:0,health_delta:0,duration:'battle'}},{copy_buff:{attack_delta:101,health_delta:2,duration:'battle'}}])assert.throws(()=>compileAbilities([{trigger:'after_move',effects:[{...copy,...change}]}]));
 assert.doesNotThrow(()=>compileAbilities([{trigger:'on_play',effects:[{op:'modify_operation_cost',target:'self',cost_delta:1,duration:'battle'}]}]));
});
