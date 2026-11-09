import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileCard} from '../src/validation.js';
import {latestCards} from '../src/derived_cards.js';
import {makePrompt} from '../src/provider.js';
const fixture=()=>JSON.parse(readFileSync(new URL('../../tests/kill837_card.json',import.meta.url),'utf8'));
test('74/75 clarified chain compiles and derived order keeps kill token closure',()=>{
 const c=compileCard(fixture(),{});
 const state={cards:{test:[{card_id:'test',revision:1,...c}]},keywords:{}};
 const cards=latestCards(state),order=cards.find(c=>c.definition.name==='倒灌');
 assert(order);assert.deepEqual(order.definition.tokens.map(t=>t.token_id),['jinye']);
 assert.match(order.rules_text,/若本次击杀/);assert.match(order.rules_text,/原位置为其控制者召唤【津液】/);
 assert.equal(compileCard(order.definition,{}).compiled_program_hash,order.compiled_program_hash);
 for(const kind of ['card','keyword','mechanism-review'])assert(makePrompt(kind,[]).includes('on_kill_summon'));
});
test('kill summon validates unit-only references and does not affect old damage',()=>{
 const c=fixture(),e=c.tokens[1].abilities[0].effects[0];e.on_kill_summon='missing';assert.throws(()=>compileCard(c,{}));
 e.on_kill_summon='daoguan';assert.throws(()=>compileCard(c,{}));
 e.on_kill_summon='jinye';c.tokens[1].play_target.include_hq=true;assert.throws(()=>compileCard(c,{}));
 delete c.tokens[1].play_target.include_hq;e.on_kill_summon='';assert.throws(()=>compileCard(c,{}));
});
