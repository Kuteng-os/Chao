import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,schemas,validateCardBlueprint,rulesText} from '../src/validation.js';
import {effectFieldValue,readyCard,blueprint} from '../../web/model.mjs';
const f=JSON.parse(readFileSync(new URL('../../tests/fixtures/repairs851.json',import.meta.url)));
test('851 reported mechanisms pass the real compiler and text renderer',()=>{
 const hashes={};for(const [key,c] of Object.entries(f)){
  try{const a=compileCard(c,{});const text=a.rules_text;assert.ok(text,key);assert.doesNotMatch(text,/undefined|NaN/,key);hashes[key]={definition_hash:a.definition_hash,compiled_program_hash:a.compiled_program_hash};}
  catch(e){throw new Error(key+': '+e.message,{cause:e});}
 }
 writeFileSync(new URL('../../tests/fixtures/parity851.json',import.meta.url),JSON.stringify(hashes));
});
test('form numeric fields and unselected optional inputs stay typed',()=>{
 const schedule=schemas.card.definitions.effect.oneOf.find(s=>s.properties.op.const==='schedule');
 assert.equal(effectFieldValue(schedule,'after_turns','3'),3);assert.equal(effectFieldValue(schedule,'times','2'),2);
 assert.equal(effectFieldValue(schedule,'times',''),undefined);assert.throws(()=>effectFieldValue(schedule,'times','1.5'));
 assert.equal(readyCard(f.choice,[]).play_target,null);
 assert.doesNotThrow(()=>validateCardBlueprint(blueprint(f.choice),{}));
});
test('token parameters bind per card and cannot become arbitrary fields',()=>{
 const k={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'test.evolution',version:1,name:'玉化',description:'入场三回合后进化',aliases:[],parameters:{form:{type:'token'}},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{op:'schedule',trigger:'next_own_turn_start',after_turns:3,lifetime:'source',effects:[{op:'transform',target:'self',token_id:{param:'form'},inherit:'none'}]}]}]}};
 const registry={'test.evolution@1':{...validateKeyword(k),registry_status:'approved'}};
 const c=structuredClone(f.evolve);c.abilities=[];c.keywords=[{id:k.id,version:1,params:{form:'form'}}];
 assert.doesNotThrow(()=>compileCard(c,registry));c.keywords[0].params.form='missing';assert.throws(()=>compileCard(c,registry),/不存在的衍生/);
 c.keywords[0].params.form=1;assert.throws(()=>compileCard(c,registry));
 writeFileSync(new URL('../../tests/fixtures/token851.json',import.meta.url),JSON.stringify({keyword:k,card:{...c,keywords:[{id:k.id,version:1,params:{form:'form'}}]}}));
});
test('new primitives retain limits and reject invalid sources',()=>{
 for(const [key,change] of [['eight',c=>c.abilities.push(c.abilities[0])],['suspend',c=>c.abilities[0].effects[0].return_when='source_leaves'],['max_only',c=>c.abilities[0].effects[0].health_delta=0],['return_drawn',c=>c.abilities[0].effects[1].effects[0].mode='copy'],['capped',c=>c.abilities[0].effects[1].max_amount=-1]]){
  const c=structuredClone(f[key]);change(c);assert.throws(()=>compileCard(c,{}),key);
 }
});
