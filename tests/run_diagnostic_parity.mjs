import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {compileCard} from '../server/src/validation.js';
import {freshCard,changeKind} from '../web/model.mjs';
const base={...freshCard(),name:'新机制边界'};
const corpus=[];
function add(c){let expected;try{const x=compileCard(c,{});expected={ok:true,definition_hash:x.definition_hash,compiled_program_hash:x.compiled_program_hash};}catch{expected={ok:false};}corpus.push({name:'diagnostic-'+corpus.length,definition:c,keywords:[],expected});}
for(const kind of ['unit','order','field'])for(const trigger of ['own_unit_deployed','enemy_unit_deployed','on_damaged','on_attacked','next_own_turn_start','next_opponent_turn_start','next_own_order_played','while_active'])for(const extra of [{},{limit:1},{damage_step:2}]){
 const c=changeKind(base,kind);c.abilities=[{trigger,...extra,effects:[{op:'modify_stats',target:'self',attack_delta:2,health_delta:0,duration:'battle'}]}];add(c);
}
for(const source of ['self','hand','deck','discard','starting_deck'])for(const destination of ['hand','deck','support','source_position'])for(const mode of ['copy','move']){
 const c=structuredClone(base);c.abilities=[{trigger:'on_death',effects:[{op:'transfer_card',source,destination,mode,selection:'random',amount:1,filter:{kind:'unit'}}]}];add(c);
}
for(const side of ['any','ally','enemy'])for(const row of ['any','front','support'])for(const op of ['damage','heal','destroy']){
 const c=changeKind(base,'order');c.play_target={side,row,include_hq:true};c.abilities=[{trigger:'on_play',effects:[{op,target:'chosen',...(op!=='destroy'?{amount:1}:{})}]}];add(c);
}
for(const x of [1,2,-1,0,6]){const c=structuredClone(base);c.abilities=[{trigger:'while_active',effects:[{op:'modify_stats',target:'self',attack_delta:{equipment:'剑',scale:x},health_delta:0,duration:'battle'}]}];add(c);}
for(const kind of ['unit','order','counter','field'])for(const trigger of ['on_play','on_reveal','on_death','on_damaged','while_active','next_own_turn_start'])for(const target of ['self','chosen','trigger_unit'])for(const q of [{test:'unit_keyword',keyword_id:'core.shock',state:'printed'},{test:'unit_state',state:'has_attacked'}]){
 const c=changeKind(base,kind);c.play_target=target==='chosen'?{side:'ally',row:'any'}:null;c.abilities=[{trigger,premise:{...q,target},effects:[{op:'draw',player:'owner',amount:1}]}];add(c);
}
for(const side of ['ally','enemy','any','invalid'])for(const list of [['tank'],['fighter','bomber'],[],['tank','tank'],['navy']]){const c=changeKind(base,'order');c.abilities=[{trigger:'on_play',premise:{test:'compare',left:{count_units:{side,unit_classes:list}},cmp:'gte',right:1},effects:[{op:'draw',player:'owner',amount:1}]}];add(c);}
for(const kind of ['unit','order','field'])for(const trigger of ['on_play','on_death','while_active'])for(const target of ['adjacent_to_self','adjacent_to_chosen','chosen_and_adjacent'])for(const duration of ['battle','match']){const c=changeKind(base,kind);if(['adjacent_to_chosen','chosen_and_adjacent'].includes(target)){if(trigger==='on_play')c.play_target={side:'enemy',row:'any',unit_classes:['tank']};}c.abilities=[{trigger,effects:[{op:'modify_stats',target,attack_delta:1,health_delta:0,duration}]}];add(c);}
for(const include_hq of [false,true])for(const types of [[],['tank'],['fighter','bomber'],['navy'],['tank','tank']]){const c=changeKind(base,'order');c.play_target={side:'enemy',row:'any',unit_classes:types,include_hq};c.abilities=[{trigger:'on_play',effects:[{op:'damage',target:'chosen',amount:1}]}];add(c);}
for(const name of ['high','蓄力','heavy_armor',' high','bad\n','a'.repeat(33)])for(const amount of [-99,-11,0,1,10,11,99,100])for(const op of ['modify_stacks','set_stacks']){const c=structuredClone(base);c.abilities=[{trigger:'on_play',effects:[{op,target:'self',stack:name,amount,duration:'battle'}]}];add(c);}
for(const kind of ['unit','order','field'])for(const target of ['self','chosen','trigger_unit','creator'])for(const trigger of ['on_play','on_death','on_stack_gained','while_active']){
 const c=changeKind(base,kind);if(target==='chosen')c.play_target={side:'ally',row:'any'};
 c.abilities=[{trigger,...(trigger==='on_stack_gained'?{stack:'high'}:{}),premise:{test:'compare',left:{stack_count:{target,stack:'high'}},cmp:'gte',right:3},effects:[{op:'modify_stacks',target,stack:'high',amount:1,duration:'battle'}]}];add(c);
}
for(const target of ['self','chosen','trigger_unit','creator'])for(const stat of ['attack','health','base_attack','base_health']){const c=changeKind(base,'order');if(target==='chosen')c.play_target={side:'enemy',row:'any'};c.abilities=[{trigger:'on_play',effects:[{op:'damage',target:'enemy_hq',amount:{unit_stat:{target,stat}}}]}];add(c);}
for(const deck_building of ['allowed','generated_only','invalid',false]){const c=structuredClone(base);c.deck_building=deck_building;add(c);}
for(const duration of ['match','battle','end_of_turn'])for(const target of ['self','chosen','own_hq'])for(const trigger of ['on_play','on_death']){const c=changeKind(base,'order');c.abilities=[{trigger:'on_play',effects:[{op:'discard',player:'owner',selection:'chosen',amount:1,filter:{name_contains:'集团军'}},{op:'modify_cards',player:'owner',zones:['battlefield','hand','deck'],filter:{same_as_discarded:true},duration,grant_abilities:[{trigger,effects:[{op:'damage',target,amount:1}]}]}]}];add(c);}
for(const source of ['tokens','starting_deck','deck'])for(const opts of [[],['a'],['a','b'],['a','a']]){const c=changeKind(base,'order');c.tokens=['a','b'].map(token_id=>({token_id,name:token_id,unit_class:'tank',attack:1,health:1,keywords:[]}));c.abilities=[{trigger:'on_play',effects:[{op:'develop',source,token_ids:opts}]}];add(c);}
for(const kind of ['unit','order','field'])for(const trigger of ['after_attack','after_move','after_action','own_unit_died','enemy_unit_died'])for(const target of ['self','trigger_unit','all_friendly_units']){const c=changeKind(base,kind);c.abilities=[{trigger,effects:[{op:'modify_operation_cost',target,cost_delta:1,duration:'battle'}]}];add(c);}
for(const op of [{op:'set_combat_priority',applies_to:'both'},{op:'grant_unit_class',unit_class:'fighter'},{op:'modify_incoming_damage',amount:2,damage_kind:'both'},{op:'modify_incoming_damage',amount:0,damage_kind:'both'},{op:'grant_order_target_reward',amount:1}])for(const include_hq of [true,false]){const c=changeKind(base,'order');c.play_target={side:'enemy',row:'any',include_hq};c.abilities=[{trigger:'on_play',effects:[{...op,target:'chosen',duration:'end_of_turn'}]}];add(c);}
const directory=mkdtempSync(join(tmpdir(),'chao-diagnostic-parity-'));
try{
 const path=join(directory,'corpus.json');writeFileSync(path,JSON.stringify(corpus));
 const root=fileURLToPath(new URL('..',import.meta.url));
 const r=spawnSync(process.env.GODOT_BIN,['--headless','--path',root,'--script','tests/test_engine.gd'],{windowsHide:true,env:{...process.env,FRONTLINE_PARITY_INPUT:path},encoding:'utf8',timeout:60000});
 const output=r.stdout+r.stderr;assert.equal(r.status,0,output);assert.match(output,new RegExp(`PARITY: ${corpus.length} checks, 0 failures`));assert(!output.includes('SCRIPT ERROR'),output);console.log(output.trim());
}finally{rmSync(directory,{recursive:true,force:true});}
