import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,builtinDefinitions} from '../src/validation.js';
import {freshCard,keywordFits} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
import {ruleCapabilities} from '../src/rule_capabilities.js';
import {CentralMatches} from '../src/central_matches.js';
const faction='06333d61-3b2e-425d-80ca-478917b21af1';
const base=name=>({...freshCard(),name,cost:0,attack:2,health:4,keywords:[],abilities:[],faction_id:faction});
const active={trigger:'on_activate',limit:1,limit_scope:'turn',target:{side:'ally',row:'any',timing:'trigger',faction_id:faction},effects:[{op:'trigger_evolution',target:'chosen'}]};
const token=(name,id)=>{const c=base(name);for(const k of ['schema_version','ruleset_version','tokens','appearance','flavor_text','faction_id'])delete c[k];return {...c,token_id:id};};
const form={...token('玉黄龙','dragon'),attack:5,health:7,abilities:[active]};
const schedule={op:'schedule',trigger:'next_own_turn_start',after_turns:3,repeat:'once',lifetime:'source',effects:[{op:'transform',target:'self',token_id:'dragon',inherit:'none'}]};
const fixtures={dragon:{...base('主动来源'),abilities:[active]},jade:{...base('玉蜥'),abilities:['on_play','on_summon'].map(trigger=>({trigger,effects:[schedule]})),tokens:[form]},plain:base('无进化单位'),gift:{...base('主动抽牌'),abilities:[{trigger:'on_activate',limit:1,limit_scope:'turn',effects:[{op:'draw',player:'owner',amount:1}]}]}};
test('905 active abilities compile on units, derived forms and keyword templates',()=>{
 const hashes={};for(const [key,c] of Object.entries(fixtures))hashes[key]=compileCard(c,{}).compiled_program_hash;
 writeFileSync(new URL('../../tests/fixtures/repairs905.json',import.meta.url),JSON.stringify({fixtures,hashes},null,2));
 assert.match(compileCard(fixtures.dragon,{}).detailed_text,/主动.*每回合/);
 const kw=JSON.parse(readFileSync(new URL('../../docs/cards/examples/keywords/standard_heavy_armor.json',import.meta.url),'utf8'));
 Object.assign(kw,{id:'custom.active',name:'主动',parameters:{},implementation:{kind:'template',abilities:[active]}});
 assert.doesNotThrow(()=>validateKeyword(kw));assert(keywordFits(kw,'unit'));assert(!keywordFits(kw,'order'));
 for(const a of [{...active,limit:2},{...active,limit_scope:'battle'},{...active,target:{...active.target,timing:'deploy'}},{...active,limit:undefined},{...active,zone:'hand'}])assert.throws(()=>compileCard({...fixtures.dragon,abilities:[a]},{}));
 for(const kind of ['order','field','hq','counter'])assert.throws(()=>compileCard({...fixtures.dragon,kind,unit_class:null,attack:0,health:kind==='hq'?20:0,operation_cost:0},{}));
});
test('905 network activation validates exact command shape',()=>{
 const command=CentralMatches.prototype.command;
 assert.deepEqual(command({type:'activate',uid:1,ability_index:0}),{type:'activate',uid:1,ability_index:0});
 for(const x of [{uid:0},{uid:1.1},{ability_index:-1},{ability_index:64},{ability_index:'0'},{target_uid:2}])assert.throws(()=>command({type:'activate',uid:1,ability_index:0,...x}));
});
test('905 generation knows active and target-owned evolution capabilities',()=>{
 assert.equal(ruleCapabilities.triggers.length,new Set(ruleCapabilities.triggers).size);
 for(const kind of ['card','keyword','mechanism-review']){
  const prompt=makePrompt(kind,[],null);assert(prompt.includes('on_activate'));assert(prompt.includes('自身尚未完成的进化'));assert(Buffer.byteLength(prompt)<200000,`${kind}: ${Buffer.byteLength(prompt)}`);
 }
});
