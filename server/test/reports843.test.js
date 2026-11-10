import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,applyCardBlueprint,validateCardBlueprint,validateKeyword,schemas} from '../src/validation.js';
import {freshCard,changeKind,blueprint,editorError} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
// Retired online generation limit; the DSH plugin pages the rules. 0.9.10 schema additions need the headroom.
const PROMPT_LIMIT=210000;
const faction='a1b80fcd-cf3e-4f1d-8759-207773c93b8c';
const base=(name,kind='order')=>({...changeKind(freshCard(),kind),name});
const returner={...base('阵亡回顶','unit'),abilities:[{trigger:'on_death',effects:[{op:'transfer_card',source:'self',mode:'move',destination:'hand',selection:'random',amount:1,overflow:'deck_top'}]}]};
const guardBonus={...base('烈焰'),damage_bonuses:[{filter:{keyword_id:'core.guard'},amount:2}],abilities:[{trigger:'on_play',effects:[{op:'damage',target:'all_enemy_units',amount:2}]}]};
const classBonus={...base('步兵追加'),abilities:[{trigger:'on_play',effects:[{op:'damage',target:'all_enemy_units',amount:2,bonuses:[{filter:{unit_classes:['infantry']},amount:2}]}]}]};
const killHQ={...base('按击杀加防御'),abilities:[{trigger:'on_play',effects:[{op:'damage',target:'all_units',amount:1},{op:'if_killed',per_unit:true,effects:[{op:'gain_hq_defense',player:'owner',amount:1}]}]}]};
const token={token_id:'soldier',kind:'unit',name:'衍生步兵',cost:1,operation_cost:1,unit_class:'infantry',attack:1,health:1,keywords:[],abilities:[],play_target:null};
const killSummon={...base('按击杀召唤'),tokens:[token],abilities:[{trigger:'on_play',effects:[{op:'damage',target:'all_units',amount:1},{op:'if_killed',per_unit:true,effects:[{op:'summon',token_id:'soldier',amount:1,row:'support'}]}]}]};
const cost={...base('元素灵','unit'),abilities:[{trigger:'on_death',effects:[{op:'modify_hand_cost',selection:'chosen',cost_delta:-1,duration:'hand',filter:{faction_id:faction}}]}]};
const search={...base('琉璃玉石','unit'),abilities:[{trigger:'on_death',effects:[{op:'transfer_card',source:'deck',mode:'move',destination:'support',selection:'chosen',amount:1,filter:{kind:'unit',faction_id:faction}}]}]};
const cards=[returner,guardBonus,classBonus,killHQ,killSummon,cost,search];
const fixtures=cards.map(c=>compileCard(c,{}));
writeFileSync(new URL('../../tests/reports843.json',import.meta.url),JSON.stringify({cards:fixtures}));
test('99-113 schemas and display and blueprint compile',()=>{
 for(const c of cards){assert.equal(editorError(c),'');assert.doesNotThrow(()=>validateCardBlueprint(blueprint(c),{}));const compiled=compileCard(c,{});assert(!/undefined|\[object/.test(compiled.rules_text));}
 const zero={...base('零费'),cost:0,abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]};
 assert.doesNotThrow(()=>validateCardBlueprint(blueprint(zero),{}));assert.doesNotThrow(()=>compileCard(zero,{}));
});
test('append bonus retains fixed damage exactly once through provider/service merge',()=>{
 const fixed=structuredClone(guardBonus);delete fixed.damage_bonuses;
 const bp=blueprint(fixed),candidate={...guardBonus,abilities:[]};
 const c=applyCardBlueprint(applyCardBlueprint(candidate,bp,{mergeEffects:false}),bp);
 assert.deepEqual(c.abilities,fixed.abilities);assert.deepEqual(c.damage_bonuses,guardBonus.damage_bonuses);
 assert.equal(compileCard(c,{}).definition.abilities.length,1);
 const next=applyCardBlueprint({...base('ignored'),abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]},blueprint(guardBonus));
 assert.deepEqual(next.damage_bonuses,guardBonus.damage_bonuses);
});
test('new branches are bounded, non-recursive and reject conflicting destinations',()=>{
 const bad=(c,f)=>{c=structuredClone(c);f(c);assert.throws(()=>compileCard(c,{}));};
 bad(cost,c=>c.abilities[0].effects[0].cost_delta=0);
 bad(cost,c=>c.abilities[0].effects[0].filter.faction_id='元素');
 bad(search,c=>c.abilities[0].effects[0].deck_position='top');
 bad(returner,c=>c.abilities[0].effects[0].destination='deck');
 bad(killHQ,c=>c.abilities[0].effects.shift());
 bad(killHQ,c=>c.abilities[0].effects[1].effects=[{op:'if_killed',per_unit:true,effects:[{op:'noop'}]}]);
 bad(classBonus,c=>c.abilities[0].effects[0].bonuses[0].amount=11);
 for(const c of [returner,classBonus,killHQ,cost,search]){
  const k={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.report843',version:1,name:'校验词条',description:'机制回归',aliases:[],parameters:{},implementation:{kind:'template',abilities:c.abilities}};
  assert.doesNotThrow(()=>validateKeyword(k));
 }
});
test('prompts expose current capabilities within provider budget',()=>{
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[],blueprint(guardBonus));assert(p.includes('modify_hand_cost'));assert(p.includes('deck_top'));assert(p.includes('per_unit'));assert(p.length<PROMPT_LIMIT);}
});


