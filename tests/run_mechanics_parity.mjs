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
for(const counter_trigger of ['enemy_unit_deployed','enemy_order_played','enemy_hq_attacked',null,'invalid'])
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
const dir = await mkdtemp(join(tmpdir(), 'frontline-mechanics-parity-'));
try {
  const path = join(dir,'corpus.json'); await writeFile(path,JSON.stringify(corpus));
  const child = spawn(process.env.GODOT_BIN,['--headless','--path',root,'--script','tests/test_engine.gd'],{windowsHide:true,env:{...process.env,FRONTLINE_PARITY_INPUT:path},stdio:['ignore','pipe','pipe']});
  let output = ''; child.stdout.on('data',data => output += data); child.stderr.on('data',data => output += data);
  const timer = setTimeout(() => child.kill(),60000); timer.unref();
  const code = await new Promise((resolve,reject) => { child.on('error',reject); child.on('exit',resolve); }); clearTimeout(timer);
  assert.equal(code,0,output); assert.match(output,new RegExp(`PARITY: ${corpus.length} checks, 0 failures`)); assert.doesNotMatch(output,/SCRIPT ERROR/);
  console.log(output.trim());
} finally { await rm(dir,{recursive:true,force:true}); }
