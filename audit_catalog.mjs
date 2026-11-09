import {readFileSync} from 'node:fs';
import {compileCard,validateKeyword} from './server/src/validation.js';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
let count=0;
for(const entry of Object.values(state.keywords)){const checked=validateKeyword(entry.definition,{allowBuiltin:true});if(checked.definition_hash!==entry.definition_hash)throw Error('Keyword hash drift');}
for(const versions of Object.values(state.cards))for(const card of versions){const checked=compileCard(card.definition,state.keywords);if(checked.definition_hash!==card.definition_hash||checked.compiled_program_hash!==card.compiled_program_hash)throw Error('Card hash drift');count++;}
console.log(JSON.stringify({cards:count,keywords:Object.keys(state.keywords).length,hashes_unchanged:true}));
