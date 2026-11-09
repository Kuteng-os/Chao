import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard} from '../src/validation.js';
import {freshCard,readyCard} from '../../web/model.mjs';
import {ruleCapabilities,rulesSummary} from '../src/rule_capabilities.js';

test('delayed targets support deployment binding and explicit trigger choice without rewriting source',()=>{
 for(const trigger of ['on_death','own_turn_start','own_turn_end'])for(const timing of [undefined,'deploy','trigger']){
  const card={...freshCard(),name:'目标绑定'};
  card.abilities=[{trigger,target:{side:'enemy',row:'any',...(timing?{timing}:{})},effects:[{op:'damage',target:'chosen',amount:{stat:'source_base_health'}}]}];
  const frozen=JSON.stringify(card),compiled=compileCard(card,{});
  assert.equal(JSON.stringify(card),frozen);
  assert.equal(compiled.rules_text.includes('部署时选定'),timing!=='trigger');
  assert.equal(readyCard(card,[]).play_target,null);
  card.abilities[0].target.timing='arbitrary';assert.throws(()=>compileCard(card,{}));
 }
 assert.equal(ruleCapabilities.delayed_target_default,'deploy');
 assert.match(rulesSummary,/离场/);assert.match(rulesSummary,/余额不足不触发/);
});

test('independent on-play target does not acquire a duplicate global target in workshop',()=>{
 const card={...freshCard(),name:'独立部署目标'};
 card.abilities=[{trigger:'on_play',target:{side:'ally',row:'any'},effects:[{op:'heal',target:'chosen',amount:1}]}];
 const ready=readyCard(card,[]);
 assert.equal(ready.play_target,null);assert(compileCard(ready,{}));
 delete card.abilities[0].target;
 assert.deepEqual(readyCard(card,[]).play_target,{side:'enemy',row:'any'});
});
