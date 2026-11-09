import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileCard,builtinDefinitions,rulesText,validateKeyword,docsURL} from '../src/validation.js';
const fixtures=JSON.parse(readFileSync(new URL('../../tests/fixtures/repairs850.json',import.meta.url),'utf8'));
const definitions=[...builtinDefinitions,...['core_blitz','core_guard'].map(n=>JSON.parse(readFileSync(new URL(`examples/keywords/${n}.json`,docsURL),'utf8')))];
const registry=Object.fromEntries(definitions.map(d=>[`${d.id}@${d.version}`,{...validateKeyword(d,{allowBuiltin:true}),registry_status:'approved'}]));
test('850 reported mechanisms compile and have printable rules',()=>{
 for(const [key,card] of Object.entries(fixtures)){
  const compiled=compileCard(card,registry);
  const text=rulesText(compiled.expanded_definition??compiled.definition??card);
  assert.ok(text.length>4,key);assert.doesNotMatch(text,/undefined|NaN/,key);
 }
});
test('850 references and event lifetimes remain bounded',()=>{
 for(const [name,change] of [
  ['attack_gain',c=>c.abilities[0].trigger='own_turn_start'],
  ['entry',c=>c.abilities[0].effects[0].trigger='next_own_turn_start'],
  ['hand_move',c=>c.abilities[0].effects[0].destination='unknown'],
  ['death_ground',c=>c.abilities[0].trigger='on_play'],
  ['set_health',c=>c.abilities[0].effects[1].op='modify_stats'],
  ['once',c=>delete c.abilities[0].limit],
  ['low_health',c=>c.abilities[0].effects[0].unit_filter.health.cmp='arbitrary']
 ]){const c=structuredClone(fixtures[name]);change(c);assert.throws(()=>compileCard(c,registry),name);}
});

test('veteran authoring retains preset and rejects invalid forms',async()=>{
 const {blueprint,readyCard,defaultEffect,labels}=await import('../../web/model.mjs');
 const {applyCardBlueprint,schemas}=await import('../src/validation.js');
 const c=fixtures.veteran;
 assert.deepEqual(blueprint(c).veteran,c.veteran);
 assert.deepEqual(applyCardBlueprint(structuredClone(c),blueprint(c)).veteran,c.veteran);
 assert.ok(!readyCard({...c,kind:'order'},[]).veteran);
 const missing=structuredClone(c);missing.veteran.token_id='missing';assert.throws(()=>compileCard(missing,registry));
 const wrong=structuredClone(c);wrong.tokens[0].kind='order';assert.throws(()=>compileCard(wrong,registry));
 const self=structuredClone(c);self.tokens[0].abilities=[{trigger:'on_veteran',effects:[{op:'become_veteran',target:'self'}]}];assert.doesNotThrow(()=>compileCard(self,registry));
 const bad=structuredClone(c);bad.kind='hq';bad.cost=0;bad.unit_class=null;bad.attack=0;bad.operation_cost=0;delete bad.veteran;bad.keywords=[];bad.abilities=[{trigger:'on_veteran',effects:[{op:'draw',player:'owner',amount:1}]}];assert.throws(()=>compileCard(bad,registry));
 assert.equal(labels.become_veteran,'升为老兵');
 assert.equal(defaultEffect(schemas.card.definitions.effect.oneOf.find(x=>x.properties.op.const==='grant_ability')).ability.trigger,'after_attack');
});

test('web premise summaries distinguish veteran, row and combat history',async()=>{
 const {premiseSummary,countText}=await import('../../web/mechanism.mjs');
 assert.equal(premiseSummary({test:'unit_state',target:'self',state:'in_front'}),'自身位于前线');
 assert.equal(premiseSummary({test:'unit_state',target:'self',state:'is_veteran'}),'自身是老兵');
 assert.equal(premiseSummary({test:'compare',left:{stat:'source_destroyed_count'},cmp:'gt',right:0}),'本卡本次消灭的单位数大于0');
 const text=countText({side:'ally',adjacent_to:'self',keyword_id:'core.guard',health:{cmp:'gt',value:7}});
 assert.match(text,/相邻/);assert.match(text,/守护/);assert.match(text,/防御大于7/);
});
