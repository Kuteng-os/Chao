import {ruleCapabilities} from '../src/rule_capabilities.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileCard,validateCardBlueprint,applyCardBlueprint} from '../src/validation.js';
import {blueprint,readyCard,setTitle,titleText,titleLayout,titleError} from '../../web/model.mjs';
import {CentralMatches} from '../src/central_matches.js';
const spec=()=>({...JSON.parse(readFileSync(new URL('../../docs/cards/examples/valid_unit.json',import.meta.url),'utf8')),keywords:[]});
const measure=(text,size)=>Array.from(text).length*size;
test('visual title breaks preserve the canonical name and survive mechanics generation',()=>{
 const c=spec();setTitle(c,'第一装甲\n步兵团');
 assert.equal(c.name,'第一装甲步兵团');assert.equal(c.appearance.name_break,4);
 assert.equal(titleText(c),'第一装甲\n步兵团');
 const normalized=readyCard(c,[]),bp=validateCardBlueprint(blueprint(normalized),{});
 assert.equal(compileCard(normalized,{}).definition.appearance.name_break,4);
 const ai=spec();ai.name='模型不应改名';ai.abilities=[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}];
 const result=compileCard(applyCardBlueprint(ai,bp),{}).definition;
 assert.equal(result.name,c.name);assert.equal(result.appearance.name_break,4);assert.equal(result.abilities.length,1);
 const legacy=spec(),old=compileCard(legacy,{});assert.deepEqual({...old.definition.appearance},{emblem:legacy.unit_class});
 assert.equal(compileCard(legacy,{}).definition_hash,old.definition_hash);
});
test('bad line breaks fail, Unicode offsets count code points, and minimum-size warning requires an explicit split',()=>{
 for(const split of [0,-1,99,1.5]){const c=spec();c.appearance.name_break=split;assert.throws(()=>compileCard(c,{}));}
 const c=spec();setTitle(c,'装甲兵团\n远征支队');assert.equal(titleError(c,titleText(c),measure),'');
 assert(titleLayout(c,measure).size>=14);assert(titleLayout(c,measure,true).size>=9);
 setTitle(c,'装甲兵团远征支队');assert.match(titleError(c,titleText(c),measure),/换行/);
 assert.match(titleError(c,'甲\n乙\n丙',measure),/最多两行/);
 setTitle(c,'甲\n');assert.match(titleError(c,'甲\n',measure),/不能为空/);assert.throws(()=>compileCard(c,{}));
 setTitle(c,'甲😀\n乙');assert.equal(c.appearance.name_break,2);assert.equal(titleText(compileCard(c,{}).definition),'甲😀\n乙');
});
test('all decks enforce current battle mechanics client floor',async()=>{
 const central=Object.create(CentralMatches.prototype);central.store={listKeywords:async()=>[]};
 const c=spec();assert.equal(await central.requiresUpdate([{definition:c}]),ruleCapabilities.battle_rules.minimum_client_build);
 c.appearance.name_break=2;assert.equal(await central.requiresUpdate([{definition:c}]),ruleCapabilities.battle_rules.minimum_client_build);
});
