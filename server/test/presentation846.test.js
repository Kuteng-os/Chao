import test from 'node:test';
import assert from 'node:assert/strict';
import {isLatin,titleLayout,titleText} from '../../web/model.mjs';
import {cardFace} from '../../web/catalog.mjs';
import {ruleCapabilities} from '../src/rule_capabilities.js';

test('Latin titles wrap at word boundaries, preserving saved names and explicit breaks',()=>{
 const measure=(text,size)=>Array.from(text).reduce((n,ch)=>n+size*(ch===' '?0.3:0.53),0);
 const card={name:'The Final Expedition',appearance:{}};
 const result=titleLayout(card,measure);
 assert.equal(result.overflow,false);assert.equal(result.lines.join(' '),card.name);
 assert.equal(result.lines.length,2);assert.equal(titleText(card),card.name);
 assert(isLatin('Royal Air Force'));assert(!isLatin('R-401孵化场'));
 const explicit=titleLayout({name:'Royal Air Force',appearance:{name_break:6}},measure);
 assert.equal(explicit.lines[0],'Royal ');
 const cn=titleLayout({name:'这是很长很长的中文名称'},(s,fs)=>s.length*fs);
 assert(cn.overflow);assert.equal(cn.lines.length,1);
});

test('web card does not use Chinese character-count shrinking for Latin text',()=>{
 const html=cardFace({definition:{name:'Last Hatching',kind:'order',cost:2,appearance:{}},rules_text:'Discard a card. Draw two cards.'},[]);
 assert.match(html,/data-card-name="Last Hatching"/);assert.match(html,/data-latin="true"/);
 assert.doesNotMatch(html,/archive-rules long-rules/);
});

test('aircraft rule is advertised together with its compatible client gate',()=>{
 assert.equal(ruleCapabilities.revision,'mechanics-49');
 assert.equal(ruleCapabilities.battle_rules.minimum_client_build,906);
 assert.equal(ruleCapabilities.battle_rules.aircraft_move_attack_exclusive,true);
 assert.equal(ruleCapabilities.battle_rules.aircraft_move_attack_exception,'core.blitz');
});
