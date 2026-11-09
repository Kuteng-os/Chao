import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateCardBlueprint,applyCardBlueprint} from '../src/validation.js';
import {freshCard,blueprint,readyCard,changeKind,editorError,keywordFits} from '../../web/model.mjs';
import {headquartersFor,headquartersEnvelope} from '../src/headquarters.js';
import {checkDeckCopies} from '../src/deck_rules.js';
import {summarizeMatch} from '../src/match_archive.js';
const hq={...changeKind(freshCard(),'hq'),name:'后勤总部',health:35,appearance:{emblem:'hq'},draw_rule:{base:1,adjustments:[{premise:{test:'compare',left:{count_units:{side:'enemy'}},cmp:'gt',right:{count_units:{side:'ally'}}},delta:1}]},abilities:[{trigger:'while_active',effects:[{op:'modify_stats',target:'all_friendly_units',attack_delta:1,health_delta:1,duration:'battle'}]},{trigger:'own_turn_start',effects:[{op:'heal',target:'own_hq',amount:1}]}]};
const eventHq={...hq,name:'空军总部',health:25,draw_rule:{base:0},abilities:[{trigger:'own_unit_deployed',limit:2,effects:[{op:'gain_kredits',amount:1}]}]};
const choiceHq={...hq,name:'救援总部',draw_rule:{base:1},abilities:[{trigger:'own_turn_start',target:{side:'ally',row:'any',timing:'trigger',include_hq:true},effects:[{op:'heal',target:'chosen',amount:1}]}]};
const fixtures=[hq,eventHq,choiceHq].map(d=>compileCard(d,{}));
writeFileSync(new URL('../../tests/fixtures835.json',import.meta.url),JSON.stringify({cards:fixtures}));
test('HQ blueprint round trip, fixed health/draw and readable conditional text',()=>{
 for(const d of [hq,eventHq,choiceHq]){validateCardBlueprint(blueprint(d),{});assert.deepEqual(readyCard(d,[]),d);assert.equal(editorError(d),'');assert.match(compileCard(d,{}).rules_text,/总部初始防御/);}
 const blank=changeKind(freshCard(),'hq');blank.name='空白总部';assert(compileCard(blank,{}));
 const generated={...hq,health:4,draw_rule:{base:5}};const out=applyCardBlueprint(generated,blueprint(hq));assert.equal(out.health,35);assert.deepEqual(out.draw_rule,hq.draw_rule);
 assert(!changeKind(hq,'unit').draw_rule);assert.equal(changeKind(hq,'order').health,0);
});
test('HQ structural and semantic boundaries',()=>{
 const invalid=[{health:0},{health:101},{cost:1},{attack:1},{draw_rule:{base:6}},{draw_rule:{base:1,adjustments:[{premise:hq.draw_rule.adjustments[0].premise,delta:0}]}},{draw_rule:{base:1,adjustments:[{premise:{test:'unit_state',target:'self',state:'has_attacked',value:true},delta:1}]}},{abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]},{abilities:[{trigger:'own_turn_start',target:{side:'ally',row:'any'},effects:[{op:'heal',target:'chosen',amount:1}]}]}];
 for(const patch of invalid)assert.throws(()=>compileCard({...hq,...patch},{}),JSON.stringify(patch));
 assert.match(checkDeckCopies([hq]),/总部/);
});
test('HQ refs enforce registered frozen kind and hashes',()=>{
 const c={...fixtures[0],card_id:'4ce6da9d-dcc3-435f-83f4-21cd1a811677',revision:1};const state={cards:{[c.card_id]:[c]},keywords:{},content_status:{cards:{},keywords:{},factions:{}}};const ref={card_id:c.card_id,revision:1,definition_hash:c.definition_hash};
 assert.equal(headquartersFor(state,null),null);assert.equal(headquartersFor(state,ref).definition.health,35);assert.equal(headquartersEnvelope(c).definition_hash,c.definition_hash);
 assert.throws(()=>headquartersFor(state,{...ref,definition_hash:'0'.repeat(64)}));assert.throws(()=>headquartersFor(state,{...ref,revision:2}));assert.throws(()=>headquartersFor(state,{...ref,extra:true}));
});
test('HQ contribution is archived separately from the forty card deck',()=>{
 const h={card_id:'h',revision:1,definition_hash:'hq',name:'总部',kind:'hq'};const summary=summarizeMatch({match_id:'x',players:[{},{}],decks:[[],[]],headquarters:[h,null],events:[{kind:'heal',owner:0,card_ref:{card_id:'h',revision:1},amount:3}]});
 assert.equal(summary.players[0].headquarters.name,'总部');assert.equal(summary.players[0].cards[0].heal,3);assert.equal(summary.players[0].cards[0].copies,1);assert.equal(summary.players[1].headquarters,null);
});

test('HQ keyword picker filters incompatible trigger timings',()=>{
 const keyword=trigger=>({implementation:{kind:'template',abilities:[{trigger,effects:[{op:'draw',player:'owner',amount:1}]}]}});
 assert.equal(keywordFits(keyword('own_turn_start'),'hq'),true);
 assert.equal(keywordFits(keyword('on_play'),'hq'),false);
 assert.equal(keywordFits(keyword('on_death'),'hq'),false);
});
