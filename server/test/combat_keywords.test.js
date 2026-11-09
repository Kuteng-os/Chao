import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Store} from '../src/store.js';
import {builtinDefinitions,compileCard,validateKeyword,docsURL,schemas} from '../src/validation.js';
import {hash} from '../src/codec.js';
import {ruleCapabilities} from '../src/rule_capabilities.js';
const card=()=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name:'基础词条',flavor_text:'',kind:'unit',unit_class:'tank',cost:1,operation_cost:1,attack:2,health:4,keywords:[],play_target:null,abilities:[],tokens:[],appearance:{emblem:'tank'}});

test('builtin migration preserves old definitions and catalogs, compiles all added exact versions',async t=>{
 const directory=await mkdtemp(join(tmpdir(),'frontline-builtins-'));let store=new Store(directory);await store.init();t.after(async()=>{await store.close();await rm(directory,{recursive:true,force:true});});
 for(const name of ['core_blitz','core_guard']){
  const original=JSON.parse(await readFile(new URL(`examples/keywords/${name}.json`,docsURL),'utf8'));
  assert.equal(store.state.keywords[`${original.id}@1`].definition_hash,hash(original));
 }
 const before=structuredClone(store.state.keywords),catalogs=structuredClone(store.state.catalogs);
 const outputs=[];
 for(const d of builtinDefinitions){
  const c=card();c.keywords=[{id:d.id,version:d.version,params:{}}];
  const result=compileCard(c,store.state.keywords);outputs.push(result);
  assert.match(result.rules_text,new RegExp(d.name));
  assert.equal(result.keyword_bindings[0].definition_hash,hash(d));
  assert.throws(()=>validateKeyword(d),e=>e.code==='UNSUPPORTED_EFFECT');
  const wrong=structuredClone(c);wrong.keywords[0].version=99;assert.throws(()=>compileCard(wrong,store.state.keywords));
 }
 await store.close();store=new Store(directory);await store.init();
 assert.deepEqual(store.state.keywords,before);assert.deepEqual(store.state.catalogs,catalogs);
 for(const c of outputs)assert.equal(compileCard(c.definition,store.state.keywords).compiled_program_hash,c.compiled_program_hash);
});

test('shared operations compile with strict bounds and allow template parameterization',()=>{
 for(const effect of [{op:'intel',amount:9},{op:'pin',target:'random_enemy_unit',turns:3},{op:'gain_hq_defense',player:'owner',amount:10},{op:'modify_kredit_slots',player:'opponent',amount:-3},...['suppress','repair','retreat','return_to_hand','remove','reset_operations','fight'].map(op=>({op,target:'random_enemy_unit'}))]){
  const c=card();c.abilities=[{trigger:'on_play',effects:[effect]}];assert(compileCard(c,{}).rules_text.length);
  assert(ruleCapabilities.operations.includes(effect.op));assert(ruleCapabilities.template_operations.includes(effect.op));
  const field=['amount','turns'].find(k=>Object.hasOwn(effect,k));
  if(field){
   const keyword={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.boundary',version:1,name:'边界参数',aliases:[],description:'测试',parameters:{n:{type:'integer',minimum:effect[field],maximum:effect[field]}},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{...effect,[field]:{param:'n'}}]}]}};
   assert(validateKeyword(keyword));
   keyword.parameters.n.maximum=20;assert.throws(()=>validateKeyword(keyword));
  }
 }
 const c=card();c.abilities=[{trigger:'on_play',effects:[{op:'modify_kredit_slots',player:'owner',amount:0}]}];assert.throws(()=>compileCard(c,{}));
 c.abilities=[{trigger:'on_death',effects:[{op:'fight',target:'random_enemy_unit'}]}];assert.throws(()=>compileCard(c,{}));
 for(const op of ['intel','pin'])assert(!schemas.card.definitions.effect.oneOf.find(x=>x.properties.op.const===op).additionalProperties);
});
