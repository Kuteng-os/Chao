import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {compileCard,validateKeyword,builtinDefinitions} from '../src/validation.js';
import {hash} from '../src/codec.js';
import {Store} from '../src/store.js';
import {makePrompt} from '../src/provider.js';
import {freshCard} from '../../web/model.mjs';
const armor=n=>JSON.parse(readFileSync(new URL(`../../docs/cards/examples/keywords/standard_heavy_armor${n===2?'_v2':''}.json`,import.meta.url),'utf8'));
const registry=Object.fromEntries([...builtinDefinitions,armor(1),armor(2)].map(d=>[`${d.id}@${d.version}`,{...validateKeyword(d,{allowBuiltin:true}),registry_status:'approved'}]));
const swap={op:'swap_stats',target:'chosen',duration:'battle'};
const base=(name='修复验收')=>({...freshCard(),name,attack:3,health:8,keywords:[],abilities:[]});
const fixtures={
 swap:{...base('攻防交换'),play_target:{side:'any',row:'any'},abilities:[{trigger:'on_play',effects:[swap]}]},
 armor:{...base('百层重甲'),keywords:[{id:'standard.heavy_armor',version:2,params:{x:100}}]},
 reduction:{...base('固定百点减伤'),abilities:[{trigger:'on_play',effects:[{op:'modify_incoming_damage',target:'self',amount:-100,damage_kind:'combat',duration:'battle'}]}]}
};
test('904 contracts, boundaries and native compiler parity fixtures',()=>{
 const hashes={};for(const [key,c] of Object.entries(fixtures))hashes[key]=compileCard(c,registry).compiled_program_hash;
 writeFileSync(new URL('../../tests/fixtures/repairs904.json',import.meta.url),JSON.stringify({fixtures,hashes},null,2));
 assert.match(compileCard(fixtures.swap,registry).detailed_text,/交换/);
 for(const bad of [{...swap,target:'enemy_hq'},{...swap,duration:'match'},{...swap,value:3}])assert.throws(()=>compileCard({...fixtures.swap,abilities:[{trigger:'on_play',effects:[bad]}]},registry));
 assert.throws(()=>compileCard({...fixtures.swap,play_target:{side:'any',row:'any',include_hq:true}},registry));
 for(const n of [-100,100])assert.doesNotThrow(()=>compileCard({...fixtures.reduction,abilities:[{trigger:'on_play',effects:[{...fixtures.reduction.abilities[0].effects[0],amount:n}]}]},registry));
 for(const n of [-101,101])assert.throws(()=>compileCard({...fixtures.reduction,abilities:[{trigger:'on_play',effects:[{...fixtures.reduction.abilities[0].effects[0],amount:n}]}]},registry));
 assert.throws(()=>compileCard({...fixtures.armor,keywords:[{id:'standard.heavy_armor',version:1,params:{x:100}}]},registry));
 for(const n of [1,10,100])assert.doesNotThrow(()=>compileCard({...fixtures.armor,keywords:[{id:'standard.heavy_armor',version:2,params:{x:n}}]},registry));
 assert.throws(()=>validateKeyword({...armor(2),parameters:{x:{type:'integer',minimum:1,maximum:100},y:{type:'integer',minimum:1,maximum:100},z:{type:'integer',minimum:1,maximum:100}}}),e=>e.code==='RULE_BUDGET_EXCEEDED');
});
test('swap is available to templates, derived cards, branches and scheduled effects',()=>{
 const kw={...armor(1),id:'custom.swap',name:'互换',parameters:{},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{...swap,target:'self'}]}]}};
 assert.doesNotThrow(()=>validateKeyword(kw));
 const c={...fixtures.swap,tokens:[{...base('衍生互换'),token_id:'swap',abilities:fixtures.swap.abilities,play_target:fixtures.swap.play_target}]};delete c.tokens[0].schema_version;delete c.tokens[0].ruleset_version;delete c.tokens[0].flavor_text;delete c.tokens[0].tokens;delete c.tokens[0].appearance;
 assert.doesNotThrow(()=>compileCard(c,registry));
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[],null);assert(p.includes('swap_stats'));assert(p.includes('standard.heavy_armor@2'));assert(Buffer.byteLength(p)<200000,`${kind}: ${Buffer.byteLength(p)}`);}
});
test('armor v2 migration is additive, durable and preserves old frozen definitions',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'chao904-'));let s;
 try{s=new Store(dir);await s.init();assert.equal(hash(s.state.keywords['standard.heavy_armor@1'].definition),hash(armor(1)));assert.equal(s.state.keywords['standard.heavy_armor@2'].definition.parameters.x.maximum,100);const h=hash(s.state.keywords['standard.heavy_armor@1']);await s.close();s=new Store(dir);await s.init();assert.equal(hash(s.state.keywords['standard.heavy_armor@1']),h);}finally{await s?.close();rmSync(dir,{recursive:true,force:true});}
});
