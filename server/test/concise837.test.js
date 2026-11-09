import test from 'node:test';
import assert from 'node:assert/strict';
import {rulesText,compileCard} from '../src/validation.js';
import {freshCard,changeKind} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
import {compactRules} from '../src/rules_compact.js';
test('concise display preserves executable groups, numeric boundaries, durations and names',()=>{
 const c={...changeKind(freshCard(),'order'),name:'文字验证',abilities:[{trigger:'on_play',premise:{test:'compare',left:{stat:'enemy_unit_count'},cmp:'gt',right:{stat:'friendly_unit_count'}},effects:[{op:'draw',player:'owner',amount:2},{op:'draw',player:'opponent',amount:1}]}]};
 const before=JSON.stringify(c),compiled=compileCard(c,{}),text=compiled.rules_text;
 assert.equal(JSON.stringify(c),before);assert.match(text,/敌方在场单位更多/);assert.match(text,/抽2张牌；敌方抽1张牌/);assert(!text.includes('然后'));
 assert.equal(compiled.definition_hash,compileCard(c,{}).definition_hash);
 const name='本次在场期间；然后';assert(compactRules('将【'+name+'】加入手牌').includes('【'+name+'】'));
 c.abilities=[{trigger:'on_play',effects:[{op:'damage',target:'enemy_hq',amount:1},{op:'damage',target:'enemy_hq',amount:1}]}];
 assert.equal((rulesText(c).match(/1点伤害/g)??[]).length,2);assert(!rulesText(c).includes('2点伤害'));
 c.abilities=[{trigger:'on_play',effects:[{op:'modify_stats',target:'all_friendly_units',attack_delta:2,health_delta:2,duration:'match'},{op:'modify_operation_cost',target:'all_friendly_units',cost_delta:-1,duration:'end_of_turn'}]}];
 assert.match(rulesText(c),/\+2\/\+2（永久）/);assert.match(rulesText(c),/行动费-1（本回合）/);
});
test('all DeepSeek stages require concise complete descriptions with no executable merges',()=>{
 for(const kind of ['card','keyword','mechanism-review']){
  const text=makePrompt(kind,[]);assert(text.includes('20～60字'));assert(text.includes('不能合并、删除或重排可执行能力组与操作'));
 }
 assert(!makePrompt('mechanism-review',[]).includes('每次受到攻击或反击时，在伤害倍率结算后'));
});
test('copy description explicitly retains permanent attachments',()=>{
 const c={...freshCard(),name:'复制',abilities:[{trigger:'on_death',effects:[{op:'transfer_card',source:'self',destination:'deck',mode:'copy',selection:'random',amount:1}]}]};
 assert.equal(rulesText(c),'阵亡：将自身的1张复制洗入己方牌库（保留永久强化）。');
});
