import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,builtinDefinitions,validateCardBlueprint,applyCardBlueprint,schemaCheck} from '../src/validation.js';
import {hash} from '../src/codec.js';
import {blueprint} from '../../web/model.mjs';
import {makePrompt} from '../src/provider.js';
// Retired online generation limit; the DSH plugin pages the rules. 0.9.10 schema additions need the headroom.
const PROMPT_LIMIT=210000;
const base=(name,kind='unit')=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name,flavor_text:'',kind,unit_class:kind==='unit'?'infantry':null,cost:1,operation_cost:kind==='unit'?1:0,attack:kind==='unit'?3:0,health:kind==='unit'?4:0,keywords:[],play_target:null,abilities:[],tokens:[],appearance:{emblem:kind==='unit'?'infantry':kind}});
const gain={op:'gain_kredits',amount:1,allow_overflow:true};
const token=(name,id)=>({token_id:id,name,kind:'order',unit_class:null,cost:0,operation_cost:0,attack:0,health:0,keywords:[],abilities:[{trigger:'on_play',effects:[gain]}]});
const testHand=name=>({test:'hand_contains',player:'owner',filter:{card_name:name}});
const addPurple={op:'create_card',token_id:'purple',amount:1,player:'owner'};
const conditional={label:'茈',premise:{test:'all',items:[testHand('苍'),testHand('赫')]},effects:[addPurple]};
const fixtures={
 overflow:{...base('无限生产团'),abilities:[{trigger:'own_turn_start',effects:[gain]}]},
 aura:{...base('和谐记忆'),abilities:[{trigger:'while_active',effects:[{op:'modify_stats',target:'adjacent_to_self',attack_delta:2,health_delta:0,duration:'battle',unit_filter:{exclude_sins:['envy']}}]}]},
 immune:{...base('五条悟'),abilities:[{trigger:'on_play',effects:[{op:'modify_incoming_damage',target:'self',damage_kind:'combat',amount:0,immune:true,duration:'battle'}]}]},
 listener:{...base('咖啡记忆'),abilities:[{trigger:'own_card_played',premise:{test:'event_card',filter:{sins:['wrath','lust','sloth','gluttony','gloom','pride']}},effects:[{op:'damage',target:'enemy_hq',amount:1}]}]},
 choices:{...base('条件抉择','order'),tokens:[token('苍','blue'),token('赫','red'),token('茈','purple')],abilities:[{trigger:'on_play',effects:[{op:'choose_effect',options:[{label:'苍',effects:[{...addPurple,token_id:'blue'}]},{label:'赫',effects:[{...addPurple,token_id:'red'}]},conditional]}]}]},
 chain:{...base('苍','order'),tokens:[token('茈','purple')],abilities:[{trigger:'on_play',premise:{test:'previous_card',kind:'order',player:'owner',card_name:'赫',this_turn:true},effects:[addPurple]}]},
 history:{...base('本回合联动','order'),tokens:[token('茈','purple')],abilities:[{trigger:'on_play',premise:{test:'all',items:['苍','赫'].map(card_name=>({test:'played_this_turn',player:'owner',filter:{card_name}}))},effects:[addPurple]}]},
};
const registry=Object.fromEntries(builtinDefinitions.map(definition=>[definition.id+'@'+definition.version,{definition,definition_hash:hash(definition),registry_status:'approved'}]));
test('863 cross-runtime fixture contracts and bounded predicate validation',()=>{
 const hashes={};for(const [key,c] of Object.entries(fixtures)){const result=compileCard(c,registry);hashes[key]=result.compiled_program_hash;assert.doesNotMatch(result.rules_text,/undefined|NaN/);}
 writeFileSync(new URL('../../tests/fixtures/repairs863.json',import.meta.url),JSON.stringify({fixtures,hashes},null,2));
 for(const filter of [{exclude_sins:[]},{sins:['fake']},{sin:'bad'},{sins:['envy','envy']}]){let c=structuredClone(fixtures.aura);c.abilities[0].effects[0].unit_filter=filter;assert.throws(()=>compileCard(c,registry));}
 let c=structuredClone(fixtures.choices);c.abilities[0].effects[0].options[2].premise={test:'hand_contains',player:'owner',filter:{card_name:'苍'},min:0};assert.throws(()=>compileCard(c,registry));
});
test('empty derived orders can be sent to assistant but cannot be published without effects',()=>{
 const c={...base('空槽'),tokens:[{...token('蓝香','blue'),abilities:[]}],abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:'blue',amount:1,player:'owner'}]}]};const bp=blueprint(c);assert.doesNotThrow(()=>validateCardBlueprint(bp,{}));assert.throws(()=>compileCard(c,{}));
 const candidate=structuredClone(c);candidate.abilities=[];candidate.tokens[0].abilities=[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1},{op:'damage',target:'enemy_hq',amount:2}]}];const merged=applyCardBlueprint(candidate,bp);assert.doesNotThrow(()=>compileCard(merged,{}));assert.equal(bp.tokens[0].abilities.length,0);
 candidate.tokens[0].cost=8;assert.throws(()=>applyCardBlueprint(candidate,bp),e=>e.code==='BLUEPRINT_TOKEN_CONFLICT');
});
test('replace mode changes derived effects while preserving identity and original blueprints',()=>{
 const c=structuredClone(fixtures.choices),bp=blueprint(c,'replace'),candidate=structuredClone(c);candidate.tokens[0].abilities[0].effects[0].amount=2;
 const merged=applyCardBlueprint(candidate,bp);assert.equal(merged.tokens[0].abilities[0].effects[0].amount,2);assert.equal(bp.tokens[0].abilities[0].effects[0].amount,1);
 assert.throws(()=>applyCardBlueprint(candidate,blueprint(c)),e=>e.code==='BLUEPRINT_TOKEN_CONFLICT');candidate.tokens[0].cost=9;assert.throws(()=>applyCardBlueprint(candidate,bp),e=>e.code==='BLUEPRINT_TOKEN_CONFLICT');
});
test('numeric parameter errors do not also demand text; prompts teach all new capabilities',()=>{
 const c=base('参数报错');c.keywords=[{id:'standard.heavy_armor',version:1,params:{x:101}}];assert.throws(()=>schemaCheck('card',c),e=>/不能大于 100/.test(e.message)&&!/必须是文字/.test(e.message));
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[],blueprint(fixtures.choices));for(const term of ['allow_overflow','exclude_sins','immune=true','played_this_turn','hand_contains','this_turn'])assert(p.includes(term),term);assert(Buffer.byteLength(p)<PROMPT_LIMIT,'prompt too large '+Buffer.byteLength(p));}
});
