import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,schemas} from '../src/validation.js';
import {effectFieldValue,defaultEffect} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
const f=JSON.parse(readFileSync(new URL('../../tests/fixtures/repairs857.json',import.meta.url),'utf8'));
test('857 conditional zero combat damage compiles and remains distinct from immunity or preventing attacks',()=>{
 const c=compileCard(f,{});assert.match(c.rules_text,/不造成战斗伤害/);assert.doesNotMatch(c.rules_text,/0 倍|undefined|NaN/);
 writeFileSync(new URL('../../tests/fixtures/parity857.json',import.meta.url),JSON.stringify({definition_hash:c.definition_hash,compiled_program_hash:c.compiled_program_hash}));
 const k={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'test.duel',version:1,name:'以强克强',description:'与强敌交战时+2攻击，否则不造成战斗伤害',aliases:[],parameters:{},implementation:{kind:'template',abilities:structuredClone(f.abilities)}};
 assert.doesNotThrow(()=>validateKeyword(k));
 for(const n of [-1,0.5,5]){const bad=structuredClone(f);bad.abilities[0].effects[1].multiplier=n;assert.throws(()=>compileCard(bad,{}));}
 const schema=schemas.card.definitions.effect.oneOf.find(s=>s.properties.op.const==='set_combat_damage_multiplier');assert.equal(effectFieldValue(schema,'multiplier','0'),0);assert.equal(defaultEffect(schema).multiplier,1);
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[]);assert.match(p,/0\.\.4/);assert.match(p,/仅本单位不造成伤害已由玩家确认/);assert(Buffer.byteLength(p)<200000);}
});
