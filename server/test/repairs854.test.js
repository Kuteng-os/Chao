import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {compileCard,validateCardBlueprint,applyCardBlueprint,validateKeyword,builtinDefinitions,docsURL} from '../src/validation.js';
import {consumeReview,createReview} from '../src/mechanism_reviews.js';
import {blueprint} from '../../web/model.mjs';
import {DeepSeekProvider} from '../src/provider.js';
const f=JSON.parse(readFileSync(new URL('../../tests/fixtures/repairs854.json',import.meta.url)));
const definitions=[...builtinDefinitions,...['core_blitz','core_guard'].map(n=>JSON.parse(readFileSync(new URL('examples/keywords/'+n+'.json',docsURL))))];
const registry=Object.fromEntries(definitions.map(d=>[d.id+'@'+d.version,{...validateKeyword(d,{allowBuiltin:true}),registry_status:'approved'}]));
test('854 reported cards compile and preserve blueprint fields',()=>{
 const hashes={};for(const [key,card] of Object.entries(f)){
  let c;try {c=compileCard(card,registry);}catch(e){throw new Error(key+': '+e.message,{cause:e});}
  hashes[key]={definition_hash:c.definition_hash,compiled_program_hash:c.compiled_program_hash};assert.doesNotMatch(c.rules_text,/undefined|NaN/);
  const bp=validateCardBlueprint(blueprint(card),registry);assert.deepEqual(applyCardBlueprint(card,bp).cost_surcharge,card.cost_surcharge);
 }
 writeFileSync(new URL('../../tests/fixtures/parity854.json',import.meta.url),JSON.stringify(hashes));
});
test('new operations reject invalid timing, targets and missing forms',()=>{
 for(const [key,change] of [['counter',c=>c.counter_trigger='enemy_order_played'],['aura',c=>c.abilities[0].premise={test:'compare',left:{stat:'enemy_unit_count'},cmp:'gt',right:0}],['liberate',c=>c.abilities[0].effects[0].token_id='absent'],['field',c=>c.abilities[1].trigger='on_play'],['cost',c=>c.cost_surcharge[0].premise={test:'unit_state',target:'self',state:'has_attacked'}]]){
  const c=structuredClone(f[key]);change(c);assert.throws(()=>compileCard(c,registry),key);
 }
});
function reviewState(compilation='failed',child=null){
 const job={generation_id:'r',kind:'mechanism-review',owner_id:'p',target_kind:'card',status:'confirmed',compilation_id:'g',source_text:'抽牌',card_blueprint:blueprint(f.cost),result:{formal_text:'抽1张牌',result_hash:'hash',questions:[],missing_capabilities:[]},history:[],round:1};
 if(child)job.child_generation_id='child';
 return {generations:{r:job,g:{status:compilation,error:{message:'输出截断'}},...(child?{child:{status:child}}:{})}};
}
test('failed compilation can retry exact confirmation, but active/newer drafts stay locked',()=>{
 const state=reviewState();const body={source_text:'抽1张牌',mechanism_review:{generation_id:'r',result_hash:'hash'}};
 assert.ok(consumeReview(state,'p',body,'card',state.generations.r.card_blueprint));
 for(const status of ['running','queued','ready']){const s=reviewState(status);assert.throws(()=>consumeReview(s,'p',body,'card',s.generations.r.card_blueprint));}
 const s=reviewState();assert.throws(()=>consumeReview(s,'p',{...body,source_text:'抽2张'},'card',s.generations.r.card_blueprint));
});
test('failed child review does not permanently block corrections',async()=>{
 for(const child of ['failed','canceled','running','awaiting_confirmation']){
  const state=reviewState('failed',child),service={idem:async(_owner,_kind,_body,fn)=>fn(state),rate(){},schedule(){}};
  const body={kind:'card',parent_generation_id:'r',review_hash:'hash',feedback:'请继续修正'};
  if(['failed','canceled'].includes(child))assert.ok((await createReview(service,'p',body)).generation_id);
  else await assert.rejects(()=>createReview(service,'p',body));
 }
});
test('truncated thinking response gets one larger bounded retry without exposing reasoning',async()=>{
 const budgets=[];let attempts=0;
 const provider=new DeepSeekProvider({apiKey:'fixture',fetch:async(_url,options)=>{
  const body=JSON.parse(options.body);budgets.push(body.max_tokens);assert.equal(body.reasoning_effort,'high');
  const final={status:'review',formal_text:'撤退后解放为4/4、行动费0并获得闪击。',questions:[],missing_capabilities:[]};
  return new Response(JSON.stringify({choices:[{finish_reason:budgets.length===1?'length':'stop',message:{reasoning_content:'hidden fixture',content:budgets.length===1?'':JSON.stringify(final)}}]}));
 }});
 const result=await provider.generate({kind:'mechanism-review',catalog:[],context:{source_text:'撤退后解放'},signal:new AbortController().signal,onAttempt:async()=>{attempts++;}});
 assert.equal(attempts,2);assert.deepEqual(budgets,[16384,32768]);assert.doesNotMatch(JSON.stringify(result),/hidden fixture/);
});
