import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,builtinDefinitions} from '../src/validation.js';
import {hash} from '../src/codec.js';
import {freshCard,readyCard,usesChosen} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
import {registerComponents} from '../src/mechanism_components.js';
// Retired online generation limit; the DSH plugin pages the rules. 0.9.10 schema additions need the headroom.
const PROMPT_LIMIT=210000;
const registry=Object.fromEntries([...builtinDefinitions,JSON.parse(readFileSync(new URL("../../docs/cards/examples/keywords/core_blitz.json",import.meta.url),"utf8"))].map(d=>[d.id+'@'+d.version,{definition:d,definition_hash:hash(d),registry_status:'approved'}]));
const base=name=>({...freshCard(),name,kind:'order',unit_class:null,attack:0,health:0,operation_cost:0,appearance:{emblem:'order'}});
const count={count_units:{side:'ally',name_contains:'集团军',distinct_by:'name'}};
const buff={...base('沙场指挥'),abilities:[{trigger:'on_play',effects:[{op:'modify_stats',target:'all_friendly_units',attack_delta:count,health_delta:count,duration:'match'}]}]};
const choice={...base('能量轰击'),play_target:{side:'ally',row:'any'},abilities:[{trigger:'on_play',effects:[{op:'choose_effect',options:[{label:'抽牌',effects:[{op:'damage',target:'chosen',amount:2},{op:'draw',player:'owner',amount:2}]},{label:'轰击',effects:[{op:'damage',target:'chosen',amount:2},{op:'damage',target:'random_enemy_unit',amount:5}]}]}]}]};
const next={...base('快速压制'),play_target:{side:'any',row:'any'},abilities:[{trigger:'on_play',effects:[{op:'pin',target:'chosen',turns:1}]},{trigger:'next_own_unit_deployed',effects:[{op:'grant_keyword',target:'trigger_unit',keyword_id:'core.blitz',keyword_version:1,duration:'battle'}]}]};
const named={...base('蛮横冲撞'),abilities:[{trigger:'on_play',effects:[{op:'modify_stacks',target:'all_friendly_units',unit_filter:{name_contains:'集团军'},stack:'heavy_armor',amount:1,duration:'battle'},{op:'grant_keyword',target:'all_friendly_units',unit_filter:{card_name:'第4集团军犀牛'},keyword_id:'core.immune',keyword_version:1,duration:'end_of_turn'}]}]};
const cards=[buff,choice,next,named];
writeFileSync(new URL('../../tests/fixtures833.json',import.meta.url),JSON.stringify({cards:cards.map(d=>compileCard(d,registry)),keywords:Object.values(registry).map(r=>r.definition)}));

test('62 to 65 compile and render names, unique counts, choices, delayed grants',()=>{
 for(const d of cards){const c=compileCard(d,registry);assert(!c.rules_text.includes('undefined'));assert(!c.rules_text.includes('[object Object]'));assert.equal(JSON.stringify(readyCard(d,[]).play_target),JSON.stringify(d.play_target));}
 assert.match(compileCard(buff,{}).rules_text,/种数.*同名/);assert.match(compileCard(choice,{}).rules_text,/抉择.*抽牌.*轰击/);assert.match(compileCard(named,registry).rules_text,/集团军.*重甲/);assert.match(compileCard(next,registry).rules_text,/下一次己方部署/);
 const k={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.branch',version:1,name:'抉择',description:'选择一个效果',aliases:[],parameters:{x:{type:"integer",minimum:1,maximum:3}},implementation:{kind:'template',abilities:structuredClone(choice.abilities)}};
 k.implementation.abilities[0].effects[0].options[0].effects[1].amount={param:'x'};assert(validateKeyword(k));
 const c=structuredClone(choice);c.abilities[0].effects[0].options[1].effects.push({op:'grant_keyword',target:'chosen',keyword_id:'core.immune',keyword_version:1,duration:'battle'});assert(compileCard(c,registry).keyword_bindings.some(k=>k.id==='core.immune'));
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[]);for(const term of ['unit_filter','distinct_by','choose_effect','next_own_unit_deployed'])assert(p.includes(term));assert(Buffer.byteLength(p)<PROMPT_LIMIT);}
});
test('branch internals enforce targets, references, budgets and order-sensitive prerequisites',()=>{
 const bads=[d=>d.play_target=null,d=>d.abilities[0].effects[0].options[0].effects=[{op:'damage',target:'self',amount:1}],d=>d.abilities[0].effects[0].options[0].effects=[{op:'create_card',token_id:'missing',amount:1,player:'owner'}],d=>d.abilities[0].effects.push(structuredClone(d.abilities[0].effects[0])),d=>d.abilities[0].trigger='next_own_turn_start',d=>d.abilities[0].effects[0].options[0].effects.push(structuredClone(d.abilities[0].effects[0])),d=>d.abilities[0].effects[0].options.push(...structuredClone(d.abilities[0].effects[0].options))];
 for(const mutate of bads){const d=structuredClone(choice);mutate(d);assert.throws(()=>compileCard(d,registry));}
 const d=structuredClone(choice);d.play_target=null;d.abilities[0].effects[0].options=[{label:'弃牌',effects:[{op:'discard',player:'owner',amount:1}]},{label:'强化',effects:[{op:'modify_cards',player:'owner',zones:['hand'],filter:{same_as_discarded:true},attack_delta:1,health_delta:1,duration:'match'}]}];assert.throws(()=>compileCard(d,registry),/先弃置/);
 const tooMany=structuredClone(choice);tooMany.play_target=null;tooMany.abilities[0].effects[0].options=[0,1,2].map(i=>({label:String(i),effects:Array.from({length:6},()=>({op:'draw',player:'owner',amount:1}))}));tooMany.abilities.push(...Array.from({length:2},()=>({trigger:"on_play",effects:Array.from({length:4},()=>({op:"draw",player:"owner",amount:1}))})));assert.throws(()=>compileCard(tooMany,{}),/24/);
});
test('named selectors reject ambiguous empty or unknown filters; local components do not leak token IDs',()=>{
 for(const filter of [{},{name_contains:''},{name_contains:' '},{name_contains:' 集团军'},{unit_classes:[]},{formula:'*'}]){const d=structuredClone(named);d.abilities[0].effects[0].unit_filter=filter;assert.throws(()=>compileCard(d,registry));}
 for(const selector of [{side:'ally',distinct_by:'class'},{side:'all'},{side:'ally',name_contains:''}]){const d=structuredClone(buff);d.abilities[0].effects[0].attack_delta={count_units:selector};assert.throws(()=>compileCard(d,{}));}
 const state={};const d=structuredClone(choice);d.abilities[0].effects[0].options[0].effects.push({op:'create_card',token_id:'private',amount:1,player:'owner'});registerComponents(state,'test',d);assert.equal(Object.values(state.mechanism_components).filter(c=>c.kind==='result').length,0);
});
