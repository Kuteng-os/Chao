import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {compileCard,validateKeyword,validateCardBlueprint} from '../src/validation.js';
import {registerComponents,expandComponents,componentCatalog} from '../src/mechanism_components.js';
import {recordDiagnostic,diagnosticList} from '../src/diagnostics.js';
import {createApp} from '../src/index.js';
import {DeepSeekProvider,makePrompt} from '../src/provider.js';
import {FACTION_ID,seedFactions} from './faction_fixture.js';
const premise={test:'compare',left:{stat:'enemy_unit_count'},cmp:'gt',right:{stat:'friendly_unit_count'}};
const card=()=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name:'以寡敌众',faction_id:FACTION_ID,flavor_text:'',kind:'order',unit_class:null,cost:1,operation_cost:0,attack:0,health:0,keywords:[],play_target:null,tokens:[],abilities:[{trigger:'on_play',premise:structuredClone(premise),effects:[{op:'draw',player:'owner',amount:2}]}],appearance:{emblem:'order'}});
test('conditional groups compile, preserve hashes and reject unsupported or unbounded expressions',()=>{
 const c=card();const result=compileCard(c,{});assert.match(result.rules_text,/若敌方在场单位更多/);
 for(const cmp of ['gt','gte','eq','ne','lt','lte']){c.abilities[0].premise.cmp=cmp;assert(compileCard(c,{}));}
 c.abilities[0].premise={test:'all',items:[premise,{test:'not',item:{test:'any',items:[premise]}}]};assert(compileCard(c,{}));
 c.abilities[0].premise={test:'not',item:c.abilities[0].premise};assert.throws(()=>compileCard(c,{}),/条件/);
 for(const bad of [{...premise,script:'x'}, {...premise,left:{stat:'eval'}}, {...premise,cmp:'javascript'}, {...premise,left:1.5}]){c.abilities[0].premise=bad;assert.throws(()=>compileCard(c,{}));}
 const kw={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.conditional',version:1,name:'以寡敌众',description:'敌方单位多于己方时抽两张。',aliases:[],parameters:{},implementation:{kind:'template',abilities:card().abilities}};assert(validateKeyword(kw));
});
test('confirmed card components deduplicate, references expand and source bodies stay frozen',()=>{
 const state={};const c=card();registerComponents(state,'author',c);const first=componentCatalog(state);assert.equal(first.length,2);
 const p=first.find(x=>x.kind==='premise'),r=first.find(x=>x.kind==='result');
 c.abilities[0].premise={test:'ref',id:p.id,version:1};c.abilities[0].effects=[{op:'use_component',id:r.id,version:1}];
 const expanded=expandComponents(c,state.mechanism_components);assert.deepEqual(expanded,card());assert(compileCard(expanded,{}));
 registerComponents(state,'other',expanded);assert.equal(componentCatalog(state).length,2);assert.equal(state.mechanism_components[p.id].uses,2);
 state.mechanism_components[p.id].body.cmp='lt';assert.equal(expanded.abilities[0].premise.cmp,'gt');assert.throws(()=>expandComponents(c,state.mechanism_components),/不存在/);
 c.abilities[0].premise.version=2;assert.throws(()=>expandComponents(c,{}));
});
test('diagnostics redact secrets, merge duplicates, restrict access and cap persisted entries',()=>{
 const state={};const event={stage:'card',code:'INVALID_MODEL_OUTPUT',message:'Bearer private-token sk-privateabc password=secret',source:'若敌方单位多，抽牌',owner:'u'};
 recordDiagnostic(state,event);recordDiagnostic(state,event);assert.equal(Object.values(state.diagnostics)[0].count,2);
 assert(!JSON.stringify(state.diagnostics).includes('privateabc'));assert(!JSON.stringify(state.diagnostics).includes('private-token'));assert.throws(()=>diagnosticList(state,'u'));
 for(let i=0;i<1005;i++)recordDiagnostic(state,{stage:'card',code:'FAIL',source:String(i)});assert.equal(Object.keys(state.diagnostics).length,1000);
});
test('DeepSeek reference output expands before schema validation and uses thinking mode',async()=>{
 const state={};registerComponents(state,'author',card());const components=componentCatalog(state);const c=card();c.abilities[0].premise={test:'ref',id:components.find(x=>x.kind==='premise').id,version:1};
 let request;const provider=new DeepSeekProvider({apiKey:'test-key',fetch:async(url,args)=>{request=JSON.parse(args.body);return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify({status:'ok',card:c,assumptions:[],explanation:'敌方单位较多则抽2张牌。'})}}]}));}});
 const output=await provider.generate({kind:'card',catalog:[],context:{source_text:'敌方单位多则抽2张牌',component_catalog:components},signal:new AbortController().signal,onAttempt:async()=>{}});
 assert.deepEqual(output.result.card.abilities[0].premise,premise);assert.equal(request.thinking.type,'enabled');assert.equal(request.reasoning_effort,'high');
 assert.match(makePrompt('mechanism-review',[]),/必须澄清奇数取整/);
});
test('failed compilation stays in the review conversation; confirmation alone cannot bypass validation',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'chao-premise-review-'));let reviews=0,compiles=0;
 const provider={configured:true,model:'test',async generate({kind,onAttempt}){await onAttempt();if(kind==='mechanism-review'){reviews++;return {result:{status:'review',formal_text:'打出指令时，若敌方在场单位数大于己方，则抽2张牌。',questions:reviews===1?[{id:'timing',question:'何时检查？',options:['打出时','回合开始']}]:[],missing_capabilities:[]},metadata:{}};}compiles++;const c=card();if(compiles===1)c.abilities[0].effects[0].amount=99;return {result:{status:'ok',card:c,assumptions:[],explanation:'抽2张牌'},metadata:{}};}};
 const app=await createApp({dataDir:dir,centralMode:true,matches:false,provider,inviteToken:'test-review-invite-long-enough'});t.after(async()=>{await app.close();await rm(dir,{recursive:true,force:true});});await seedFactions(app.service.store);app.service.minuteLimit=30;
 const user=await app.auth.register({display_name:'测试者',invite_code:'test-review-invite-long-enough'},'local');const owner=user.owner_id;
 const full=card();full.abilities=[];const {kind,unit_class,cost,operation_cost,attack,health,keywords,name,faction_id}=full;
 const blueprint={kind,unit_class,cost,operation_cost,attack,health,keywords,name,faction_id,abilities:[],tokens:[],play_target:null,effect_mode:'append'};
 const wait=async id=>{for(let i=0;i<100;i++){const j=app.service.job(owner,id);if(!['queued','running'].includes(j.status))return j;await new Promise(r=>setTimeout(r,5));}throw Error('timeout');};
 let job=await wait((await app.service.createReview(owner,{request_id:randomUUID(),kind:'card',source_text:'敌方单位较多就抽2张牌',card_blueprint:blueprint})).generation_id);
 assert.equal(job.result.questions.length,1);assert.equal(Object.keys(app.service.store.state.mechanism_components).length,0);
 const compile=()=>app.service.createGeneration(owner,{request_id:randomUUID(),editor_revision:1,source_text:job.result.formal_text,clarification_answers:[],schema_version:'1.0.0',ruleset_version:'frontline-1',card_blueprint:blueprint,mechanism_review:{generation_id:job.generation_id,result_hash:job.result.result_hash}});
 await assert.rejects(compile,/补充/);
 job=await wait((await app.service.createReview(owner,{request_id:randomUUID(),kind:'card',parent_generation_id:job.generation_id,review_hash:job.result.result_hash,answers:[{question_id:job.result.questions[0].id,answer:'打出时'}]})).generation_id);
 const failed=await wait((await compile()).generation_id);assert.equal(failed.status,'failed');assert(Object.values(app.service.store.state.diagnostics).some(x=>x.stage==='card'));
 job=await wait((await app.service.createReview(owner,{request_id:randomUUID(),kind:'card',parent_generation_id:job.generation_id,review_hash:job.result.result_hash,feedback:'请按抽2张修复'})).generation_id);
 assert.equal(job.history.length,2);assert(job.history[1].validation_error);
 const ready=await wait((await compile()).generation_id);assert.equal(ready.status,'ready');assert.equal(componentCatalog(app.service.store.state).length,0);
 await app.service.confirmCard(owner,{request_id:randomUUID(),draft_id:ready.result.draft_id,draft_hash:ready.result.draft_hash});assert.equal(componentCatalog(app.service.store.state).length,2);
});
