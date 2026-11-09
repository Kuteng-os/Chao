import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard,rulesText} from '../src/validation.js';
import {latestCards} from '../src/derived_cards.js';
import {makePrompt} from '../src/provider.js';
import {freshCard} from '../../web/model.mjs';

const base=(name='测试',kind='order')=>({...freshCard(),name,kind,unit_class:kind==='unit'?'tank':null,attack:kind==='unit'?3:0,health:kind==='unit'?4:0,operation_cost:kind==='unit'?1:0,appearance:{emblem:kind==='unit'?'tank':kind}});
const token=(id)=>{const d=base(id);for(const k of ['schema_version','ruleset_version','tokens','appearance'])delete d[k];return {...d,token_id:id,abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]};};
const hatching=()=>({...base('最后的孵化'),abilities:[{trigger:'on_play',effects:[{op:'discard',player:'owner',amount:1,selection:'chosen',filter:{kind:'unit',name_contains:'集团军'}},{op:'modify_cards',player:'owner',zones:['battlefield','hand','deck'],filter:{same_as_discarded:true},attack_delta:2,health_delta:2,operation_cost_delta:-1,duration:'match',grant_abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]}]}]});

test('chosen discard, same-name cross-zone buff and gifted deployment effect validate',()=>{
 const c=compileCard(hatching(),{});assert.match(c.rules_text,/使用时/);assert.match(c.rules_text,/集团军/);assert.match(c.rules_text,/部署时.*抽/);assert.match(c.rules_text,/永久/);
 const original=structuredClone(c.definition);rulesText(c.definition);assert.deepEqual(JSON.parse(JSON.stringify(c.definition)),original);
 const bad=hatching();bad.abilities[0].effects.shift();assert.throws(()=>compileCard(bad,{}),/先弃置/);
 for(const mutate of [d=>d.abilities[0].effects[0].filter.name_contains=' ',d=>d.abilities[0].effects[1].zones=['discard'],d=>d.abilities[0].effects[1].grant_abilities[0].effects=[{op:'damage',target:'chosen',amount:1}],d=>d.abilities[0].effects[1].grant_abilities[0].trigger='on_reveal',d=>d.abilities[0].effects[1].grant_abilities[0].effects=[{op:'modify_cards'}]]){const d=hatching();mutate(d);assert.throws(()=>compileCard(d,{}));}
});

test('three research stages materialize valid versioned derived cards and keep references',()=>{
 const d=base('分阶段研发');d.tokens=['reward_a','reward_b','reward_c','reward_d','stage_2','stage_3'].map(token);
 d.abilities=[{trigger:'on_play',effects:[{op:'research',token_ids:['reward_a','stage_2']}]}];
 d.tokens[4].abilities[0].effects=[{op:'research',token_ids:['reward_b','stage_3']}];d.tokens[5].abilities[0].effects=[{op:'research',token_ids:['reward_c','reward_d']}];
 const c=compileCard(d,{}),id='11111111-1111-4111-8111-111111111111',state={keywords:{},cards:{[id]:[{card_id:id,revision:1,...c,owner_id:'test'}]}};
 const all=latestCards(state);assert.equal(all.length,7);
 for(const r of all)assert.equal(compileCard(r.definition,{}).compiled_program_hash,r.compiled_program_hash);
 assert.equal(all.find(r=>r.definition.name==='stage_2').definition.deck_building,'generated_only');
 assert.equal(all.find(r=>r.definition.name==='stage_2').definition.tokens.length,4);
 const unknown=structuredClone(d);unknown.abilities[0].effects[0].token_ids[0]='missing';assert.throws(()=>compileCard(unknown,{}),/不存在/);
 const repeated=structuredClone(d);repeated.abilities[0].effects[0].token_ids=['reward_a','reward_a'];assert.throws(()=>compileCard(repeated,{}));
});

test('develop supports bounded token pool and frozen starting deck without ambiguous source fields',()=>{
 const d=base('开发');d.tokens=['a','b','c','d'].map(token);d.abilities=[{trigger:'on_play',effects:[{op:'develop',source:'tokens',token_ids:['a','b','c','d']}]}];assert.match(compileCard(d,{}).rules_text,/最多3/);
 d.tokens=[];d.abilities[0].effects=[{op:'develop',source:'starting_deck',filter:{kind:'unit',unit_class:'tank'}}];assert.match(compileCard(d,{}).rules_text,/起始牌组/);
 d.abilities[0].effects[0].token_ids=['a'];assert.throws(()=>compileCard(d,{}));
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[]);assert.match(p,/modify_cards/);assert.match(p,/由被弃牌的手牌持有者选择/);assert.match(p,/指令“使用时”/);assert.ok(Buffer.byteLength(p)<200000);}
});
