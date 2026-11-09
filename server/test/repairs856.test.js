import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,builtinDefinitions} from '../src/validation.js';
const registry=Object.fromEntries(builtinDefinitions.map(d=>[d.id+'@'+d.version,{...validateKeyword(d,{allowBuiltin:true}),registry_status:'approved'}]));
const f=JSON.parse(readFileSync(new URL('../../tests/fixtures/repairs856.json',import.meta.url),'utf8'));
test('856 received damage and precise next-turn lifetimes compile with stable text',()=>{
 const hashes={};for(const [key,def] of Object.entries(f)){const c=compileCard(def,registry);hashes[key]={definition_hash:c.definition_hash,compiled_program_hash:c.compiled_program_hash};assert.doesNotMatch(c.rules_text,/undefined|NaN/);assert.match(c.rules_text,/直到下个/);}
 writeFileSync(new URL('../../tests/fixtures/parity856.json',import.meta.url),JSON.stringify(hashes));
 assert.match(compileCard(f.tank,registry).rules_text,/坦克.*×2/);
 const kw={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'test.incoming',version:1,name:'易伤',aliases:[],description:'受到伤害翻倍',parameters:{},implementation:{kind:'template',abilities:structuredClone(f.tank.abilities)}};
 assert.doesNotThrow(()=>validateKeyword(kw));
});
test('856 rejects malformed multipliers and source filters without relaxing old constraints',()=>{
 for(const edit of [e=>e.multiplier=1,e=>e.multiplier=0.5,e=>e.multiplier=11,e=>delete e.amount,e=>delete e.multiplier,e=>e.source_unit_classes=[],e=>e.source_unit_classes=['tank','tank'],e=>e.source_unit_classes=['unknown'],e=>e.duration='forever']){
  const c=structuredClone(f.tank);edit(c.abilities[0].effects[1]);assert.throws(()=>compileCard(c,registry));
 }
 const c=structuredClone(f.combat);c.abilities[0].effects[1].source_unit_classes=['fighter','bomber'];assert.doesNotThrow(()=>compileCard(c,registry));
});
