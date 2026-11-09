import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {shortText} from '../../web/card_text.mjs';
import {compileCard,cardPresentation} from '../src/validation.js';
import {makePrompt} from '../src/provider.js';
const cases=JSON.parse(readFileSync(new URL('../../tests/text845-cases.json',import.meta.url)));
test('card-face qualifiers use concise text while lifetimes, numbers and literal names survive',()=>{
 for(const [input,expected] of cases)assert.equal(shortText(input),expected);
 const extra=cases[0][0].replace(/。$/u,'；敌方总部受到的伤害+2。');
 assert(!shortText(extra).includes('选中该目标'),'different lifetimes must not become one turn-scoped sentence');
 const fixtures=JSON.parse(readFileSync(new URL('../../tests/text844-fixtures.json',import.meta.url)));
 for(const c of fixtures.cards){const compiled=compileCard(c.definition,fixtures.keywords),p=cardPresentation(c.definition,fixtures.keywords,compiled.compiled_program.expanded_definition);assert.equal(compiled.compiled_program_hash,c.compiled_program_hash);if(c.definition.name==='战术集火'){assert(!p.rules_text.includes('不含本指令'));assert(p.detailed_text.includes('不含本指令'));}}
});
test('R Company language policy reaches reviews, keywords, cards and append-mode prompts',()=>{
 for(const [kind,blueprint]of[['mechanism-review',null],['keyword',null],['card',null],['card',{effect_mode:'append'}]]){
  const p=makePrompt(kind,[],blueprint);assert(p.includes('r-company-1'));assert(p.includes('永久+2/+2'));assert(p.includes('不在 JSON 文案中加入 Markdown'));assert(p.includes('不堆叠“（本回合）”'));assert(!p.includes('部署：自身重甲+2（在场期间）'));
 }
});
