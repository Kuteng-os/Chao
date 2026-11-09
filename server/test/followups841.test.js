import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,validateCardBlueprint} from '../src/validation.js';
import {freshCard,changeKind,blueprint,numericError,editorError} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
import {markResolved,resumeContext,inbox} from '../src/diagnostics.js';
const blank=(name,kind='unit')=>({...changeKind(freshCard(),kind),name});
const noop={...blank('空白指令','order'),cost:3,abilities:[{trigger:'on_play',effects:[{op:'noop'}]}]};
const turn={...blank('回合阵亡'),abilities:[{trigger:'own_unit_died',premise:{test:'turn_owner',side:'owner'},effects:[{op:'draw',player:'owner',amount:1},{op:'gain_kredits',amount:1}]}]};
const gap={...blank('攻击差减伤'),attack:7,health:10,abilities:[{trigger:'on_play',effects:[{op:'modify_incoming_damage',target:'self',damage_kind:'combat',amount:{attack_gap:{step:2,reduction:1}},duration:'battle'}]}]};
const copy={...blank('指定强化继承'),abilities:[{trigger:'on_death',effects:[{op:'transfer_card',source:'self',mode:'copy',destination:'deck',selection:'random',amount:1,inherit_from:[{card_id:'06c0ce91-5cf3-4ff9-97ff-d2f1fe341371',name:'最后的孵化'}]}]}]};
const fixtures=[noop,turn,gap,copy].map(c=>compileCard(c,{}));
writeFileSync(new URL('../../tests/fixtures841.json',import.meta.url),JSON.stringify({cards:fixtures}));
test('841 shared contract, blueprint and concise rules',()=>{
 for(const c of [noop,turn,gap,copy]){assert.equal(editorError(c),'');validateCardBlueprint(blueprint(c),{});assert(!compileCard(c,{}).rules_text.includes('[object Object]'));}
 assert.match(fixtures[0].rules_text,/无额外效果/);assert.match(fixtures[1].rules_text,/己方回合/);assert.match(fixtures[2].rules_text,/每高出.*2.*1/);assert.match(fixtures[3].rules_text,/仅继承【最后的孵化】/);
 for(const kind of ['card','keyword','mechanism-review'])for(const text of ['attack_gap','turn_owner','noop','inherit_from','core.untargetable'])assert(makePrompt(kind,[]).includes(text));
 const k={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.gap',version:1,name:'差额护甲',description:'攻击力差减伤',aliases:[],parameters:{},implementation:{kind:'template',abilities:gap.abilities}};assert(validateKeyword(k));
});
test('841 contracts reject malformed formulas, branches and source filters',()=>{
 for(const amount of [{attack_gap:{step:0,reduction:1}},{attack_gap:{step:2.5,reduction:1}},{attack_gap:{step:2,reduction:11}},{attack_gap:{step:2,reduction:1,code:'run'}}]){const c=structuredClone(gap);c.abilities[0].effects[0].amount=amount;assert.throws(()=>compileCard(c,{}));}
 for(const premise of [{test:'turn_owner',side:'enemy'},{test:'turn_owner',side:'owner',extra:true}])assert.throws(()=>compileCard({...turn,abilities:[{...turn.abilities[0],premise}]},{}));
 const c=structuredClone(copy);c.abilities[0].effects[0].inherit_from.push(c.abilities[0].effects[0].inherit_from[0]);assert.throws(()=>compileCard(c,{}),/不能重复/);
 c.abilities[0].effects[0].inherit_from=[];assert.match(compileCard(c,{}).rules_text,/不继承强化/);
 c.abilities[0].effects[0].mode='move';assert.throws(()=>compileCard(c,{}),/仅用于复制/);
 assert.throws(()=>compileCard({...noop,abilities:[{trigger:'on_play',effects:[{op:'noop',amount:0}]}]},{}));
});
test('71/72 numeric errors precede generation and preserve entered values',()=>{
 const h=blank('总部','hq');h.health=101;assert.match(numericError(h),/防御.*1.*100/);assert.equal(h.health,101);assert.throws(()=>validateCardBlueprint(blueprint(h),{}),/100/);
 h.health=100;assert.equal(numericError(h),'');validateCardBlueprint(blueprint(h),{});
 const u=blank('单位');u.health=21;assert.match(editorError(u),/1.*20/);u.health=1.5;assert.match(numericError(u),/整数/);
});
test('resolved reports notify author once and preserve latest answers',()=>{
 const r={id:'r',number:'CZ-000079',count:1,status:'open',owner_id:'a',generation_id:'old',first_seen:'2026-09-27'};
 const old={owner_id:'a',conversation_id:'c',round:1,kind:'mechanism-review',card_blueprint:turn,source_text:'原需求',history:[]};
 const latest={...old,round:2,status:'canceled',history:[{answer:'不包括自身死亡'}]};
 const s={diagnostics:{r},generations:{old,latest}};markResolved(s,r,{resolution:'已支持回合归属条件，原答案保留。',version:'0.8.41'});markResolved(s,r,{});
 assert.equal(inbox(s,'a').items.length,1);assert.deepEqual(resumeContext(s,'a','CZ-000079').history,latest.history);assert.equal(inbox(s,'b').items.length,0);
});
