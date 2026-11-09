import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard,validateKeyword} from '../src/validation.js';
import {makePrompt} from '../src/provider.js';
import {keywordFits,defaultEffect} from '../../web/model.mjs';
import {schemas} from '../src/validation.js';
const card = e => ({schema_version:'1.0.0',ruleset_version:'frontline-1',name:'以寡敌众',flavor_text:'',kind:'unit',unit_class:'infantry',cost:1,operation_cost:1,attack:3,health:4,keywords:[],play_target:null,abilities:[{trigger:'on_play',effects:[e]}],tokens:[],appearance:{emblem:'infantry'}});
const effect = stat => ({op:'modify_stats',target:'self',attack_delta:{stat},health_delta:0,duration:'battle'});
test('count references compile in direct cards, registered keywords and generated cards',()=>{
 for(const stat of ['enemy_unit_count','friendly_unit_count','other_friendly_unit_count']){
  const e=effect(stat),c=card(e),compiled=compileCard(c,{});
  assert.deepEqual(JSON.parse(JSON.stringify(compiled.definition.abilities[0].effects[0])),e);
  assert.match(compiled.rules_text,/在场单位数/);assert(!compiled.rules_text.includes('[object Object]'));
  const kw={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.count',version:1,name:'以寡敌众',description:'登场时按敌方单位数获得攻击力。',aliases:[],parameters:{},implementation:{kind:'template',abilities:c.abilities}};
  const registry={[kw.id+'@1']:{...validateKeyword(kw),registry_status:'approved'}};
  const bound={...c,abilities:[],keywords:[{id:kw.id,version:1,params:{}}]};
  assert.deepEqual(JSON.parse(JSON.stringify(compileCard(bound,registry).compiled_program.expanded_definition.abilities)),c.abilities);
  for(const kind of ['unit','order','counter']){
   const d=card({op:'damage',target:'enemy_hq',amount:{stat}});
   if(kind!=='unit')Object.assign(d,{kind,unit_class:null,attack:0,health:0,operation_cost:0,appearance:{emblem:kind}});
   if(kind==='counter'){d.counter_trigger='enemy_order_played';d.abilities[0].trigger='on_reveal';}
   assert(compileCard(d,{}));
   const t={...d,token_id:'child'};for(const k of ['schema_version','ruleset_version','appearance','tokens'])delete t[k];
   assert(compileCard({...c,tokens:[t],abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:'child',amount:1,player:'owner'}]}]},{}));
  }
 }
});
test('dynamic inputs remain a strict whitelist and fixed value boundaries remain unchanged',()=>{
 for(const bad of [{stat:'enemy_hand_count'},{stat:'enemy_unit_count',formula:'eval'}, {stat:'enemy_unit_count',multiplier:2},{},null,6,-6,1.5,true])
  assert.throws(()=>compileCard(card({...effect('enemy_unit_count'),attack_delta:bad}),{}));
 assert.throws(()=>compileCard(card({...effect('enemy_unit_count'),attack_delta:0}),{}));
 const schema=schemas.card.definitions.effect.oneOf.find(s=>s.properties.op.const==='modify_stats');
 assert.equal(defaultEffect(schema).attack_delta,1);assert.equal(defaultEffect(schema).health_delta,0);
});
test('all DeepSeek stages advertise snapshot counts and editor permits them for orders',()=>{
 for(const kind of ['mechanism-review','card','keyword']){
  const p=makePrompt(kind,[]);assert.match(p,/enemy_unit_count/);assert.match(p,/不是持续光环/);assert.match(p,/计数为0合法/);
 }
 const kw={implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{op:'damage',target:'enemy_hq',amount:{stat:'enemy_unit_count'}}]}]}};
 assert(keywordFits(kw,'order'));kw.implementation.abilities[0].effects[0].amount.stat='source_base_health';assert(!keywordFits(kw,'order'));
});
