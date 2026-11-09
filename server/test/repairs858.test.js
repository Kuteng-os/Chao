import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {compileCard,validateKeyword} from '../src/validation.js';
import {makePrompt} from '../src/provider.js';
const f=JSON.parse(readFileSync(new URL('../../tests/fixtures/repairs858.json',import.meta.url),'utf8'));
const child=()=>({...structuredClone(f),name:'峥嵘岁月',cost:3,tokens:[],abilities:structuredClone(f.tokens[0].abilities)});
const kw=c=>({schema_version:'1.0.0',ruleset_version:'frontline-1',id:'test.youth',version:1,name:'岁月',description:'部署坦克强化；检索忧郁坦克',aliases:[],parameters:{},implementation:{kind:'template',abilities:structuredClone(c.abilities)}});
test('858 derived order supports ordered filtered copies and permanent global deployment listeners',()=>{
 const c=compileCard(f,{}),d=compileCard(child(),{});assert.match(d.rules_text,/忧郁/);assert.match(d.rules_text,/坦克/);assert.match(d.rules_text,/弃牌区.*手牌/);assert.doesNotMatch(d.rules_text,/undefined|NaN/);
 assert.doesNotThrow(()=>validateKeyword(kw(child())));
 writeFileSync(new URL('../../tests/fixtures/parity858.json',import.meta.url),JSON.stringify({parent:c.compiled_program_hash,child:d.compiled_program_hash}));
 for(const sin of ['wrath','lust','sloth','gluttony','gloom','pride','envy',null]){const x=child();x.abilities[0].effects[1].filter.sin=sin;assert.doesNotThrow(()=>compileCard(x,{}));}
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[]);assert.match(p,/fallback_sources/);assert.match(p,/罪孽筛选、按区域回退复制/);assert(Buffer.byteLength(p)<200000);}
});
test('858 copy fallback rejects ambiguous and unsupported source combinations in cards and keyword templates',()=>{
 for(const patch of [{fallback_sources:[]},{fallback_sources:['discard','discard']},{fallback_sources:['deck']},{fallback_sources:['discard','hand','deck']},{fallback_sources:['self']},{fallback_sources:['starting_deck']},{mode:'move'},{destination:'deck'},{source:'self'},{filter:{sin:'melancholy'}}]){
  const x=child();Object.assign(x.abilities[0].effects[1],patch);assert.throws(()=>compileCard(x,{}),JSON.stringify(patch));assert.throws(()=>validateKeyword(kw(x)),JSON.stringify(patch));
 }
});
test('858 trigger unit is validated in the nearest scheduled event scope',()=>{
 const x=child(),effect=x.abilities[0].effects[0].effects[0];x.abilities[0].effects=[effect];assert.throws(()=>compileCard(x,{}));assert.throws(()=>validateKeyword(kw(x)));
 for(const trigger of ['next_own_turn_start','next_own_order_played']){const y=child();y.abilities[0].effects[0].trigger=trigger;y.abilities[0].effects[0].repeat=trigger==='next_own_turn_start'?'each_turn':'each_event';assert.throws(()=>compileCard(y,{}));assert.throws(()=>validateKeyword(kw(y)));}
 const nested=child();nested.abilities[0].effects[0].effects=[{op:'schedule',trigger:'next_own_turn_start',effects:[effect]}];assert.throws(()=>compileCard(nested,{}));
 const counter=child();counter.kind='counter';counter.counter_trigger='enemy_unit_attacked';counter.abilities[0].trigger='on_reveal';counter.abilities[0].effects=[{op:'schedule',trigger:'next_own_unit_deployed',effects:[{op:'cancel_action'}]}];assert.throws(()=>compileCard(counter,{}));
});
