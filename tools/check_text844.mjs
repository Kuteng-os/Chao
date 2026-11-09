import {readFileSync} from 'node:fs';
import {cardPresentation,compileCard} from '../server/src/validation.js';
const s=JSON.parse(readFileSync(new URL('../tests/text844-fixtures.json',import.meta.url)));
for(const c of s.cards){const result=compileCard(c.definition,s.keywords);if(result.definition_hash!==c.definition_hash||result.compiled_program_hash!==c.compiled_program_hash)throw Error('Hash changed');const p=cardPresentation(c.definition,s.keywords,c.compiled_program?.expanded_definition??c.definition);console.log(c.definition.name+'\n'+p.rules_text+'\n');}
