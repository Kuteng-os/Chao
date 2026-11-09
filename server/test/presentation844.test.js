import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {cardPresentation,compileCard} from '../src/validation.js';
import {shortText,boldText} from '../../web/card_text.mjs';
import {publicCard} from '../src/cloud_catalog.js';
const fixtures=JSON.parse(readFileSync(new URL('../../tests/text844-fixtures.json',import.meta.url)));
test('existing R cards get compact faces without changing frozen programs',()=>{
 for(const card of fixtures.cards){const c=compileCard(card.definition,fixtures.keywords);assert.equal(c.definition_hash,card.definition_hash);assert.equal(c.compiled_program_hash,card.compiled_program_hash);const p=publicCard(card,'',false,{keywords:fixtures.keywords});assert(!p.rules_text.includes('++'));assert(!p.rules_text.includes('X为1'));assert(!p.rules_text.includes('X为2'));}
 const rabbit=fixtures.cards.find(c=>c.card_id==='716ceade-4d40-4224-aa9c-c71c199ee92d');const p=publicCard(rabbit,'',false,{keywords:fixtures.keywords});assert(p.rules_text.length<40);assert(p.detailed_text.includes('最后的孵化'));assert(p.detailed_text.includes('词条说明'));assert(!p.rules_text.includes('仅继承'));
});
test('keyword explanations stay in detail; markup in names never becomes HTML',()=>{
 const c=structuredClone(fixtures.cards[0].definition);const k={id:'example.test',version:1,name:'团结<b>',description:'友方回合开始抽1张牌。',implementation:{kind:'template',abilities:[{trigger:'own_turn_start',effects:[{op:'draw',player:'owner',amount:1}]}]}};
 c.keywords=[{id:k.id,version:1,params:{}}];c.abilities=[];
 const p=cardPresentation(c,{[k.id+'@1']:{definition:k}});assert.equal(p.rules_text,'团结<b>');assert(p.detailed_text.includes(k.description));assert.equal(boldText(p.rules_text,p.keyword_names),'<strong>团结&lt;b&gt;</strong>');
});
test('shortening keeps turn limits, permanent duration, conditional results and separate lines',()=>{
 assert.equal(shortText('自身+1/+1（在场期间）\n阵亡：抽1张牌'),'自身+1/+1\n阵亡：抽1张牌');
 assert(shortText('若敌方单位更多，则永久+2/+2（本回合）').includes('若敌方单位更多'));assert(shortText('永久+2/+2（本回合）').includes('永久'));assert(shortText('永久+2/+2（本回合）').includes('本回合'));
 assert.equal(shortText('【主动行动完成后：】行动后：自身行动费+2；自身+1/+1'),'【主动行动完成后：】行动后：+1/+1，行动费+2');
});
