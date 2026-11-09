import {hash} from '../src/codec.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,builtinDefinitions} from '../src/validation.js';
import {referenceTemplates,freezeReferenceTemplates} from '../src/card_references.js';
import {editorError} from '../../web/model.mjs';
const base=(name,kind='unit')=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name,flavor_text:'',kind,unit_class:kind==='unit'?'tank':null,cost:1,operation_cost:kind==='unit'?1:0,attack:kind==='unit'?3:0,health:kind==='unit'?4:0,keywords:[],play_target:null,abilities:[],tokens:[],appearance:{emblem:kind==='unit'?'tank':kind}});
const stats=(target,attack_delta,health_delta,duration='battle')=>({op:'modify_stats',target,attack_delta,health_delta,duration});
const incoming=(target,amount,more={})=>({op:'modify_incoming_damage',target,amount,damage_kind:'both',duration:'battle',...more});
const fixtures={};
function card(key,trigger,effects,patch={}){const c={...base(key),abilities:[{trigger,effects}],...patch};fixtures[key]=c;return c;}
card('otherAura','while_active',[stats('all_other_friendly_units',1,0)]);
card('vulnerability','while_active',[incoming('all_enemy_units',2),incoming('enemy_hq',2),incoming('all_enemy_units',1,{unit_filter:{unit_classes:['infantry','tank','artillery']}})]);
card('orderAura','while_active',[incoming('all_units',2,{source_kind:'order',source_side:'ally'}),incoming('enemy_hq',2,{source_kind:'order',source_side:'ally'})]);
card('attacked','after_attacked',[{op:'heal',target:'self',amount:1}]);
card('move','own_unit_moved',[stats('self_and_trigger',0,1)]);
card('headquartersGap','on_play',[stats('self',0,4)]).abilities[0].premise={test:'compare',left:{stat:'friendly_hq_health'},cmp:'gte',right:{stat:'enemy_hq_health'},right_offset:8};
card('excludeLiberated','on_play',[{op:'damage',target:'all_units',amount:4,unit_filter:{is_liberated:false}}],base('excludeLiberated','order'));
fixtures.excludeLiberated.abilities=[{trigger:'on_play',effects:[{op:'damage',target:'all_units',amount:4,unit_filter:{is_liberated:false}}]}];
card('developDeck','on_play',[{op:'develop',source:'deck'}],{...base('developDeck','order'),abilities:[{trigger:'on_play',effects:[{op:'develop',source:'deck'}]}]});
card('suspend','on_play',[{op:'temporarily_remove',target:'all_units',return_when:'next_opponent_turn_start',after_turns:2,destination:'original_position',reset:'temporary'}],{...base('suspend','order'),abilities:[{trigger:'on_play',effects:[{op:'temporarily_remove',target:'all_units',return_when:'next_opponent_turn_start',after_turns:2,destination:'original_position',reset:'temporary'}]}]});
card('equalAttack','on_play',[{op:'set_combat_damage_multiplier',target:'self',multiplier:1,against:'any',applies_to:'both',duration:'battle',attack_base:'opponent'}]);
card('once','on_play',[{op:'schedule',trigger:'next_own_unit_deployed',repeat:'each_event',lifetime:'match',once_per_card:'tank_defense',effects:[{...stats('trigger_unit',0,1,'match'),unit_filter:{unit_classes:['tank']}}]}]);
fixtures.once.kind='order';fixtures.once.unit_class=null;fixtures.once.attack=0;fixtures.once.health=0;fixtures.once.operation_cost=0;fixtures.once.appearance.emblem='order';
card('liberateChoice','when_condition',[{op:'liberate',target:'self',token_id:'form'},{op:'choose_effect',options:[{label:'闪击',effects:[{op:'grant_keyword',target:'self',keyword_id:'core.blitz',keyword_version:2,duration:'battle'}]},{label:'攻击',effects:[stats('self',1,0)]}]}]);
fixtures.liberateChoice.abilities[0].premise={test:'compare',left:{count_units:{side:'ally',unit_classes:['tank']}},cmp:'gt',right:0};
fixtures.liberateChoice.tokens=[{token_id:'form',name:'解放形态',kind:'unit',unit_class:'tank',cost:1,operation_cost:1,attack:3,health:4,keywords:[],abilities:[],play_target:null}];
fixtures.orderImmune={...base('orderImmune'),keywords:[{id:'core.order_untargetable',version:1,params:{}}]};
fixtures.maxOnly=card('maxOnly','on_play',[{...stats('self',1,-2),health_mode:'max_only'}]);
card('killCopy','on_kill',[{op:'transfer_card',source:'event_card',destination:'hand',mode:'copy',selection:'top',amount:1}]);
card('killForm','on_kill',[{op:'become_trigger_unit',target:'self',inherit:'permanent'}]);
card('handCost','enemy_unit_died',[{op:'modify_hand_cost',selection:'self',cost_delta:-3,duration:'hand'}],{cost:8}).abilities[0].zone='hand';
fixtures.handCost.abilities.push({trigger:'enemy_unit_died',effects:[{op:'modify_operation_cost',target:'self',cost_delta:-2,duration:'battle'}]});
fixtures.zeroCost={...base('zeroCost'),cost:8,cost_override:{premise:{test:'compare',left:{stat:'enemy_deaths_this_turn'},cmp:'gt',right:0},value:0}};
fixtures.drawCost={...base('drawCost','order'),abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:2,filter:{kind:'counter'}},{op:'modify_hand_cost',selection:'drawn',cost_delta:-1,duration:'hand'}]}]};
card('salvageGain','own_unit_deployed',[{...stats('self_and_trigger',1,0),unit_filter:{generated_by:'salvage'}}]);
// Select the event by premise; self_and_trigger must include the non-salvaged listener too.
delete fixtures.salvageGain.abilities[0].effects[0].unit_filter;
fixtures.salvageGain.abilities[0].premise={test:'unit_matches',target:'trigger_unit',filter:{generated_by:'salvage'}};
fixtures.bomberBypass={...base('bomberBypass'),unit_class:'bomber',appearance:{emblem:'bomber'},keywords:[{id:'core.ignore_fighter_cover',version:1,params:{}}]};
fixtures.endSuspend=structuredClone(fixtures.suspend);fixtures.endSuspend.name='endSuspend';fixtures.endSuspend.abilities[0].effects[0].return_when='next_opponent_turn_end';fixtures.endSuspend.abilities[0].effects[0].after_turns=1;
test('861 report fixtures compile and publish matching native parity vectors',()=>{
 const registry=Object.fromEntries(builtinDefinitions.map(definition=>[definition.id+'@'+definition.version,{definition,definition_hash:hash(definition),registry_status:'approved'}]));
 const hashes={};for(const [name,c] of Object.entries(fixtures)){
  try{const v=compileCard(c,registry);hashes[name]=v.compiled_program_hash;assert.doesNotMatch(v.rules_text,/undefined|NaN/);}catch(e){console.error(e.stack);throw new Error(name+': '+e.message,{cause:e});}
 }
 writeFileSync(new URL('../../tests/fixtures/repairs861.json',import.meta.url),JSON.stringify({fixtures,hashes},null,2));
});

test('named published cards and nested tokens freeze with accurate effects',()=>{
 const c={...base('偶遇','order'),abilities:[{trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]}]};
 const compiled=compileCard(c,{}),record={...compiled,card_id:'10000000-0000-4000-8000-000000000001',revision:1,definition:c};
 const catalog=referenceTemplates({cards:{one:[record]}},'生成一张偶遇');
 assert.equal(catalog.length,1);
 const spec={...base('引用'),abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:catalog[0].token_id,player:'owner',amount:1}]}]};
 const frozen=freezeReferenceTemplates(spec,catalog);assert.doesNotThrow(()=>compileCard(frozen,{}));
 assert.equal(frozen.tokens[0].abilities[0].effects[0].op,'draw');
 c.abilities[0].effects[0].amount=2;assert.equal(frozen.tokens[0].abilities[0].effects[0].amount,1);
 assert.equal(editorError(fixtures.once),'');assert.equal(editorError(fixtures.killCopy),'');
 const bad=structuredClone(fixtures.equalAttack);bad.abilities[0].effects[0].divisor=2;assert.match(editorError(bad),/取整/);
});
