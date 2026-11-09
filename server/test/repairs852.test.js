import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,validateCardBlueprint,applyCardBlueprint} from '../src/validation.js';
import {readyCard,blueprint,freshCard,keywordFits} from '../../web/model.mjs';
import {recordDiagnostic,authorReports} from '../src/diagnostics.js';
const keyword={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.release',version:1,name:'解放',description:'满足本卡条件时解放，回手后重置。',aliases:[],parameters:{},implementation:{kind:'configurable'}};
const registry={'custom.release@1':{...validateKeyword(keyword),registry_status:'approved'}};
const ability={trigger:'when_condition',premise:{test:'compare',left:{stat:'enemy_unit_count'},cmp:'gt',right:0},effects:[{op:'modify_stats',target:'self',attack_delta:2,health_delta:1,duration:'battle'},{op:'draw',player:'owner',amount:1}]};
const card={...freshCard(),name:'逐卡解放',cost:1,attack:3,health:4,keywords:[{id:'custom.release',version:1,params:{},abilities:[ability]}]};

test('configurable keyword freezes independent per-card and token abilities in both hashes',()=>{
 const a=compileCard(card,registry),b=structuredClone(card);b.keywords[0].abilities[0].effects[0].attack_delta=4;
 const changed=compileCard(b,registry);assert.notEqual(a.definition_hash,changed.definition_hash);assert.notEqual(a.compiled_program_hash,changed.compiled_program_hash);
 assert.equal(a.compiled_program.expanded_definition.abilities[0].effects[0].attack_delta,2);
 assert.match(a.short_rules_text,/解放/);assert.match(a.short_rules_text,/满足条件/);assert.doesNotMatch(a.rules_text,/undefined/);
 assert.doesNotThrow(()=>validateCardBlueprint(blueprint(card),registry));assert.ok(keywordFits(keyword,'unit'));
 const token={...card,token_id:'child'};for(const k of ['schema_version','ruleset_version','appearance','tokens'])delete token[k];
 const parent={...freshCard(),name:'母卡',tokens:[token],abilities:[{trigger:'on_play',effects:[{op:'summon',token_id:'child',amount:1,row:'support'}]}]};
 assert.equal(compileCard(parent,registry).compiled_program.expanded_definition.tokens[0].abilities.length,1);
 writeFileSync(new URL('../../tests/fixtures/repairs852.json',import.meta.url),JSON.stringify({keyword,card,hash:a.compiled_program_hash,parent}));
});

test('empty and forged configurations cannot bypass validation or execution budgets',()=>{
 const check=change=>{const c=structuredClone(card);change(c);assert.throws(()=>compileCard(c,registry));};
 check(c=>delete c.keywords[0].abilities);check(c=>c.keywords[0].abilities=[]);
 check(c=>c.keywords[0].abilities[0].effects[0].attack_delta=999);
 check(c=>c.abilities=Array.from({length:8},()=>({trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]})));
 check(c=>delete c.keywords[0].abilities[0].premise);
 check(c=>c.keywords[0].abilities[0].premise={test:'unit_state',target:'chosen',state:'has_attacked'});
 check(c=>c.keywords[0].abilities[0].limit=2);
 const ordinary={...keyword,id:'custom.ordinary',implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]}};
 const c=structuredClone(card);c.keywords[0].id=ordinary.id;
 assert.throws(()=>compileCard(c,{'custom.ordinary@1':{...validateKeyword(ordinary),registry_status:'approved'}}),/逐卡配置/);
 assert.throws(()=>validateKeyword({...keyword,parameters:{x:{type:'integer',minimum:1,maximum:2}}}),/参数/);
});

test('per-card chosen effects, orders and deferred selections use the ordinary compiler',()=>{
 const c={...structuredClone(card),kind:'order',unit_class:null,operation_cost:0,attack:0,health:0,appearance:{emblem:'order'}};
 c.keywords[0].abilities=[{trigger:'on_play',effects:[{op:'damage',target:'chosen',amount:2}]}];
 const prepared=readyCard(c,[{definition:keyword}]);assert.deepEqual(prepared.play_target,{side:'enemy',row:'any'});assert.doesNotThrow(()=>compileCard(prepared,registry));
 const unit=structuredClone(card);unit.keywords[0].abilities[0].effects.push({op:'damage',target:'chosen',amount:1});unit.keywords[0].abilities[0].target={side:'enemy',row:'any',timing:'trigger'};
 assert.doesNotThrow(()=>compileCard(unit,registry));
 c.keywords[0].abilities=[ability];assert.throws(()=>compileCard(c,registry),/单位/);
});

test('failed form reports retain a bounded card snapshot only for its author',()=>{
 const state={diagnostics:{},generations:{}};const definition={...card,password:'not-a-card-field',flavor_text:'sk-secretvalue'};
 const id=recordDiagnostic(state,{stage:'/v1/card-drafts',code:'INVALID_SCHEMA',message:'数量错误',owner:'author',definition});
 const saved=authorReports(state,'author').items[0];assert.equal(saved.card_definition.name,card.name);assert.equal(saved.card_definition.password,undefined);assert.doesNotMatch(saved.card_definition.flavor_text,/secretvalue/);
 assert.equal(authorReports(state,'other').items.length,0);assert.throws(()=>authorReports(state,'other',state.diagnostics[id].number));
});

test('assistant can fill empty per-card slots without replacing fixed configuration',()=>{
 const pending=structuredClone(card);pending.keywords[0].abilities=[];
 const bp=validateCardBlueprint(blueprint(pending),registry);assert.deepEqual(bp.keywords[0].abilities,[]);
 assert.doesNotThrow(()=>compileCard(applyCardBlueprint(card,bp),registry));
 assert.throws(()=>compileCard(pending,registry));
 const fixed=blueprint(card),changed=structuredClone(card);changed.keywords[0].abilities[0].effects[0].attack_delta=6;
 assert.throws(()=>applyCardBlueprint(changed,fixed),/修改/);
 const spoof=structuredClone(card);spoof.keywords[0].version=2;assert.throws(()=>applyCardBlueprint(spoof,bp));
 const token={...pending,token_id:'child'};for(const k of ['schema_version','ruleset_version','appearance','tokens'])delete token[k];
 const parent={...freshCard(),name:"母卡",tokens:[token],abilities:[{trigger:'on_play',effects:[{op:'summon',token_id:'child',amount:1,row:'support'}]}]};
 const tb=validateCardBlueprint(blueprint(parent),registry);assert.deepEqual(tb.tokens[0].keywords[0].abilities,[]);
 parent.tokens[0].keywords[0].abilities=[ability];assert.doesNotThrow(()=>compileCard(applyCardBlueprint(parent,tb),registry));
});
