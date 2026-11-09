import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateKeyword} from '../src/validation.js';
import {freshCard,changeKind,editorError} from '../../web/model.mjs';
const base=(name,kind='order')=>({...changeKind(freshCard(),kind),name});
const draw=(kind,amount=1)=>({op:'draw',player:'owner',amount,filter:{kind}});
const parity={...base('偶数过牌'),cost:5,abilities:[{trigger:'on_play',effects:[draw('unit'),draw('order'),{op:'if_drawn',parity:'even',match:'any',effects:[{op:'gain_hq_defense',player:'owner',amount:5}]}]}]};
const previous={...base('连续指令'),cost:5,abilities:[{trigger:'on_play',effects:[draw('order',2)]},{trigger:'on_play',premise:{test:'previous_card',player:'owner',kind:'order'},effects:[{op:'gain_kredits',amount:2}]}]};
const delayed={...base('延迟抽牌'),cost:4,abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:2}]},{trigger:'next_own_turn_start',after_turns:2,effects:[{op:'draw',player:'owner',amount:1}]}]};
const sword={...base('剑士','unit'),abilities:[{trigger:'while_active',effects:[{op:'modify_stats',target:'self',attack_delta:{equipment_faction:'408c3c32-19c5-49ce-9a9d-055c38d516ba',scale:2},health_delta:0,duration:'battle'}]}]};
const fixtures=[parity,previous,delayed,sword].map(c=>compileCard(c,{}));
writeFileSync(new URL('../../tests/latest841.json',import.meta.url),JSON.stringify({cards:fixtures}));
test('82-88 compile and show typed draws, parity, history, delay, faction equipment',()=>{
 for(const c of [parity,previous,delayed,sword]){assert.equal(editorError(c),'');assert(!compileCard(c,{}).rules_text.includes('[object'))}
 for(const [i,re] of [[0,/抽1张单位牌.*抽1张指令牌.*偶数/s],[1,/上一张.*指令/],[2,/第2个后续回合/],[3,/指定阵营装备/]])assert.match(fixtures[i].rules_text,re);
 const k={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.draw',version:1,name:'偶数抽取',description:'抽到偶数费用触发',aliases:[],parameters:{},implementation:{kind:'template',abilities:parity.abilities}};assert(validateKeyword(k));
});
test('reject nested draw branches, malformed delays and faction formulas',()=>{
 const c=structuredClone(parity);c.abilities[0].effects[2].effects=[c.abilities[0].effects[2]];assert.throws(()=>compileCard(c,{}));
 for(const after_turns of [0,7,1.5]){const c=structuredClone(delayed);c.abilities[1].after_turns=after_turns;assert.throws(()=>compileCard(c,{}));}
 const c2=structuredClone(delayed);c2.abilities[0].after_turns=2;assert.throws(()=>compileCard(c2,{}),/回合/);
 const c3=structuredClone(sword);c3.abilities[0].effects[0].attack_delta.equipment_faction='剑';assert.throws(()=>compileCard(c3,{}));
});
