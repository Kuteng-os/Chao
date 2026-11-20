import assert from 'node:assert/strict';
import {mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {compileCard, validateKeyword, docsURL, schemas} from '../server/src/validation.js';

if (!process.env.GODOT_BIN) throw new Error('Set GODOT_BIN to the Godot editor executable.');
const root = fileURLToPath(new URL('..', import.meta.url));
const keywords = await Promise.all(['core_blitz', 'core_guard'].map(async name => JSON.parse(await readFile(new URL(`examples/keywords/${name}.json`, docsURL), 'utf8'))));
const base = kind => ({schema_version:'1.0.0', ruleset_version:'frontline-1', name:'跨运行时边界', flavor_text:'', kind, unit_class:kind === 'unit' ? 'artillery' : null, cost:1, operation_cost:kind === 'unit' ? 1 : 0, attack:kind === 'unit' ? 2 : 0, health:kind === 'unit' ? 4 : 0, keywords:[], play_target:null, abilities:[], tokens:[], appearance:{emblem:kind === 'unit' ? 'artillery' : 'order'}});
const corpus = [];
function add(name, definition, catalog = keywords) {
  let expected;
  try {
    const registry = Object.fromEntries(catalog.map(def => [`${def.id}@${def.version}`, {...validateKeyword(def, {allowBuiltin:true}), registry_status:'approved'}]));
    const compiled = compileCard(definition, registry);
    expected = {ok:true, definition_hash:compiled.definition_hash, compiled_program_hash:compiled.compiled_program_hash};
  } catch { expected = {ok:false}; }
  corpus.push({name, definition, keywords:catalog, expected});
}
for (const kind of ['unit','order']) for (const trigger of schemas.card.definitions.ability.properties.trigger.enum) {
  for (const target of ['self','chosen','own_hq','enemy_hq','all_friendly_units','all_enemy_units','random_friendly_unit','random_enemy_unit']) {
    const examples = [
      {op:'destroy',target},
      ...['any','infantry','tank','artillery','fighter','bomber','hq','invalid'].flatMap(against => ['attack','retaliation','both','invalid'].flatMap(applies_to => [0,1,2,4,5].map(multiplier => ({op:'set_combat_damage_multiplier',target,against,applies_to,multiplier,duration:'battle'})))),
      ...[0,1,2,4,5,true,1.5].flatMap(attacks => ['battle','end_of_turn'].map(duration => ({op:'set_attack_limit', target, attacks, duration}))),
      ...[-5,-4,-1,0,1,4,5,true,0.5].flatMap(cost_delta => ['battle','end_of_turn'].map(duration => ({op:'modify_operation_cost', target, cost_delta, duration}))),
    ];
    for (const effect of examples) {
      const definition = base(kind);
      definition.play_target = target === 'chosen' ? {side:'ally',row:'any'} : null;
      definition.abilities = [{trigger,effects:[effect]}];
      add(`${kind}/${trigger}/${JSON.stringify(effect)}`, definition);
    }
  }
}
const fight = JSON.parse(await readFile(new URL('examples/keywords/example_fight.json', docsURL), 'utf8'));
for (const [op, field, ranges] of [['set_attack_limit','attacks',[[1,4],[0,4],[1,5],[2,2]]], ['modify_operation_cost','cost_delta',[[-4,-1],[1,4],[-1,1],[0,0],[-5,-1],[4,5]]]]) {
  for (const [minimum, maximum] of ranges) for (const value of [-5,-4,-1,0,1,2,4,5]) {
    const keyword = structuredClone(fight);
    keyword.parameters = {n:{type:'integer', minimum, maximum}};
    keyword.implementation.abilities[0].effects = [{op,target:'self',[field]:{param:'n'},duration:'battle'}];
    const definition = base('unit'); definition.keywords = [{id:keyword.id,version:1,params:{n:value}}];
    add(`template/${op}/${minimum}..${maximum}/${value}`, definition, [...keywords,keyword]);
  }
}
for(const counter_trigger of ['enemy_unit_deployed','enemy_order_played','enemy_hq_attacked','enemy_unit_acted','enemy_unit_moved_to_front','enemy_unit_ability_triggered','unit_attack_changed',null,'invalid'])
 for(const trigger of ['on_reveal','on_play','on_death'])
  for(const effect of [{op:'cancel_action'},...['self','chosen','trigger_unit','enemy_hq'].map(target=>({op:'damage',target,amount:2}))]){
   const c={...base('counter'),counter_trigger,appearance:{emblem:'counter'},abilities:[{trigger,effects:[effect]}]};
   add('counter/'+JSON.stringify({counter_trigger,trigger,effect}),c);
   const template={...structuredClone(fight),id:'custom.counter_parity',implementation:{kind:'template',abilities:c.abilities}};
   const withTemplate={...c,abilities:[],keywords:[{id:template.id,version:1,params:{}}]};
   add('counter template/'+JSON.stringify({counter_trigger,trigger,effect}),withTemplate,[...keywords,template]);
  }
for(const rarity of ['standard','limited','special','elite','invalid',null])add('rarity/'+rarity,{...base('unit'),rarity});
for (const kind of ['unit','order']) for (const trigger of ['on_play','on_death','own_turn_end'])
 for (const target of ['chosen','random_enemy_unit']) for (const selector of [undefined,{side:'enemy',row:'any'},{side:'ally',row:'front'},{side:'enemy',row:'bad'}])
  for (const amount of [1,10,11,{stat:'source_base_health'},{stat:'current_health'},{stat:'source_base_health',formula:'x'},{}]) {
   const c=base(kind);c.abilities=[{trigger,...(selector?{target:selector}:{}),effects:[{op:'damage',target,amount}]}];
   c.play_target=trigger==='on_play'&&target==='chosen'?{side:'enemy',row:'any'}:null;
   add('dynamic direct/'+JSON.stringify(c),c);
   const template={...structuredClone(fight),implementation:{kind:'template',abilities:c.abilities}};
   add('dynamic template/'+JSON.stringify(c),{...c,abilities:[],keywords:[{id:template.id,version:1,params:{}}]},[...keywords,template]);
  }
for (const op of ['modify_stacks','set_stacks']) for (const amount of [-11,-10,-1,0,1,10,11,true,1.5]) for(const stack of ['heavy_armor','poison']) {
 const c=base('unit');c.abilities=[{trigger:'on_play',effects:[{op,target:'self',stack,amount,duration:'battle'}]}];add('stack/'+JSON.stringify(c),c);
}
for(const op of ['modify_stacks','set_stacks'])for(const [minimum,maximum] of [[-10,-1],[-1,1],[0,0],[0,10],[1,10],[10,11]])for(const value of [-10,-1,0,1,10,11]){
 const kw={...structuredClone(fight),parameters:{x:{type:'integer',minimum,maximum}},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{op,target:'self',stack:'heavy_armor',amount:{param:'x'},duration:'battle'}]}]}};
 const c={...base('unit'),keywords:[{id:kw.id,version:1,params:{x:value}}]};add('stack template/'+JSON.stringify({op,minimum,maximum,value}),c,[...keywords,kw]);
}
for(const op of ['search_deck','summon_from_deck'])for(const card_name of ['玉石','',' 玉石','玉\n石','玉'.repeat(33)])for(const amount of [1,3,0,4,true,{param:'n'}]){
 const effect={op,card_name,amount},c=base('unit');c.abilities=[{trigger:'on_death',effects:[effect]}];add('deck direct/'+JSON.stringify(effect),c);
 const kw={...structuredClone(fight),parameters:typeof amount==='object'?{n:{type:'integer',minimum:1,maximum:3}}:{},implementation:{kind:'template',abilities:c.abilities}};
 add('deck keyword/'+JSON.stringify(effect),{...c,abilities:[],keywords:[{id:kw.id,version:1,params:typeof amount==='object'?{n:2}:{}}]},[...keywords,kw]);
}
for(const kind of ['unit','order','counter'])for(const trigger of ['on_play','on_summon','on_death','on_reveal'])for(const op of ['summon','create_card'])for(const target of ['self','chosen','enemy_hq']){
 const token={token_id:'child',name:'子卡',kind,cost:0,operation_cost:kind==='unit'?1:0,unit_class:kind==='unit'?'infantry':null,attack:kind==='unit'?2:0,health:kind==='unit'?3:0,keywords:[],abilities:[{trigger,effects:[{op:'damage',target,amount:2}],...(['on_summon','on_death'].includes(trigger)&&target==='chosen'?{target:{side:'enemy',row:'any'}}:{})}],play_target:trigger==='on_play'&&target==='chosen'?{side:'enemy',row:'any'}:null,...(kind==='counter'?{counter_trigger:'enemy_order_played'}:{})};
 const e={op,token_id:'child',amount:1,...(op==='summon'?{row:'support'}:{player:'owner'})};
 add('generated/'+JSON.stringify({kind,trigger,op,target}),{...base('unit'),tokens:[token],abilities:[{trigger:'on_play',effects:[e]}]});
 const kw={...structuredClone(fight),id:'custom.generator',parameters:{},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[e]}]}};
 add('generated keyword/'+JSON.stringify({kind,trigger,op,target}),{...base('unit'),tokens:[token],keywords:[{id:kw.id,version:1,params:{}}]},[...keywords,kw]);
}
const armor=JSON.parse(await readFile(new URL('examples/keywords/standard_heavy_armor.json',docsURL),'utf8'));
for(const op of ['summon','create_card'])for(const maximum of [2,3,4])for(const value of [1,2,3]){
 const token={token_id:'child',name:'子卡',unit_class:'infantry',attack:1,health:3,keywords:[]};
 const kw={...structuredClone(fight),parameters:{n:{type:'integer',minimum:1,maximum}},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{op,token_id:'child',amount:{param:'n'},...(op==='summon'?{row:'support'}:{player:'owner'})}]}]}};
 add('generation range/'+JSON.stringify({op,maximum,value}),{...base('unit'),tokens:[token],keywords:[{id:kw.id,version:1,params:{n:value}}]},[...keywords,kw]);
}
for(const x of [1,3,10,11]){
 const token={token_id:'child',name:'重甲子卡',unit_class:'infantry',attack:1,health:3,keywords:[{id:armor.id,version:1,params:{x}}]};
 add('token registered armor/'+x,{...base('unit'),tokens:[token],abilities:[{trigger:'on_play',effects:[{op:'summon',token_id:'child',amount:1,row:'support'}]}]},[...keywords,armor]);
}
// 0.11.0 mechanics: new ops, summoned targets, random summons, value sources, cost limits and filters.
{
 const tokens=[{token_id:'a',name:'甲',unit_class:'infantry',attack:1,health:3,keywords:[]},{token_id:'b',name:'乙',unit_class:'infantry',attack:2,health:2,keywords:[]}];
 const summonA={op:'summon',token_id:'a',amount:1,row:'support'};
 for(const kind of ['unit','order','counter'])for(const counter_trigger of (kind==='counter'?['enemy_hq_attacked','enemy_unit_attacked','enemy_order_played','enemy_unit_acted']:[undefined]))for(const trigger of (kind==='counter'?['on_reveal']:['on_play','on_death','enemy_unit_entered']))for(const effects of [
  [summonA,{op:'redirect_attack',target:'summoned'}],[{op:'redirect_attack',target:'random_friendly_unit'}],[{op:'redirect_attack',target:'summoned'}],
  [summonA,{op:'fight',source:'summoned',target:'random_enemy_unit'}],[{op:'fight',source:'summoned',target:'random_enemy_unit'}],
  [summonA,{op:'move_unit',target:'summoned',row:'front'}],[{op:'move_unit',target:'self',row:'front'}],[{op:'move_unit',target:'trigger_unit',row:'support'}],
  [{op:'swap_position',target:'random_friendly_unit',with:'self'}],[{op:'swap_position',target:'trigger_unit',with:'self'}],
  [{op:'grant_action',target:'self',action:'attack',attack_target:'trigger_unit'}],[{op:'grant_action',target:'self',action:'attack'}],[{op:'grant_action',target:'self',action:'move'}],[{op:'grant_action',target:'self',action:'move',attack_target:'enemy_hq'}],[summonA,{op:'grant_action',target:'summoned',action:'attack',attack_target:'random_enemy_target'}],
  [{op:'summon',token_ids:['a','b'],amount:1,row:'support',position:'beside_hq'}],[{op:'summon',token_id:'a',token_ids:['a','b'],amount:1,row:'support'}],[{op:'summon',amount:1,row:'support'}],
  [{op:'draw',player:'owner',amount:{stat:'hand_shortfall'}}],[{op:'draw',player:'owner',amount:1,filter:{kind:'unit',unit_classes:['tank'],sins:['wrath',null],min_cost:2,max_cost:15,keyword_id:'core.guard'}}],
  [{op:'gain_hq_defense',player:'owner',amount:{stat:'friendly_draws_this_game'}}],[{op:'damage',target:'enemy_hq',amount:{unit_stat:{target:'trigger_unit',stat:'attack'}}}],
 ]){
  const c={...base(kind),tokens,abilities:[{trigger,effects}],...(kind==='counter'?{counter_trigger,appearance:{emblem:'counter'}}:{})};
  add('0110/'+JSON.stringify({kind,counter_trigger,trigger,effects}),c);
 }
 for(const cost of [12,15,20,21])add('cost/'+cost,{...base('unit'),cost});
 for(const cost_reduction of [{per_draw:true,amount:1},{per_unit:{side:'ally',row:'any'},amount:1},{per_draw:true,per_unit:{side:'ally',row:'any'},amount:1},{amount:1}])add('cost_reduction/'+JSON.stringify(cost_reduction),{...base('unit'),cost:15,cost_reduction});
 for(const [counter_trigger,counter_filter] of [['unit_attack_changed',{side:'own',direction:'down'}],['unit_attack_changed',null],['enemy_hq_attacked',{side:'own'}],['unit_attack_changed',{row:'sideways'}]])add('counter_filter/'+JSON.stringify({counter_trigger,counter_filter}),{...base('counter'),counter_trigger,counter_filter,appearance:{emblem:'counter'},abilities:[{trigger:'on_reveal',effects:[{op:'gain_hq_defense',player:'owner',amount:1}]}]});
 for(const [trigger,event_filter] of [['unit_attack_changed',{side:'enemy',row:'front',direction:'up'}],['unit_attack_changed',undefined],['on_play',{side:'any'}]])add('event_filter/'+JSON.stringify({trigger,event_filter}),{...base('unit'),abilities:[{trigger,...(event_filter?{event_filter}:{}),effects:[{op:'gain_hq_defense',player:'owner',amount:1}]}]});
 for(const stat of ['friendly_units_played_this_game','enemy_units_played_this_game','friendly_draws_this_game','hand_shortfall'])add('premise/'+stat,{...base('unit'),abilities:[{trigger:'on_play',premise:{test:'compare',left:{stat},cmp:'eq',right:1},effects:[{op:'gain_hq_defense',player:'owner',amount:1}]}]});
}
// 0.12.0 mechanics: forbid_play, play-cost auras, removed abilities, selected targets, counter return, kredit slots.
{
 const selectThree={op:'select_units',side:'enemy',min:3,max:3};
 for(const kind of ['unit','order','field'])for(const trigger of ['on_play','while_active','own_counter_returned','own_kredit_slot_gained','enemy_kredit_slot_gained','on_death'])for(const effects of [
  [{op:'forbid_play',player:'opponent',card_kinds:['order','field']}],[{op:'forbid_play',player:'owner',card_kinds:['unit']}],[{op:'forbid_play',player:'opponent',card_kinds:[]}],[{op:'forbid_play',player:'opponent',card_kinds:['order','order']}],
  [{op:'modify_play_cost',cost_delta:-1,filter:{kind:'order'},first_each_turn:true}],[{op:'modify_play_cost',cost_delta:1}],[{op:'modify_play_cost',cost_delta:0}],[{op:'modify_play_cost',cost_delta:-1,first_each_turn:false}],[{op:'modify_play_cost',cost_delta:-1,filter:{card_name:' 空格 '}}],
  [{op:'remove_abilities',target:'chosen',trigger:'on_death',duration:'battle'}],[{op:'remove_abilities',target:'all_enemy_units',trigger:'own_turn_start',duration:'end_of_turn'}],[{op:'remove_abilities',target:'self',trigger:'on_death',duration:'battle'}],[{op:'remove_abilities',target:'chosen',trigger:'while_active',duration:'battle'}],
  [selectThree,{op:'damage',target:'selected_units',amount:3}],[{op:'damage',target:'selected_units',amount:3}],[selectThree,{op:'heal',target:'selected_units',amount:2}],[selectThree,{op:'modify_stats',target:'selected_units',attack_delta:1,health_delta:0,duration:'end_of_turn'}],[selectThree,{op:'remove_keyword',target:'selected_units',keyword_id:'core.guard'}],[selectThree,{op:'grant_keyword',target:'selected_units',keyword_id:'core.guard',keyword_version:1,duration:'end_of_turn'}],[selectThree,{op:'suppress',target:'selected_units'}],[selectThree,{op:'return_to_hand',target:'selected_units'}],
  [{op:'modify_hand_cost',selection:'event_card',cost_set:0,duration:'hand'}],[{op:'modify_hand_cost',selection:'event_card',cost_delta:-5,duration:'hand',filter:{kind:'counter'}}],[{op:'modify_hand_cost',selection:'all',cost_set:0,duration:'end_of_turn',filter:{kind:'order'}}],[{op:'modify_hand_cost',selection:'all',cost_set:0,cost_delta:-1,duration:'hand'}],[{op:'modify_hand_cost',selection:'all',duration:'hand'}],
  [{op:'modify_kredit_slots',player:'owner',amount:1}],[{op:'draw',player:'owner',amount:{stat:'friendly_kredit_slots'}}],[{op:'damage',target:'enemy_hq',amount:{stat:'enemy_kredit_slots'}}],
  [{op:'modify_stacks',target:'self',stack:'heavy_armor',amount:1,duration:'battle'}],[{op:'modify_stacks',target:'self',stack:'heavy_armor',amount:1,duration:'end_of_turn'}],[{op:'set_stacks',target:'self',stack:'heavy_armor',amount:2,duration:'match'}],[{op:'grant_keyword',target:'self',keyword_id:'core.guard',keyword_version:1,duration:'battle'}],[{op:'grant_keyword',target:'self',keyword_id:'core.guard',keyword_version:1,duration:'end_of_turn'}],[{op:'modify_stacks',target:'self',stack:'poison',amount:1,duration:'battle'}],
 ]){
  for(const premise of [undefined,{test:'compare',left:{stat:'friendly_kredit_slots'},cmp:'gte',right:3}]){
   const ability={trigger,effects,...(premise?{premise}:{})};
   if(effects.some(e=>e.target==='chosen'))ability.target={side:'enemy',row:'any',timing:trigger==='on_play'?'deploy':'trigger'};
   add('0120/'+JSON.stringify({kind,ability}),{...base(kind),abilities:[ability]});
  }
 }
 for(const stat of ['friendly_kredit_slots','enemy_kredit_slots'])add('premise/'+stat,{...base('unit'),abilities:[{trigger:'on_play',premise:{test:'compare',left:{stat},cmp:'gte',right:5},effects:[{op:'draw',player:'owner',amount:1}]}]});
 const hq={...base('hq'),health:20,draw_rule:{base:1},abilities:[]};
 for(const trigger of ['own_counter_returned','own_kredit_slot_gained','enemy_kredit_slot_gained'])add('hq/'+trigger,{...hq,abilities:[{trigger,effects:[{op:'draw',player:'owner',amount:1}]}]});
}
const dir = await mkdtemp(join(tmpdir(), 'frontline-mechanics-parity-'));
try {
  const path = join(dir,'corpus.json'); await writeFile(path,JSON.stringify(corpus));
  const child = spawn(process.env.GODOT_BIN,['--headless','--path',root,'--script','tests/test_engine.gd'],{windowsHide:true,env:{...process.env,FRONTLINE_PARITY_INPUT:path},stdio:['ignore','pipe','pipe']});
  let output = ''; child.stdout.on('data',data => output += data); child.stderr.on('data',data => output += data);
  const timer = setTimeout(() => child.kill(),Number(process.env.PARITY_TIMEOUT_MS || 60000)); timer.unref();
  const code = await new Promise((resolve,reject) => { child.on('error',reject); child.on('exit',resolve); }); clearTimeout(timer);
  assert.equal(code,0,output); assert.match(output,new RegExp(`PARITY: ${corpus.length} checks, 0 failures`)); assert.doesNotMatch(output,/SCRIPT ERROR/);
  console.log(output.trim());
} finally { await rm(dir,{recursive:true,force:true}); }
