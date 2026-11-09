import test from 'node:test';
import assert from 'node:assert/strict';
import {freshCard,changeKind,blueprint,readyCard,keywordFits} from '../../web/model.mjs';
import {compileCard,validateKeyword,validateCardBlueprint,applyCardBlueprint} from '../src/validation.js';
import {DECK_SIZE,RARITIES,checkDeckCopies} from '../src/deck_rules.js';
import {makePrompt} from '../src/provider.js';
const draw={op:'draw',player:'owner',amount:2};
const card=kind=>({...changeKind(freshCard(),kind),name:'类型测试'});
test('rarity limits combine copies across hashes, names and revisions, legacy hash stays stable',()=>{
 assert.equal(DECK_SIZE,40);
 for(const [rarity,{limit}] of Object.entries(RARITIES)){
  const cards=Array.from({length:limit},(_,i)=>({card_id:'same',revision:i+1,definition:{...card('unit'),rarity,attack:i}}));
  assert.equal(checkDeckCopies(cards),'');assert.notEqual(checkDeckCopies([...cards,cards[0]]),'');
 }
 const c=card('unit');delete c.rarity;const old=compileCard(c,{});assert.equal('rarity' in old.definition,false);
 assert.equal(checkDeckCopies(Array(4).fill(c)),'');assert.notEqual(checkDeckCopies(Array(5).fill(c)),'');
 assert.notEqual(checkDeckCopies([c,{...c,rarity:'elite'}]),'');
 assert.notEqual(checkDeckCopies([{card_id:'a',definition:{...c,rarity:'elite'}},{card_id:'a',definition:{...c,name:'改名'}}]),'');
});
test('order creator fixes nonunit values, applies AI effects and preserves chosen target',()=>{
 const c=readyCard(card('order'),[]);assert.equal(c.health,0);assert.equal(c.operation_cost,0);assert.equal(c.appearance.emblem,'order');
 const b=validateCardBlueprint(blueprint(c),{}),candidate={...c,abilities:[{trigger:'on_play',effects:[draw]}]};
 const generated=applyCardBlueprint(candidate,b);assert.equal(compileCard(generated,{}).definition.kind,'order');
 c.abilities=[{trigger:'on_play',effects:[{op:'damage',target:'chosen',amount:2}]}];
 const ready=readyCard(c,[]);assert.deepEqual(ready.play_target,{side:'enemy',row:'any'});compileCard(ready,{});
 assert.throws(()=>compileCard({...ready,abilities:[]},{}));
});
test('counter blueprints fix trigger and support effect templates without arbitrary scripts',()=>{
 const c=card('counter');c.counter_trigger='enemy_order_played';
 const b=validateCardBlueprint(blueprint(c),{});const changed={...c,counter_trigger:'enemy_hq_attacked',abilities:[{trigger:'on_reveal',effects:[{op:'cancel_action'},draw]}]};
 const built=applyCardBlueprint(changed,b);assert.equal(built.counter_trigger,c.counter_trigger);compileCard(built,{});
 assert.match(makePrompt('card',[],b),/counter_trigger/);
 const k={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.counter_draw',version:1,name:'反制补给',description:'触发后抽两张牌',aliases:[],parameters:{},implementation:{kind:'template',abilities:[{trigger:'on_reveal',effects:[draw]}]}};
 const entry={...validateKeyword(k),registry_status:'approved'};const registry={[k.id+'@1']:entry};
 c.keywords=[{id:k.id,version:1,params:{}}];const result=compileCard(c,registry);assert.equal(result.compiled_program.expanded_definition.abilities[0].trigger,'on_reveal');
 assert.equal(keywordFits(k,'counter',c.counter_trigger),true);assert.equal(keywordFits(k,'order'),false);
 for(const trigger of ['enemy_unit_deployed','enemy_order_played','enemy_hq_attacked']){
  const value={...card('counter'),counter_trigger:trigger,abilities:[{trigger:'on_reveal',effects:[{op:'cancel_action'}]}]};
  if(trigger==='enemy_unit_deployed')assert.throws(()=>compileCard(value,{}));else compileCard(value,{});
  value.abilities[0].effects=[{op:'damage',target:'trigger_unit',amount:2}];
  if(trigger==='enemy_order_played')assert.throws(()=>compileCard(value,{}));else compileCard(value,{});
 }
 const invalid=card('unit');invalid.abilities=[{trigger:'on_reveal',effects:[draw]}];assert.throws(()=>compileCard(invalid,{}));
});
