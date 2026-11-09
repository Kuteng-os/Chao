import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,builtinDefinitions,validateCardBlueprint,applyCardBlueprint} from '../src/validation.js';
import {blueprint,editorError} from '../../web/model.mjs';
import {hash} from '../src/codec.js';
const base=(name,kind='unit')=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name,flavor_text:'',kind,unit_class:kind==='unit'?'infantry':null,cost:1,operation_cost:kind==='unit'?1:0,attack:kind==='unit'?3:0,health:kind==='unit'?4:0,keywords:[],play_target:null,abilities:[],tokens:[],appearance:{emblem:kind==='unit'?'infantry':kind}});
const stats=(a=2)=>({op:'modify_stats',target:'self',attack_delta:a,health_delta:0,duration:'battle'});
const smoke={id:'core.smokescreen',version:1,params:{}};
const loss={trigger:'on_keyword_lost',keyword_id:'core.smokescreen',effects:[stats()]};
const fixtures={
 smokeLoss:{...base('刺眼光芒','order'),abilities:[{trigger:'on_play',effects:[{op:'grant_ability',target:'all_friendly_units',duration:'battle',ability:loss}]}]},
 smokeUnit:{...base('烟幕单位'),keywords:[smoke],abilities:[loss]},
 smokeAura:{...base('治安管理部'),keywords:[smoke],abilities:[{trigger:'while_active',premise:{test:'unit_keyword',target:'self',keyword_id:'core.smokescreen',state:'current'},effects:[stats()]}]},
 attackCopy:{...base('联想者'),unit_class:'fighter',appearance:{emblem:'fighter'},abilities:[{trigger:'after_attack',effects:[{op:'transfer_card',source:'attack_target',destination:'hand',mode:'copy',selection:'top',amount:1,copy_state:'current_stats'}]}]},
 jade:{...base('玉质新生','order'),abilities:[{trigger:'on_play',effects:[{op:'select_units',side:'ally',min:0,max:2,unit_filter:{name_contains:'玉石'}},{op:'destroy',target:'selected_units'},{op:'transfer_card',source:'discard',destination:'support',mode:'move',selection:'random',amount:{stat:'selected_destroyed_count'},filter:{kind:'unit',name_contains:'玉石'}}]}]},
};
const registry=Object.fromEntries(builtinDefinitions.map(definition=>[definition.id+'@'+definition.version,{definition,definition_hash:hash(definition),registry_status:'approved'}]));
test('862 fixtures compile; generator, editor and native hash contract',()=>{
 const hashes={};for(const [key,c] of Object.entries(fixtures)){
  assert.equal(editorError(c),'',key);const result=compileCard(c,registry);hashes[key]=result.compiled_program_hash;
  assert.doesNotMatch(result.rules_text,/undefined|NaN|object Object/);
 }
 writeFileSync(new URL('../../tests/fixtures/repairs862.json',import.meta.url),JSON.stringify({fixtures,hashes},null,2));
});
test('862 denies cyclic auras, unbound multi-selection and invalid copies',()=>{
 let c=structuredClone(fixtures.smokeAura);c.abilities[0].effects=[{op:'grant_keyword',target:'self',keyword_id:'core.fury',keyword_version:1,duration:'battle'}];assert.throws(()=>compileCard(c,registry));
 c=structuredClone(fixtures.jade);c.abilities[0].effects.shift();assert.throws(()=>compileCard(c,registry),/先.*选择/);
 c=structuredClone(fixtures.jade);c.abilities[0].effects[0].min=3;assert.throws(()=>compileCard(c,registry),/数量/);
 c=structuredClone(fixtures.attackCopy);c.abilities[0].trigger='on_play';assert.throws(()=>compileCard(c,registry),/攻击/);
 c=structuredClone(fixtures.smokeUnit);delete c.abilities[0].keyword_id;assert.throws(()=>compileCard(c,registry),/词条/);
});
test('862 explicitly replacing effects preserves numbers without duplicated old ability',()=>{
 const original={...base('青春岁月','order'),abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]};
 const bp=blueprint(original,'replace');validateCardBlueprint(bp,registry);
 const generated=structuredClone(original);generated.cost=9;generated.abilities[0].effects[0].filter={kind:'unit',unit_class:'tank'};
 const updated=applyCardBlueprint(generated,bp);assert.equal(updated.cost,1);assert.equal(updated.abilities.length,1);assert.equal(updated.abilities[0].effects[0].filter.unit_class,'tank');assert.doesNotThrow(()=>compileCard(updated,registry));
 const appended=applyCardBlueprint(generated,blueprint(original));assert.equal(appended.abilities.length,2);
});
