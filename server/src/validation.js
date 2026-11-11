import {shortText} from '../../web/card_text.mjs';
import {compactRules} from './rules_compact.js';
import Ajv from 'ajv';
import {validatePremise, premiseText, premiseUnitQueries, unitClassText,unitCountText,validStackName,unitValue,unitValueText,filterDetail, maxUnitStatText} from './premises.js';
import {readFileSync} from 'node:fs';
import {canonical, normalize, hash, fail} from './codec.js';
import {discriminate, diagnose} from './schema_diagnostics.js';

export const docsURL = new URL('../../docs/cards/', import.meta.url);
export const schemas = Object.fromEntries(['card', 'keyword', 'generation', 'keyword-generation', 'mechanism-review'].map(name => [name, JSON.parse(readFileSync(new URL(`${name}.schema.json`, docsURL), 'utf8'))]));
const ajv = new Ajv({allErrors: true, strict: false, coerceTypes: false, removeAdditional: false, discriminator: true});
for (const schema of Object.values(schemas)) ajv.addSchema(discriminate(schema));
export function schemaCheck(name, value) {
  const validate = ajv.getSchema(schemas[name].$id);
  if (!validate(value)) {
    const details=diagnose(validate.errors, value);
    fail('INVALID_SCHEMA', details.map(e=>e.message).join('\n'), 422, details);
  }
}
const effectValidator = ajv.compile({$ref: schemas.card.$id + '#/definitions/effect'});
export const builtinDefinitions = JSON.parse(readFileSync(new URL('builtin_keywords.json', docsURL), 'utf8'));
const builtinIds = new Set(['core.blitz', 'core.guard',...builtinDefinitions.map(d=>d.id)]);
const builtinVersions = new Set(['core.blitz.v1','core.guard.v1',...builtinDefinitions.map(d=>d.implementation.builtin_id)]);
const plainText = (text, path, newline = false) => {
  if ((newline ? /[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/ : /[\u0000-\u001f\u007f-\u009f]/).test(text)) fail('SEMANTIC_VALIDATION_FAILED', '名称和说明中不能包含控制字符。', 422, [{code: 'CONTROL_CHARACTER', path, message: '请使用纯文本。'}]);
};
const validParameter=(value,range)=>range.type==='token'?typeof value==='string'&&/^[a-z][a-z0-9_]{0,31}$/.test(value):Number.isInteger(value)&&value>=range.minimum&&value<=range.maximum;
const refAbilities=(def,ref)=>def.implementation.kind==='configurable'?ref.abilities:substitute(def.implementation.abilities,ref.params);
const pendingRef=ref=>Array.isArray(ref.abilities)&&ref.abilities.length===0;
function validateRefAbilities(def,ref){
 if(def.implementation.kind==='configurable'){
  if(!Array.isArray(ref.abilities)||!ref.abilities.length)fail('INVALID_KEYWORD_PARAMS','请为本卡填写「'+def.name+'」的触发、前提与效果。');
 }else if(ref.abilities!==undefined)fail('INVALID_KEYWORD_PARAMS','仅逐卡配置词条可填写独立效果。');
}
export const unboundEffects=effects=>effects.flatMap(e=>['if_drawn','if_killed','schedule'].includes(e.op)?unboundEffects(e.effects):e.op==='choose_effect'?e.options.filter(o=>!o.target).flatMap(o=>unboundEffects(o.effects)):[e]);
export const walkEffects=effects=>effects.flatMap(e=>[e,...(['if_drawn','if_killed','schedule'].includes(e.op)?walkEffects(e.effects):e.op==='choose_effect'?e.options.flatMap(o=>walkEffects(o.effects)):[])]);
const scopedEffects=(effects,trigger)=>effects.flatMap(effect=>[{effect,trigger},...(['if_drawn','if_killed','schedule'].includes(effect.op)?scopedEffects(effect.effects,effect.op==='schedule'?effect.trigger:trigger):effect.op==='choose_effect'?effect.options.flatMap(o=>scopedEffects(o.effects,trigger)):[])]);
const leaves=effects=>walkEffects(effects).filter(e=>!['choose_effect','if_drawn','if_killed','schedule'].includes(e.op));
function effectPaths(effects){let paths=[[]];for(const e of effects)paths=e.op==='choose_effect'?paths.flatMap(p=>e.options.map(o=>[...p,...(o.target?[]:o.effects)])):paths.map(p=>[...p,e]);return paths;}
const effectChooses=e=>['chosen','adjacent_to_chosen','chosen_and_adjacent'].includes(e.target)||[e.amount,e.attack_delta,e.health_delta,e.value].some(v=>unitValue(v)?.target==='chosen');
const eventTriggers=['on_keyword_lost','own_unit_deployed','enemy_unit_deployed','own_order_played','enemy_order_played','own_card_played','enemy_card_played','after_attacked','own_unit_moved','enemy_unit_moved','on_kill','on_attacked','on_damaged','on_stack_gained','after_attack','after_move','after_action','own_unit_died','enemy_unit_died','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave'];
const keywordAura=a=>a.premise?.test==='unit_keyword'&&a.premise.target==='self'&&a.effects.every(e=>e.op==='modify_stats'&&e.target==='self'&&e.health_delta===0&&Number.isInteger(e.attack_delta));
const positionQuery=q=>q.test==='unit_state'&&q.target==='self'&&['in_front','in_support'].includes(q.state);
function extendedSemantics(a,body){
 if(a.trigger==='on_keyword_lost'){if(!builtinIds.has(a.keyword_id)||body&&body.kind!=='unit')fail('SEMANTIC_VALIDATION_FAILED','失去词条事件需要单位及有效基础词条。');}else if(a.keyword_id!==undefined)fail('SEMANTIC_VALIDATION_FAILED','事件词条仅用于失去词条时。');
 for(let i=0;i<a.effects.length;i++){
  const e=a.effects[i],prior=a.effects.slice(0,i);
  if(e.op==='select_units'&&(e.min>e.max||prior.some(x=>x.op==='select_units')||a.trigger==='while_active'))fail('SEMANTIC_VALIDATION_FAILED','每组最多一次多选，最少数量不得超过最多数量。');
  if(e.target==='selected_units'&&!prior.some(x=>x.op==='select_units'))fail('SEMANTIC_VALIDATION_FAILED','请先在本组选择多个单位。');
  if(e.amount?.stat==='selected_destroyed_count'&&!prior.some(x=>x.op==='destroy'&&x.target==='selected_units'))fail('SEMANTIC_VALIDATION_FAILED','数量需要本组先消灭所选单位。');
  if(e.source==='attack_target'&&(e.mode!=='copy'||!['after_attack','on_attack'].includes(a.trigger)))fail('SEMANTIC_VALIDATION_FAILED','被攻击单位仅能在主动攻击时或之后复制。');
  if(e.copy_state!==undefined&&(e.source!=='attack_target'||e.mode!=='copy'||e.inherit_from))fail('SEMANTIC_VALIDATION_FAILED','当前攻防复制仅用于被攻击单位，不混用强化来源筛选。');
 }

 if(a.zone==='hand'&&(!['enemy_unit_died','own_unit_died'].includes(a.trigger)||body&&body.kind!=='unit'||a.target||a.effects.some(e=>e.op!=='modify_hand_cost'||e.selection!=='self')))fail('SEMANTIC_VALIDATION_FAILED','手牌监听仅支持己方/敌方单位阵亡时修改本卡手牌费用。');
 if(a.effects.some(e=>e.op==='modify_hand_cost'&&e.selection==='self')&&a.zone!=='hand')fail('SEMANTIC_VALIDATION_FAILED','本卡手牌费用需使用手牌区域监听。');
 for(const e of a.effects){if(e.op==='become_trigger_unit'&&a.trigger!=='on_kill')fail('SEMANTIC_VALIDATION_FAILED','复制被消灭单位形态仅用于本单位消灭敌方单位时。');if(e.op==='transfer_card'&&e.source==='event_card'&&(e.mode!=='copy'||!['on_kill','own_unit_died','enemy_unit_died'].includes(a.trigger)))fail('SEMANTIC_VALIDATION_FAILED','事件卡仅能在击杀或阵亡事件中复制。');}
 const invalid=m=>fail('SEMANTIC_VALIDATION_FAILED',m);
 if(a.trigger==='on_activate'){
  if(body&&body.kind!=='unit'||a.zone==='hand'||a.limit!==1||a.limit_scope!=='turn')invalid('主动能力仅供场上单位使用，须设置每回合一次。');
  if(a.target&&a.target.timing!=='trigger')invalid('主动能力发动时选择目标。');
  if(premiseUnitQueries(a.premise).some(q=>q.target!=='self'))invalid('主动能力发动前的前提不能读取未选择的目标或事件单位。');
 }
 if(a.trigger==='when_condition'){
  if(!a.premise||body&&body.kind!=='unit')invalid('满足条件时需要单位及明确前提。');
  if(a.limit!==undefined||a.limit_scope!==undefined||a.occurrence!==undefined)invalid('满足条件时每次在场只触发一次，不另设次数。');
  if(a.target&&a.target.timing!=='trigger')invalid('满足条件时需要触发时选择目标。');
  if(premiseUnitQueries(a.premise).some(q=>q.target!=='self')||/"(?:event_damage|source_destroyed_count|destroyed_by)"/.test(JSON.stringify(a.premise)))invalid('满足条件时只查询场上状态，不读取尚未发生的事件或所选目标。');
 }
 if(a.occurrence!==undefined&&(!eventTriggers.includes(a.trigger)||a.trigger==='on_leave'))invalid('第几次仅用于事件监听。');
 if(a.trigger==='on_leave'&&(a.limit!==undefined||a.limit_scope!==undefined))invalid('离场时仅触发一次，不设置次数限制。');
 if(a.limit_scope!==undefined&&a.limit===undefined)invalid('每回合次数限制须填写次数。');
 if(JSON.stringify(a.premise)?.includes('destroyed_by')&&a.trigger!=='on_death')invalid('击杀者兵种前提只能用于阵亡。');
 if(JSON.stringify(a.premise)?.includes('source_destroyed_count')&&!['on_play','after_attack','after_action'].includes(a.trigger))invalid('该时机没有本次消灭数。');
 for(const e of a.effects){
  if(e.op==='modify_stats'&&e.health_mode==='max_only'&&(!(typeof e.health_delta==='number')||e.health_delta===0))invalid('防御上限变化需要非零整数。');
  if(e.op==='temporarily_remove'&&e.return_when==='source_leaves'&&body&&body.kind!=='unit')invalid('来源离场归还需要单位来源。');
  if(e.op==='temporarily_remove'&&e.return_cost!==undefined&&e.destination!=='hand')invalid('归还费用仅用于返回手牌。');
  if(e.op==='summon_origin'&&body&&body.kind!=='unit')invalid('召唤原型仅用于单位。');
  if(e.target==='attack_target'&&!(['on_attack','after_attack','after_action'].includes(a.trigger)||a.trigger==='on_reveal'&&(!body||body.counter_trigger==='enemy_unit_attacked')))invalid('该时机没有攻击目标。');
  for(const v of [e.amount,e.attack_delta,e.health_delta,e.value]){
   if(v?.unit_stat?.target==='attack_target'&&!(['on_attack','after_attack','after_action'].includes(a.trigger)||a.trigger==='on_reveal'&&(!body||body.counter_trigger==='enemy_unit_attacked')))invalid('该时机没有攻击目标。');
   if((v?.unit_stat??v?.keyword_param)?.target==='effect_target'&&!['set_attack','damage','heal','modify_stats','modify_stacks','set_stacks'].includes(e.op))invalid('结算目标属性仅用于设置攻击力。');
  }
  if(e.op==='schedule'){
   if(e.repeat==='each_event'&&!['next_own_unit_deployed','next_own_order_played','next_own_unit_entered','next_own_unit_attacked_hq'].includes(e.trigger))invalid('每次事件监听需要事件时机。');
   if(e.repeat==='each_turn'&&!['next_own_turn_start','next_opponent_turn_start'].includes(e.trigger))invalid('每回合监听需要回合时机。');
   if(e.after_turns!==undefined&&!['next_own_turn_start','next_opponent_turn_start'].includes(e.trigger))invalid('事件监听不设置回合延迟。');
  }
  if(e.op==='grant_ability'){
   if(e.ability.effects.some(x=>x.on_kill_summon))invalid('附加能力不使用来源卡衍生模板。');
   semantics({...body,kind:'unit',abilities:[e.ability],play_target:null,tokens:[],keywords:[]},false,false,true);
  }
 }
 if(a.after_turns!==undefined&&!['next_own_turn_start','next_opponent_turn_start'].includes(a.trigger))fail('SEMANTIC_VALIDATION_FAILED','延迟回合数仅用于后续回合开始。');
 for(const e of a.effects)if(['if_drawn','if_killed','schedule'].includes(e.op)){
  if(e.op==='schedule'){
   if(a.trigger==='while_active')fail('SEMANTIC_VALIDATION_FAILED','延迟效果不能放入持续光环。');
   if(e.lifetime==='source'&&body&&body.kind!=='unit')fail('SEMANTIC_VALIDATION_FAILED','来源在场期限需要单位。');
   if(e.lifetime==='target'&&!leaves(e.effects).some(effectChooses))fail('SEMANTIC_VALIDATION_FAILED','目标在场期限需要绑定 chosen。');
   if(e.times!==undefined&&!['each_turn','each_event'].includes(e.repeat))fail('SEMANTIC_VALIDATION_FAILED','重复次数仅用于每回合延迟效果。');
  }
  extendedSemantics(e.op==='schedule'?{trigger:e.trigger,effects:e.effects,_scheduled:true}:{...a,effects:e.effects},body);
 }
 for(const path of effectPaths(a.effects))for(let i=0;i<path.length;i++)if(path[i].op==='if_killed'&&!path.slice(0,i).some(e=>e.op==='damage'))fail('SEMANTIC_VALIDATION_FAILED','击杀结果须跟在同一效果组的伤害操作之后。');

 if(a.repeat!==undefined){
  if(a.trigger==='while_active')fail('SEMANTIC_VALIDATION_FAILED','持续光环不能重复结算。');
  if(a.repeat?.count_units)validatePremise({test:'compare',left:a.repeat,cmp:'gte',right:0});
 }

 const choices=a.effects.filter(e=>e.op==='choose_effect');
 if(choices.length){
  if(choices.length>1||a.trigger==='while_active')fail('SEMANTIC_VALIDATION_FAILED','每个非持续效果组最多一次抉择。');
  for(const e of choices)for(const o of e.options){if(o.premise)validatePremise(o.premise);plainText(o.label,'/options/label');if(o.effects.some(x=>x.op==='choose_effect'))fail('SEMANTIC_VALIDATION_FAILED','抉择不能嵌套。');}
  for(const e of choices)for(const o of e.options)if(o.target){if(!o.effects.some(effectChooses))invalid('分支目标需要对应选定目标效果。');semantics({...body,kind:body?.kind??'order',abilities:[{trigger:'on_play',target:o.target,effects:o.effects,...(o.target?{target:o.target}:{})}],play_target:null,tokens:body?.tokens??[],keywords:[]},false,false,true);}
  for(const effects of effectPaths(a.effects))extendedSemantics({...a,effects},body);
  return;
 }
 for(const e of a.effects)if(e.unit_filter){
  if(['own_hq','enemy_hq'].includes(e.target))fail('SEMANTIC_VALIDATION_FAILED','单位筛选仅用于触发效果的单位目标。');
  for(const k of ['card_name','name_contains'])if(e.unit_filter[k]!==undefined){plainText(e.unit_filter[k],'/unit_filter/'+k);if(!e.unit_filter[k].trim()||e.unit_filter[k]!==e.unit_filter[k].trim())fail('SEMANTIC_VALIDATION_FAILED','单位名称筛选不能含首尾空格。');}
 }

 const bad=m=>fail('SEMANTIC_VALIDATION_FAILED',m);
 for(const e of a.effects)if(e.op==='transfer_card'&&e.copy_buff){
  if(e.mode!=='copy'||!['support','source_position'].includes(e.destination))bad('复制强化仅用于将复制单位召唤到场上。');
  if(e.copy_buff.attack_delta===0&&e.copy_buff.health_delta===0)bad('复制强化不能同时为零。');
 }
 if(['after_attack','after_move','after_action','on_attack','on_veteran','on_leave'].includes(a.trigger)&&body&&body.kind!=='unit')bad('行动后时机只能用于单位。');
 if(a.trigger==='on_stack_gained'){
  if(!validStackName(a.stack)||body&&body.kind!=='unit')bad('获得层数事件需要单位与明确的层数名称。');
 }else if(a.stack!==undefined)bad('层数名称只用于获得层数事件。');
 for(const e of a.effects){
  if(e.op==='prepare_counter'&&e.duration==='battle'&&body&&body.kind!=='unit')bad('在场期间的反制预备需要单位。');
  if(e.op==='return_to_hand'&&((e.cost_delta!==undefined)!==(e.duration!==undefined)||e.cost_delta===0))bad('回手费用变化需同时指定非零费用变化和持续时间。');
  if(e.op==='modify_hand_cost'&&e.cost_delta===0)bad('费用变化不能为零。');
  if(e.op==='modify_hand_cost')for(const k of ['card_name','name_contains'])if(e.filter?.[k]){plainText(e.filter[k],'/filter/'+k);if(e.filter[k]!==e.filter[k].trim())bad('卡名筛选不能带首尾空格。');}
  if(e.op==='modify_incoming_damage'&&e.amount===0&&!e.multiplier&&!e.immune)bad('受到伤害的变化不能为零。');
  if(['modify_stacks','set_stacks'].includes(e.op)){
   if(!validStackName(e.stack))bad('层数名称需为1—32字，不能含首尾空格或控制字符。');
   if(typeof e.amount==='number'&&Math.abs(e.amount)>(e.stack==='heavy_armor'?100:99))bad(e.stack==='heavy_armor'?'重甲层数操作范围为-100至100。':'自定义层数操作范围为-99至99。');
   if(a.trigger==='while_active'&&e.stack!=='heavy_armor')bad('自定义层数是计数状态，请通过触发操作增减，不能作为持续光环。');
  }
  if(['shuffle_into_deck','tax_opponent_plays','forbid_deploy','remove_keyword'].includes(e.op)&&a.trigger==='while_active')bad('洗入牌库、征收费用、禁止部署和失去词条是一次性效果，不能作为持续光环。');
  if(e.op==='modify_operation_cost'&&e.per_stack&&e.cost_delta===undefined)bad('按层数修改行动费需要 cost_delta。');
  if(e.op==='modify_operation_cost'&&e.per_stack&&a.trigger==='while_active')bad('按层数修改行动费不能作为持续光环。');
  if(e.op==='temporarily_remove'&&e.return_when==='immediate'&&e.after_turns!==undefined)bad('立即返回不设置回合延迟。');
  if(e.op==='remove_hand'&&(!e.card_name.trim()||e.card_name!==e.card_name.trim()))bad('移除手牌需填写准确卡名。');
  if(e.op==='remove_hand')plainText(e.card_name,'/effects/card_name');
  for(const v of [e.amount,e.attack_delta,e.health_delta,e.value,e.per_stack?{stack_count:e.per_stack}:undefined])if(unitValue(v)){
   const q=unitValue(v);
   if(v.stack_count&&!validStackName(q.stack))bad('层数名称无效。');
   if(a.trigger==='while_active'&&!(v.stack_count&&q.target==='self'&&e.op==='modify_stats'&&v!==e.amount))bad('持续光环只能用自身的自定义层数修改攻防，不能读取单位当前属性。');
   if(q.target==='self'&&body&&body.kind!=='unit')bad('该卡没有自身单位可读取。');
   if(q.target==='chosen'&&body&&!(a.target??body?.play_target))bad('读取所选单位需要选择目标。');
   if(q.target==='chosen'&&(a.target??body?.play_target)?.include_hq)bad('单位数值读取不能包含总部。');
   if(q.target==='trigger_unit'&&!['own_unit_deployed','next_own_unit_deployed','enemy_unit_deployed','after_attacked','own_unit_moved','enemy_unit_moved','on_kill','on_attacked','on_damaged','on_stack_gained','after_attack','after_move','after_action','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave'].includes(a.trigger))bad('此事件没有可读取的触发单位。');
  }
 }

 for(const s of [a.target,body?.play_target])if((s?.unit_classes||s?.faction_id)&&s.include_hq)bad('兵种目标不能同时选择总部。');
 for(const e of a.effects){
  if(e.target==='adjacent_to_self'&&body&&body.kind!=='unit')bad('自身相邻目标需要来源单位。');
  if(['adjacent_to_chosen','chosen_and_adjacent'].includes(e.target)&&(a.target??body?.play_target)?.include_hq)bad('相邻效果的中心目标必须是单位。');
 }

 for(const q of premiseUnitQueries(a.premise)){
  if(a.trigger==='while_active'&&!keywordAura(a)&&!positionQuery(q))bad('持续状态前提支持自身前线/后援线位置；自身词条条件仅用于固定攻击力光环。');
  if(q.target==='chosen'&&(a.trigger!=='on_play'||a.target||body&&(!body.play_target||body.play_target.include_hq)))bad('所选单位状态前提需要登场共用 play_target，且不包含总部。');
  if(q.target==='self'&&(['on_death','on_reveal'].includes(a.trigger)||body&&body.kind!=='unit'))bad('自身状态前提需要仍在场的来源单位。');
  if(q.target==='trigger_unit'&&(!['on_reveal','own_unit_deployed','next_own_unit_deployed','enemy_unit_deployed','after_attacked','own_unit_moved','enemy_unit_moved','on_kill','on_attacked','on_damaged','on_stack_gained','after_attack','after_move','after_action','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave'].includes(a.trigger)||a.trigger==='on_reveal'&&body?.counter_trigger==='enemy_order_played'))bad('此事件没有可查询的触发单位。');
 }
 if(a.damage_step!==undefined && a.trigger!=='on_damaged')bad('累计损伤阈值仅用于受伤后触发。');
 if(a.limit!==undefined && a.trigger!=='on_activate' && !eventTriggers.includes(a.trigger))bad('次数限制用于事件监听；延迟效果固定只执行一次。');
 if(!a._scheduled&&a.trigger.startsWith('next_') && body && body.kind!=='order')bad('预留的下一次效果仅用于指令；单位请使用在场事件。');
 if(a.target && (a.trigger.startsWith('next_')||eventTriggers.includes(a.trigger)) && (a.target.timing??'deploy')!=='trigger')bad('事件目标须在触发时选择。');
 if(a.event_scope&&!['own_unit_moved','own_unit_retreated','own_unit_returned','own_unit_attacked','own_unit_entered','own_unit_deployed','own_unit_died'].includes(a.trigger))bad('自身/其他事件筛选仅用于友方单位事件。');
 for(const e of a.effects){
  if(e.op==='unit_limit'&&(a.trigger!=='while_active'||body&&body.kind!=='field'))bad('单位数量上限仅用于场地持续效果。');
  if(e.op==='liberate'&&(body&&body.kind!=='unit'||['on_death','on_leave','on_reveal','while_active'].includes(a.trigger)))bad('解放需要仍在场的单位。');
  if(e.op==='transfer_card'&&e.entry&&!(e.source==='deck'&&e.mode==='move'&&e.destination==='support'))bad('部署方式仅用于从牌库移动单位到后援线。');
 }
 if(a.trigger==='while_active'){
   if(!keywordAura(a)&&(/keyword_id|attack|health/.test(JSON.stringify(a.premise??{}))||premiseUnitQueries(a.premise).some(q=>!positionQuery(q))))bad('持续条件不能读取光环可改变的属性或词条。');
   if(a.limit||a.damage_step||a.target)bad('持续效果不能包含次数或目标选择。');
   if(a.premise){const stats=JSON.stringify(a.premise).match(/"stat":"([^"]+)"/g)||[];if(stats.some(x=>!/(?:enemy|friendly)_(?:unit|front|support)_count|other_friendly_unit_count/.test(x)))bad('持续条件仅允许战场单位与战线计数。');}
   for(const e of a.effects){
    if(e.op==='unit_limit')continue;
    if(e.op==='modify_stats'&&e.target==='self'&&e.health_delta!==0)bad('自身持续攻防效果仅改变攻击力。');
    if(e.unit_filter&&Object.keys(e.unit_filter).some(k=>['attack','health','keyword_id','without_keyword','attack_parity'].includes(k)))bad('光环筛选不能读取可被光环改变的属性或词条。');
    if(!((!body||body.kind==='unit')&&e.op==='modify_stats'&&e.target==='self'&&e.health_delta===0)&&['attack_delta','health_delta','amount'].some(k=>e[k]&&typeof e[k]==='object'))bad('光环只支持固定数值。');
    if(['self','adjacent_to_self','all_other_friendly_units'].includes(e.target)&&body&&body.kind!=='unit')bad('自身或相邻光环需要单位来源。');
    if(['own_hq','enemy_hq'].includes(e.target)&&e.op!=='modify_incoming_damage')bad('总部光环仅支持受伤修正。');
    if(a.premise&&e.op==='modify_stats'&&e.health_delta!==0)bad('条件光环不改变防御。');
   }
 }
 for(let index=0;index<a.effects.length;index++){
  const e=a.effects[index];
  if(['discard','modify_cards','develop'].includes(e.op))for(const k of ['card_name','name_contains'])if(e.filter?.[k]){plainText(e.filter[k],'/effects/filter/'+k);if(e.filter[k]!==e.filter[k].trim())bad('卡名筛选不能带首尾空格。');}
  if(e.op==='develop'&&((e.source==='tokens')!==!!e.token_ids||e.source==='tokens'&&e.filter))bad('衍生卡开发需要 token_ids；起始牌组开发只能使用 filter。');
  if(e.op==='modify_cards'){
   if(e.filter.kind&&e.filter.kind!=='unit')bad('跨区域强化仅用于单位卡。');
   if(e.filter.same_as_discarded&&!a.effects.slice(0,index).some(x=>x.op==='discard'&&x.amount===1))bad('同名强化需要同一效果组先弃置恰好一张手牌。');
   if(![e.attack_delta,e.health_delta,e.operation_cost_delta].some(v=>v)&&!e.grant_abilities?.length)bad('强化需至少有一项属性变化或附加能力。');
   for(const ability of e.grant_abilities??[])semantics({...body,kind:'unit',abilities:[ability],play_target:null,tokens:[],keywords:[]},false,false,true);
  }
 }
 for(const e of a.effects){
  if(e.on_kill_summon&&(['own_hq','enemy_hq'].includes(e.target)||(e.target==='chosen'&&(a.target??body?.play_target)?.include_hq)))bad('击杀后召唤仅支持单位目标。');
   if(e.op==='transfer_card'){
   if(e.fallback_sources!==undefined&&(e.mode!=='copy'||e.destination!=='hand'||!['deck','discard','hand'].includes(e.source)||e.fallback_sources.includes(e.source)))bad('后备来源仅用于从牌库、弃牌区或手牌复制到手牌，来源不能重复。');
   if(e.player==='opponent'&&!['deck','hand','discard','starting_deck'].includes(e.source))bad('对方来源只允许明确卡池。');
   if(e.deck_position!==undefined&&e.destination!=='deck')bad('牌库位置仅用于放入牌库。');
   if(e.overflow!==undefined&&e.destination!=='hand')bad('满手牌改放牌库顶仅用于加入手牌。');
   if(e.selection==='chosen'&&!['deck','hand','discard','starting_deck'].includes(e.source))bad('手选卡牌需要明确的卡池。');
   if(e.inherit_from!==undefined&&e.mode!=='copy')bad('强化继承筛选仅用于复制。');
   if(e.inherit_from&&new Set(e.inherit_from.map(r=>r.card_id)).size!==e.inherit_from.length)bad('强化来源不能重复。');
   if(e.source==='starting_deck'&&e.mode!=='copy')bad('起始牌组池只能复制。');
   if(e.source==='self'&&e.mode==='move'&&(a.trigger!=='on_death'||!['hand','deck'].includes(e.destination)||e.amount!==1||e.filter||e.selection!=='random'||body&&body.kind!=='unit'))bad('原卡回手仅用于单位阵亡，移动自身一张到手牌，不设筛选。');
   if(e.source==='drawn'&&e.mode!=='move')bad('本次抽牌只能移动，不能复制。');
   if(e.destination==='source_position'&&body?.kind!=='unit'&&body)bad('原位置召唤需要来源单位。');
   if(e.filter?.min_cost>e.filter?.max_cost)bad('最低费用不能大于最高费用。');
   if((e.filter?.event_faction||e.filter?.event_cost_distance!==undefined)&&!['own_order_played','enemy_order_played','own_card_played','enemy_card_played','next_own_order_played','next_own_unit_deployed','own_unit_deployed','enemy_unit_deployed','own_unit_died','enemy_unit_died','after_action','after_attack','after_move','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave'].includes(a.trigger))bad('事件卡筛选只能在打出卡牌事件中使用。');
   if(e.filter?.card_name)plainText(e.filter.card_name,'/abilities/effects/filter/card_name');
  }
  if(['equip','unequip'].includes(e.op))plainText(e.tag,'/abilities/effects/tag');
 }
 if(a.target?.include_hq&&a.target.row!=='any')bad('总部目标的战线须选任意。');
 if(a.target?.include_hq&&leaves(a.effects).some(e=>['chosen','adjacent_to_chosen','chosen_and_adjacent'].includes(e.target)&&!['damage','heal','modify_incoming_damage','grant_order_target_reward'].includes(e.op)))bad('总部目标仅允许伤害或治疗。');
}
const effectCount=a=>walkEffects(a.effects).reduce((n,e)=>n+1+(e.on_kill_summon?1:0)+(e.op==='grant_ability'?e.ability.effects.length:0)+(e.grant_abilities??[]).reduce((m,g)=>m+g.effects.length,0),0);
const semantics = (definition, template = false, allowEmptyOrder = false, tokenBody = false, allowUnusedTokens = false) => {
  const abilities = template ? definition : definition.abilities;
  if (abilities.length > 8 || abilities.reduce((sum, a) => sum + effectCount(a), 0) > 24) fail('RULE_BUDGET_EXCEEDED', '展开后最多 8 个能力、24 条操作。');
  let chosen = false; const usedTokens = new Set(definition?.veteran?[definition.veteran.token_id]:[]);
  for (const [ai, ability] of abilities.entries()) {
    if(!template&&definition.kind==='hq'){
      if(!['while_active','own_turn_start','own_turn_end','opponent_turn_start','opponent_turn_end','own_unit_deployed','enemy_unit_deployed','own_order_played','enemy_order_played','own_card_played','enemy_card_played','own_unit_died','enemy_unit_died','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave'].includes(ability.trigger))fail('SEMANTIC_VALIDATION_FAILED','总部支持驻场、回合、部署、指令和阵亡事件。');
      if(ability.target&&(ability.target.timing??'deploy')!=='trigger')fail('SEMANTIC_VALIDATION_FAILED','总部效果的目标需要触发时选择。');
    }

    if (!template && ability.trigger==='while_active' && !['field','unit','hq'].includes(definition.kind)) fail('SEMANTIC_VALIDATION_FAILED','此时机仅用于场地卡。');
    if (!template && definition.kind==='field' && !['on_play','while_active','own_turn_start','own_turn_end','opponent_turn_start','opponent_turn_end','own_unit_died','enemy_unit_died'].includes(ability.trigger)) fail('SEMANTIC_VALIDATION_FAILED','场地支持登场、回合时机和持续效果。');
    if (!template && definition.kind==='field' && ability.target && (ability.target.timing??'deploy')!=='trigger') fail('SEMANTIC_VALIDATION_FAILED','场地的效果组选定目标请使用触发时选择。');
    if(ability.premise){validatePremise(ability.premise);if(premiseUnitQueries(ability.premise).some(q=>q.target==='chosen'))chosen=true;}
    extendedSemantics(ability,template?null:definition);
    const hasChosen=unboundEffects(ability.effects).some(effectChooses);
    if (Object.hasOwn(ability,'target') && (!['on_play','on_reveal','on_death','on_summon','own_turn_start','own_turn_end','opponent_turn_start','opponent_turn_end','next_own_turn_start','next_opponent_turn_start','next_own_order_played','next_own_unit_deployed','own_unit_deployed','enemy_unit_deployed','own_order_played','enemy_order_played','own_card_played','enemy_card_played','after_attacked','own_unit_moved','enemy_unit_moved','on_kill','on_attacked','on_damaged','on_stack_gained','after_attack','after_move','after_action','own_unit_died','enemy_unit_died','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave','when_condition','on_activate'].includes(ability.trigger)||!hasChosen) || ['on_reveal','on_death','on_summon','own_turn_start','own_turn_end','opponent_turn_start','opponent_turn_end','next_own_turn_start','next_opponent_turn_start','next_own_order_played','next_own_unit_deployed','own_unit_deployed','enemy_unit_deployed','own_order_played','enemy_order_played','own_card_played','enemy_card_played','after_attacked','own_unit_moved','enemy_unit_moved','on_kill','on_attacked','on_damaged','on_stack_gained','after_attack','after_move','after_action','own_unit_died','enemy_unit_died','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave','when_condition','on_activate'].includes(ability.trigger)&&hasChosen&&!ability.target) fail('SEMANTIC_VALIDATION_FAILED','延后触发的 chosen 必须填写效果组 target；仅允许目标选择时机使用。');
    if (!template && definition.kind === 'counter' && ability.trigger !== 'on_reveal') fail('SEMANTIC_VALIDATION_FAILED', '反制只能具有触发时效果。');
    if (!template && definition.kind !== 'counter' && ability.trigger === 'on_reveal') fail('SEMANTIC_VALIDATION_FAILED', '触发时效果只能用于反制。');
    if (!template && definition.kind === 'order' && !['on_play','next_own_turn_start','next_opponent_turn_start','next_own_order_played','next_own_unit_deployed'].includes(ability.trigger)) fail('SEMANTIC_VALIDATION_FAILED', '指令支持使用时和预留的下一次触发。');
    for (const [ei, {effect,trigger:effectTrigger}] of scopedEffects(ability.effects,ability.trigger).entries()) {
      if (!effectValidator(effect)) fail('SEMANTIC_VALIDATION_FAILED', '展开后的效果数值或结构无效。', 422, [{path: `/abilities/${ai}/effects/${ei}`, code: 'INVALID_EFFECT', message: '检查参数全部允许值是否都在该指令范围内。'}]);
      if (ability.trigger==='while_active' && effect.op!=='unit_limit' && (!['modify_stats','modify_operation_cost','modify_stacks','grant_keyword','modify_incoming_damage'].includes(effect.op)||!['self','all_units','all_friendly_units','all_other_friendly_units','all_enemy_units','adjacent_to_self','own_hq','enemy_hq'].includes(effect.target)||effect.duration!=='battle'||effect.op==='grant_keyword'&&!['core.guard','core.blitz','core.fury','core.immune'].includes(effect.keyword_id))) fail('SEMANTIC_VALIDATION_FAILED','场地持续效果支持所有友方/敌方单位的固定攻防、行动费或重甲变化，持续时间选本次在场期间。');
      if(effect.op==='set_combat_damage_multiplier' && (effect.divisor??1)>1 && !effect.rounding)fail('SEMANTIC_VALIDATION_FAILED','分数伤害需要指定向上或向下取整。');
      if (effect.target === 'trigger_unit' && (!['on_reveal','own_unit_deployed','next_own_unit_deployed','enemy_unit_deployed','after_attacked','own_unit_moved','enemy_unit_moved','on_kill','on_attacked','on_damaged','on_stack_gained','after_attack','after_move','after_action','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave'].includes(effectTrigger) || (effectTrigger==='on_reveal' && !template && definition.counter_trigger === 'enemy_order_played'))) fail('SEMANTIC_VALIDATION_FAILED', '触发单位仅用于部署单位或攻击总部的反制。');
      if (effect.op === 'cancel_action' && (effectTrigger !== 'on_reveal' || (!template && definition.counter_trigger === 'enemy_unit_deployed'))) fail('SEMANTIC_VALIDATION_FAILED', '取消行动仅用于打出指令或攻击总部的反制。');
      if (unboundEffects(ability.effects).includes(effect) && effectChooses(effect)) { if (ability.trigger === 'on_play' && !ability.target) chosen = true; else if (!['on_play','on_reveal','on_death','on_summon','own_turn_start','own_turn_end','opponent_turn_start','opponent_turn_end','next_own_turn_start','next_opponent_turn_start','next_own_order_played','next_own_unit_deployed','own_unit_deployed','enemy_unit_deployed','own_order_played','enemy_order_played','own_card_played','enemy_card_played','after_attacked','own_unit_moved','enemy_unit_moved','on_kill','on_attacked','on_damaged','on_stack_gained','after_attack','after_move','after_action','own_unit_died','enemy_unit_died','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave','when_condition','on_activate'].includes(ability.trigger)) fail('SEMANTIC_VALIDATION_FAILED', '选定目标仅可用于部署、被召唤、阵亡或己方回合效果。'); }
      if (!template && effect.amount?.stat === 'source_base_health' && definition.kind !== 'unit') fail('SEMANTIC_VALIDATION_FAILED', '初始防御力只能读取来源单位卡牌。');
      if (effect.target === 'self' && (['on_death','on_reveal'].includes(ability.trigger) || (!template && definition.kind !== 'unit'))) fail('SEMANTIC_VALIDATION_FAILED', '此效果时机没有可用的自身单位。');
      if (effect.op === 'modify_stats' && effect.attack_delta === 0 && effect.health_delta === 0) fail('SEMANTIC_VALIDATION_FAILED', '属性修改不能同时为零。');
      if (effect.op === 'modify_stacks' && effect.amount === 0) fail('SEMANTIC_VALIDATION_FAILED', '层数变化不能为零；清除请将层数设为0。');
      if (effect.op === 'modify_operation_cost' && effect.cost_delta === 0) fail('SEMANTIC_VALIDATION_FAILED', '行动费用修改不能为零。');
      if (effect.op === 'modify_kredit_slots' && effect.amount === 0) fail('SEMANTIC_VALIDATION_FAILED', '资源槽变化不能为零。');
      if (effect.op === 'fight' && (['on_death','on_reveal'].includes(ability.trigger) || (!template && definition.kind !== 'unit'))) fail('SEMANTIC_VALIDATION_FAILED','战斗效果需要仍在场的来源单位。');
      if (effect.op === 'fight' && effect.target === 'chosen' && (ability.target || !template) && (ability.target ?? definition.play_target)?.side !== 'enemy') fail('SEMANTIC_VALIDATION_FAILED','战斗目标必须是敌方单位。');
      if (['search_deck','summon_from_deck'].includes(effect.op)) { plainText(effect.card_name, `/abilities/${ai}/effects/${ei}/card_name`); if (!effect.card_name.trim() || effect.card_name !== effect.card_name.trim()) fail('SEMANTIC_VALIDATION_FAILED', '检索卡牌名称不能为空或带首尾空格。'); }
      if (['summon','create_card','transform','liberate'].includes(effect.op)) usedTokens.add(effect.token_id);
      if(effect.on_kill_summon)usedTokens.add(effect.on_kill_summon);
      for(const id of effect.token_ids??[])usedTokens.add(id);
    }
  }
  if (template) return;
  if(definition.play_target?.include_hq && definition.play_target.row!=='any')fail('SEMANTIC_VALIDATION_FAILED','总部目标的战线须选任意。');
  if(definition.play_target?.include_hq && abilities.some(a=>a.trigger==='on_play'&&!a.target&&leaves(a.effects).some(e=>['chosen','adjacent_to_chosen','chosen_and_adjacent'].includes(e.target)&&!['damage','heal','modify_incoming_damage','grant_order_target_reward'].includes(e.op))))fail('SEMANTIC_VALIDATION_FAILED','总部目标仅允许伤害或治疗。');
  if (chosen !== (definition.play_target !== null)) fail('SEMANTIC_VALIDATION_FAILED', '选定目标效果与 play_target 必须同时存在。');
  if (definition.kind !== 'unit' && ((!abilities.length && !allowEmptyOrder && !['field','hq'].includes(definition.kind)) || definition.keywords.length)) fail('SEMANTIC_VALIDATION_FAILED', '指令或反制需要至少一个效果，且不能具有单位内置词条。');
  if (tokenBody) return usedTokens;
  const tokens = new Set();
  const edges = new Map();
  let total = abilities.reduce((n,a)=>n+effectCount(a),0);
  for (const token of definition.tokens) {
    if (tokens.has(token.token_id)) fail('SEMANTIC_VALIDATION_FAILED', '衍生模板 ID 重复。');
    tokens.add(token.token_id); plainText(token.name, '/tokens/name');
    plainText(token.flavor_text || '', '/tokens/flavor_text', true);
    if(token.display_text!==undefined)plainText(token.display_text,'/tokens/display_text',true);
    const body = {...token,kind:token.kind||'unit',abilities:token.abilities||[],play_target:token.play_target??null};
    edges.set(token.token_id, semantics(body,false,allowEmptyOrder,true));
    total += body.abilities.reduce((n,a)=>n+effectCount(a),0);
  }
  for (const refs of [usedTokens,...edges.values()]) for (const id of refs) if (!tokens.has(id)) fail('SEMANTIC_VALIDATION_FAILED', '召唤引用了不存在的衍生模板。');
  for(const body of [definition,...definition.tokens])for(const a of body.abilities||[])for(const e of leaves(a.effects))if(['summon','transform','liberate'].includes(e.op)&&(definition.tokens.find(t=>t.token_id===e.token_id)?.kind||'unit')!=='unit')fail('SEMANTIC_VALIDATION_FAILED','只能直接召唤衍生单位；指令和反制请使用 create_card 加入手牌。');
  for(const body of [definition,...definition.tokens])for(const a of body.abilities||[])for(const e of leaves(a.effects))if(e.on_kill_summon&&(definition.tokens.find(t=>t.token_id===e.on_kill_summon)?.kind||'unit')!=='unit')fail('SEMANTIC_VALIDATION_FAILED','击杀后只能召唤衍生单位。');
  const reachable = new Set(usedTokens), pending=[...usedTokens];
  while(pending.length) for(const id of edges.get(pending.pop())||[]) if(!reachable.has(id)){reachable.add(id);pending.push(id);}
  // Unreferenced templates are independently editable library entries.
  if(total>96) fail('RULE_BUDGET_EXCEEDED','卡牌与衍生单位合计最多96条操作。');
};
export function substitute(value, parameters, used = new Set()) {
  if (Array.isArray(value)) return value.map(v => substitute(v, parameters, used));
  if (value && typeof value === 'object') {
    if (Object.hasOwn(value, 'param')) {
      if (!Object.hasOwn(parameters, value.param)) fail('INVALID_KEYWORD_PARAMS', '模板引用了未声明的参数。');
      used.add(value.param); return parameters[value.param];
    }
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, substitute(v, parameters, used)]));
  }
  return value;
}
export function validateKeyword(input, {allowBuiltin = false, workBudget = null} = {}) {
  const def = normalize(input); schemaCheck('keyword', def);
  plainText(def.name, '/name'); plainText(def.description, '/description', true); def.aliases.forEach(s => plainText(s, '/aliases'));
  if (Buffer.byteLength(canonical(def)) > 16384) fail('RULE_BUDGET_EXCEEDED', '词条定义超过大小限制。');
  if (def.implementation.kind === 'builtin') {
    if (!allowBuiltin || !builtinIds.has(def.id) || !builtinVersions.has(`${def.id}.v${def.version}`) || def.implementation.builtin_id !== `${def.id}.v${def.version}` || canonical(def.parameters) !== canonical(builtinDefinitions.findLast(d => d.id === def.id && d.version === def.version)?.parameters ?? {})) fail('UNSUPPORTED_EFFECT', '玩家只能登记模板词条；内置机制需要开发实现。');
  } else if(def.implementation.kind==='configurable'){
    if(def.id.startsWith('core.')||Object.keys(def.parameters).length)fail('INVALID_KEYWORD_PARAMS','逐卡配置词条不使用 core 命名空间或模板参数。');
  } else {
    if (def.id.startsWith('core.')) fail('INVALID_KEYWORD_PARAMS', 'core 命名空间仅供内置机制使用。');
    const entries = Object.entries(def.parameters), used = new Set();
    for (const [, range] of entries) if (range.type!=='token' && range.minimum > range.maximum) fail('INVALID_KEYWORD_PARAMS', '参数最小值不能大于最大值。');
    // Bound exhaustive validation even when a single parameter spans 1..100.
    const combinations=entries.reduce((n,[,v])=>n*(v.type==='token'?1:v.maximum-v.minimum+1),1);
    if(combinations>65536)fail('RULE_BUDGET_EXCEEDED','词条参数组合最多 65536 种，请缩小范围。');
    // A small number of combinations can still multiply a large template into
    // seconds of synchronous work. Bound the expanded traversal, not just count.
    const nodes=value=>1+(value&&typeof value==='object'?Object.values(value).reduce((n,v)=>n+nodes(v),0):0);
    const work=combinations*nodes(def.implementation.abilities);
    if(work>250000||workBudget&&work>workBudget.remaining)
      fail('RULE_BUDGET_EXCEEDED','词条参数范围与效果数量的组合过大，请缩小参数范围或拆分词条。');
    if(workBudget)workBudget.remaining-=work;
    const visit = (index, params) => {
      if (index === entries.length) return semantics(substitute(def.implementation.abilities, params, used), true);
      const [name, range] = entries[index];
      if(range.type==='token')return visit(index+1,{...params,[name]:'template_form'});
      for (let n = range.minimum; n <= range.maximum; n++) visit(index + 1, {...params, [name]: n});
    };
    visit(0, {});
    for (const [name] of entries) if (!used.has(name)) fail('INVALID_KEYWORD_PARAMS', '词条包含未使用的参数。');
  }
  return {definition: def, definition_hash: hash(def)};
}
export function registryEntries(registry) {
  return Object.values(registry).filter(e => e.registry_status === 'approved').sort((a, b) => a.definition.id < b.definition.id ? -1 : a.definition.id > b.definition.id ? 1 : a.definition.version - b.definition.version);
}
export const binding = entry => ({id: entry.definition.id, version: entry.definition.version, definition_hash: entry.definition_hash});
export const registryHash = registry => hash(registryEntries(registry).map(binding));
export function validateCardBlueprint(input, registry) {
  const blueprint = normalize(input);
  const required = ['kind', 'unit_class', 'cost', 'operation_cost', 'attack', 'health', 'keywords'];
  if (!blueprint || typeof blueprint !== 'object' || Array.isArray(blueprint) || required.some(key => !Object.hasOwn(blueprint, key)) || Object.keys(blueprint).some(key => ![...required, 'name', 'display_text', 'rarity', 'sin', 'faction_id', 'counter_trigger', 'abilities', 'tokens', 'play_target', 'appearance', 'media', 'effect_mode', 'deck_building', 'cost_reduction', 'cost_override', 'cost_surcharge', 'draw_rule','damage_bonuses','veteran'].includes(key))) fail('INVALID_REQUEST', '基础卡牌配置缺少字段或包含未知字段。', 400);
  if (Object.hasOwn(blueprint, 'effect_mode') && (!['append','replace'].includes(blueprint.effect_mode) || !Array.isArray(blueprint.abilities))) fail('INVALID_REQUEST', '追加模式需要固定能力数组。', 400);
  if (Object.hasOwn(blueprint,'appearance') && (!blueprint.appearance || typeof blueprint.appearance !== 'object' || Array.isArray(blueprint.appearance))) fail('INVALID_SCHEMA','卡牌外观必须是对象。');
  if (Object.hasOwn(blueprint, 'name')) {
    if (typeof blueprint.name !== 'string') fail('INVALID_SCHEMA', '卡牌名称必须是文本。');
    if (!blueprint.name.trim()) delete blueprint.name;
  }
  const shell = {schema_version: '1.0.0', ruleset_version: 'frontline-1', ...blueprint, name: blueprint.name || '未命名', flavor_text: '', play_target: blueprint.play_target ?? null, abilities: blueprint.abilities ?? [], tokens: structuredClone(blueprint.tokens ?? []), appearance: {...blueprint.appearance, emblem: blueprint.kind === 'unit' ? blueprint.unit_class : blueprint.kind}};
  delete shell.effect_mode;
  if (Object.hasOwn(blueprint, 'abilities') && !Array.isArray(blueprint.abilities)) fail('INVALID_SCHEMA', '固定能力必须是数组。');
  schemaCheck('card', shell); plainText(shell.name, '/card_blueprint/name');
  const seen = new Set();
  for (const ref of blueprint.keywords) {
    if (seen.has(ref.id)) fail('INVALID_KEYWORD_PARAMS', '基础配置不能重复选择同一词条。'); seen.add(ref.id);
    const entry = registry[`${ref.id}@${ref.version}`];
    if (!entry || entry.registry_status !== 'approved') fail('KEYWORD_NOT_REGISTERED', `词条 ${ref.id}@${ref.version} 尚未登记。`);
    const definition = entry.definition;
    if (Object.keys(ref.params).length !== Object.keys(definition.parameters).length || Object.keys(ref.params).some(key => !Object.hasOwn(definition.parameters, key))) fail('INVALID_KEYWORD_PARAMS', '所选词条参数必须与登记定义完全匹配。');
    for (const [key, range] of Object.entries(definition.parameters)) if (!validParameter(ref.params[key],range)) fail('INVALID_KEYWORD_PARAMS', `参数 ${key} 不在登记范围内。`);
    if (!(definition.implementation.kind==='configurable' && pendingRef(ref))) validateRefAbilities(definition,ref);
    if (blueprint.kind === 'order' && (definition.implementation.kind === 'builtin' || refAbilities(definition,ref).some(a => !['on_play','next_own_turn_start','next_opponent_turn_start','next_own_order_played','next_own_unit_deployed'].includes(a.trigger) || leaves(a.effects).some(e => e.target === 'self')))) fail('SEMANTIC_VALIDATION_FAILED', '所选词条仅支持单位，不能用于指令。');
  }
  // A not-yet-generated order may await its first effect, but every already-fixed
  // ability and expanded keyword must satisfy the real compiler and shared budget.
  // Empty per-card slots may be sent to the assistant, but can never be saved.
  for(const body of [shell,...shell.tokens]) body.keywords=body.keywords.filter(ref=>{
    if(!pendingRef(ref))return true;
    const def=registry[`${ref.id}@${ref.version}`]?.definition;
    if(def?.implementation.kind!=='configurable')validateRefAbilities(def??{implementation:{}},ref);
    if(Object.keys(ref.params).length)fail('INVALID_KEYWORD_PARAMS','逐卡配置词条没有模板参数。');
    return false;
  });
  compileCard(shell, registry, {allowEmptyOrder: true, allowUnusedTokens:true});
  return blueprint;
}
const effectSlot = (ability, effect) => canonical({trigger:ability.trigger,premise:ability.premise??null,selector:ability.target??null,repeat:ability.repeat??1, op: effect.op, target: effect.target ?? null, player: effect.player ?? null});
export function mergeBlueprintAbilities(candidateAbilities, fixedAbilities) {
  if (!Array.isArray(candidateAbilities)) fail('INVALID_SCHEMA', '模型能力必须是数组。');
  const merged = structuredClone(fixedAbilities), seen = new Set(fixedAbilities.map(canonical));
  const fixedSlots = new Set(fixedAbilities.flatMap(ability => ability.effects.map(effect => effectSlot(ability, effect))));
  for (const [ai, ability] of candidateAbilities.entries()) {
    const signature = canonical(ability);
    // The provider and service both apply this merge. Exact fixed copies from the
    // first pass disappear here while the original player ordering stays intact.
    if (seen.has(signature)) continue;
    if (!ability || typeof ability !== 'object' || !Array.isArray(ability.effects)) fail('INVALID_SCHEMA', '模型能力结构无效。');
    if (ability.effects.some(effect => effect && typeof effect === 'object' && fixedSlots.has(effectSlot(ability, effect)))) fail('BLUEPRINT_ABILITY_CONFLICT', '模型重复或修改了玩家固定效果；请只补充其他效果，或先在表单中修改固定效果。', 422, [{code: 'BLUEPRINT_ABILITY_CONFLICT', path: `/abilities/${ai}`, message: 'card.abilities 只返回额外能力；不要重写同触发、同操作、同目标的固定效果。完全相同的完整能力会自动去重。'}]);
    merged.push(structuredClone(ability)); seen.add(signature);
  }
  return merged;
}
// Compare model echoes using the same optional defaults as the battle runtime.
// This is comparison-only: retain the player's original template and its hash.
function comparableToken(token) {
  const kind = Object.hasOwn(token, 'kind') ? token.kind : 'unit';
  return {kind, cost: 1, operation_cost: kind === 'unit' ? 1 : 0, abilities: [], play_target: null, flavor_text: '', ...(kind !== 'counter' ? {counter_trigger: null} : {}), ...token};
}
function tokenDifferences(expected, actual, path) {
  if (canonical(expected) === canonical(actual)) return [];
  if (expected && actual && typeof expected === 'object' && typeof actual === 'object' && Array.isArray(expected) === Array.isArray(actual)) {
    return [...new Set([...Object.keys(expected), ...Object.keys(actual)])].flatMap(key => {
      const childPath = `${path}/${key.replace(/~/g, '~0').replace(/\//g, '~1')}`;
      if (!Object.hasOwn(expected, key) || !Object.hasOwn(actual, key)) return [childPath];
      return tokenDifferences(expected[key], actual[key], childPath);
    });
  }
  return [path];
}
function completeFixedReference(selected,ref){
  if(!pendingRef(selected))return false;
  if(canonical({...selected,abilities:[]})!==canonical({...ref,abilities:[]}))return false;
  if(!Array.isArray(ref.abilities)||!ref.abilities.length)return false;
  selected.abilities=structuredClone(ref.abilities);return true;
}
export function applyCardBlueprint(candidate, blueprint, {mergeEffects = true} = {}) {
  if (!blueprint) return structuredClone(candidate);
  const card = structuredClone(candidate), references = blueprint.keywords.map(ref => structuredClone(ref));
  if (!Array.isArray(card.keywords) || card.keywords.some(ref => !ref || typeof ref !== 'object' || Array.isArray(ref))) fail('INVALID_SCHEMA', '模型返回的 keywords 必须是词条引用数组。');
  for (const ref of card.keywords) {
    const selected = references.find(item => item.id === ref.id);
    if (selected && canonical(selected) !== canonical(ref) && !completeFixedReference(selected,ref)) fail('INVALID_KEYWORD_PARAMS', `模型修改了玩家已选择词条 ${ref.id} 的版本或参数，请重新完善机制。`, 422, [{code: 'BLUEPRINT_KEYWORD_CONFLICT', path: '/keywords', message: '玩家所选词条不能被模型覆盖。'}]);
    if (!selected) references.push(structuredClone(ref));
  }
  for (const field of ['kind', 'unit_class', 'cost', 'operation_cost', 'attack', 'health']) card[field] = blueprint[field];
  if(blueprint.veteran)card.veteran=structuredClone(blueprint.veteran);
  if(blueprint.draw_rule)card.draw_rule=structuredClone(blueprint.draw_rule);else delete card.draw_rule;
  if (blueprint.name) card.name = blueprint.name;
  if (Object.hasOwn(blueprint,'display_text')) card.display_text=blueprint.display_text; else delete card.display_text;
  if (Object.hasOwn(blueprint,'counter_trigger')) card.counter_trigger = blueprint.counter_trigger;
  else delete card.counter_trigger;
  if (Object.hasOwn(blueprint,'rarity')) card.rarity=blueprint.rarity;
  else delete card.rarity; // Legacy blueprints keep their original hash contract.
  if (Object.hasOwn(blueprint,'sin')) card.sin=blueprint.sin; else delete card.sin;
  if (Object.hasOwn(blueprint,'faction_id')) card.faction_id=blueprint.faction_id;
  else delete card.faction_id;
  if (Object.hasOwn(blueprint,'deck_building')) card.deck_building=blueprint.deck_building; else delete card.deck_building;
  if(blueprint.cost_reduction){
    if(card.cost_reduction && canonical(card.cost_reduction)!==canonical(blueprint.cost_reduction))fail('BLUEPRINT_ABILITY_CONFLICT','不能修改已有的动态减费规则。');
    card.cost_reduction=structuredClone(blueprint.cost_reduction);
  }
  if(blueprint.cost_override){if(card.cost_override&&canonical(card.cost_override)!==canonical(blueprint.cost_override))fail('BLUEPRINT_ABILITY_CONFLICT','不能修改已有的条件费用。');card.cost_override=structuredClone(blueprint.cost_override);}
  if(blueprint.cost_surcharge){
    if(card.cost_surcharge&&canonical(card.cost_surcharge)!==canonical(blueprint.cost_surcharge))fail('BLUEPRINT_ABILITY_CONFLICT','不能修改已有的动态加费规则。');
    card.cost_surcharge=structuredClone(blueprint.cost_surcharge);
  }
  card.keywords = references;
  if(blueprint.damage_bonuses){
    const additions=card.damage_bonuses??[],saved=structuredClone(blueprint.damage_bonuses);
    for(const bonus of additions)if(!saved.some(b=>canonical(b)===canonical(bonus)))saved.push(bonus);
    card.damage_bonuses=saved;
  }
  // Legacy blueprints did not define a fixed-ability contract. Preserve their
  // candidates unchanged; new blueprints opt in even when abilities is empty.
  if (Object.hasOwn(blueprint, 'abilities') && mergeEffects && blueprint.effect_mode!=='replace') card.abilities = blueprint.effect_mode === 'append' ? [...structuredClone(blueprint.abilities), ...card.abilities] : mergeBlueprintAbilities(card.abilities, blueprint.abilities);
  if (blueprint.play_target && blueprint.effect_mode!=='replace') {
    if (card.play_target && canonical(card.play_target) !== canonical(blueprint.play_target)) fail('BLUEPRINT_TARGET_CONFLICT', '新增效果必须共用现有登场目标；请先在表单中调整目标。');
    card.play_target = structuredClone(blueprint.play_target);
  }
  if (blueprint.tokens) {
    const tokens = structuredClone(blueprint.tokens);
    if (!Array.isArray(card.tokens)) fail('INVALID_SCHEMA', '模型返回的 tokens 必须是衍生卡数组。');
    const seen = new Set();
    for (const [index, token] of card.tokens.entries()) {
      if (!token || typeof token !== 'object' || Array.isArray(token) || typeof token.token_id !== 'string') fail('INVALID_SCHEMA', '衍生卡必须具有 token_id。');
      if (seen.has(token.token_id)) fail('INVALID_SCHEMA', '模型返回了重复的衍生卡 token_id。');
      seen.add(token.token_id);
      const existing = tokens.find(item => item.token_id === token.token_id);
      if (existing) {
        for(const ref of token.keywords??[]){const selected=existing.keywords.find(r=>r.id===ref.id);if(selected)completeFixedReference(selected,ref);}
        const echo=structuredClone(token);
        if(blueprint.effect_mode==='replace'||!(existing.abilities??[]).length&&Array.isArray(token.abilities)&&token.abilities.length>0){
          // Only effect text/selection is editable; all template identity and numeric fields stay fixed.
          existing.abilities=structuredClone(token.abilities??[]);
          if(Object.hasOwn(token,'play_target'))existing.play_target=structuredClone(token.play_target);
        }
        if(Object.hasOwn(existing,'display_text'))echo.display_text=existing.display_text;else delete echo.display_text;
        const differences = tokenDifferences(comparableToken(existing), comparableToken(echo), `/tokens/${index}`);
        if (differences.length) fail('BLUEPRINT_TOKEN_CONFLICT', `模型修改了已有衍生卡「${existing.name}」；费用、数值和效果必须保留。`, 422, differences.slice(0, 6).map(path => ({code: 'BLUEPRINT_TOKEN_CONFLICT', path, message: `已有衍生卡「${existing.name}」（${existing.token_id}）的此字段与固定配置不符。card.tokens 只返回新模板；已有模板由服务器保留，使用原 token_id 引用。`})));
      }
      if (!existing) tokens.push(token);
    }
    card.tokens = tokens;
  }
  if (blueprint.media) card.media=structuredClone(blueprint.media); else delete card.media;
  card.appearance = {...blueprint.appearance, emblem: blueprint.kind === 'unit' ? blueprint.unit_class : blueprint.kind};
  return card;
}
export function compileCard(input, registry, {allowEmptyOrder = false, allowUnusedTokens = false} = {}) {
  const definition = normalize(input); schemaCheck('card', definition);
  if(definition.kind!=='field' && (definition.media?.background||definition.media?.music)) fail('SEMANTIC_VALIDATION_FAILED','战场背景和音乐仅用于场地卡。');
  if(definition.veteran&&(definition.kind!=='unit'||!definition.tokens.some(t=>t.token_id===definition.veteran.token_id&&(t.kind??'unit')==='unit')))fail('SEMANTIC_VALIDATION_FAILED','老兵形态须引用已定义的衍生单位。');
  plainText(definition.name, '/name'); plainText(definition.flavor_text, '/flavor_text', true);
  if(definition.display_text!==undefined)plainText(definition.display_text,'/display_text',true);
  if (Object.hasOwn(definition.appearance, 'name_break')) {
    const letters=Array.from(definition.name), split=definition.appearance.name_break;
    if(split>=letters.length || !letters.slice(0,split).join('').trim() || !letters.slice(split).join('').trim()) fail('SEMANTIC_VALIDATION_FAILED','名称换行必须位于文字之间，两行均不能为空。',422,[{path:'/appearance/name_break',message:'请在名称文字之间换行。'}]);
  }
  if (Buffer.byteLength(canonical(definition)) > 16384) fail('RULE_BUDGET_EXCEEDED', '卡牌定义超过 16 KiB。');
  for(const body of [definition,...definition.tokens])for(const tier of [...(body.cost_surcharge??[]),...(body.cost_override?[body.cost_override]:[])]){
    validatePremise(tier.premise);
    if(premiseUnitQueries(tier.premise).length||/source_|event_|previous_card|destroyed_by/.test(JSON.stringify(tier.premise)))fail('SEMANTIC_VALIDATION_FAILED','加费条件仅查询出牌前公开场面或回合状态。');
  }
  for(const body of [definition,...definition.tokens])if(body.cost_reduction)validatePremise({test:'compare',left:{count_units:body.cost_reduction.per_unit},cmp:'gte',right:0});
  if(definition.kind==='hq')for(const adjustment of definition.draw_rule.adjustments??[]){validatePremise(adjustment.premise);if(premiseUnitQueries(adjustment.premise).length)fail('SEMANTIC_VALIDATION_FAILED','总部抽牌条件不能引用选中或自身单位。');}
  const expanded = structuredClone(definition), bindings = new Map();
  const resolve = (ref, builtinOnly = false) => {
    const entry = registry[`${ref.id}@${ref.version}`];
    if (!entry || entry.registry_status !== 'approved') fail('KEYWORD_NOT_REGISTERED', `词条 ${ref.id}@${ref.version} 尚未登记。`);
    const def = entry.definition;
    if (builtinOnly && (!builtinIds.has(ref.id) || def.implementation.kind !== 'builtin')) fail('INVALID_KEYWORD_PARAMS', '动态授予只能使用已实现的内置词条。');
    if (Object.keys(ref.params).length !== Object.keys(def.parameters).length) fail('INVALID_KEYWORD_PARAMS', '词条参数数量不匹配。');
    for (const [key, range] of Object.entries(def.parameters)) if (!validParameter(ref.params[key],range)) fail('INVALID_KEYWORD_PARAMS', `参数 ${key} 不在登记范围内。`);
    validateRefAbilities(def,ref);
    bindings.set(`${ref.id}@${ref.version}`, binding(entry)); return def;
  };
  const refs = (references, builtinOnly = false) => {
    const seen = new Set(); return references.map(ref => { if (seen.has(ref.id)) fail('INVALID_KEYWORD_PARAMS', '同一词条不能重复引用。'); seen.add(ref.id); return resolve(ref, builtinOnly); });
  };
  const definitions = refs(definition.keywords);
  expanded.keywords = [];
  definitions.forEach((def, i) => {
    if (def.implementation.kind === 'builtin') expanded.keywords.push(definition.keywords[i]);
    else expanded.abilities.push(...refAbilities(def,definition.keywords[i]));
  });
  definition.tokens.forEach((token, index) => {
    const target=expanded.tokens[index]; target.keywords=[];
    refs(token.keywords).forEach((def,i)=>{
      if(def.implementation.kind==='builtin')target.keywords.push(token.keywords[i]);
      else (target.abilities??=[]).push(...refAbilities(def,token.keywords[i]));
    });
  });
  for (const body of [expanded,...expanded.tokens]) for (const ability of body.abilities||[]) for (const effect of leaves(ability.effects)) if (effect.op === 'grant_keyword') resolve({id: effect.keyword_id, version: effect.keyword_version, params: {}}, true);
  schemaCheck('card', expanded); semantics(expanded, false, allowEmptyOrder, false, allowUnusedTokens);
  const keyword_bindings = [...bindings.values()].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : a.version - b.version);
  const definition_hash = hash(definition), compiled_program = {compiler_version: 'card-compiler-1', definition_hash, keyword_bindings, expanded_definition: expanded};
  if (Buffer.byteLength(canonical(compiled_program)) > 32768) fail('RULE_BUDGET_EXCEEDED', '展开程序超过 32 KiB。');
  const presentation=cardPresentation(definition,registry,expanded);
  return {definition, definition_hash, canonical_definition: canonical(definition), keyword_bindings, compiled_program, compiled_program_hash: hash(compiled_program), rules_text:rulesText(expanded),short_rules_text:presentation.rules_text,detailed_text:presentation.detailed_text,keyword_names:presentation.keyword_names};
}
const bonusText=(bonuses,keyword)=>bonuses.map(b=>`对${b.filter.keyword_id?'有'+(keyword(b.filter.keyword_id)?.name??b.filter.keyword_id)+'的':''}${b.filter.card_name?'【'+b.filter.card_name+'】':b.filter.name_contains?'名称含【'+b.filter.name_contains+'】的':''}${b.filter.faction_id?'指定阵营':''}${unitClassText(b.filter.unit_classes??[])}伤害+${b.amount}`).join('，');
const targets = {all_other_friendly_units:'其他友方单位',self_and_trigger:'自身与触发单位',trigger_and_adjacent:'触发单位及其相邻单位',adjacent_to_trigger:'触发单位的相邻单位',random_enemy_target:'随机敌方目标',random_friendly_target:'随机友方目标',attack_target:'攻击目标',all_units:'双方所有单位',creator:'生成本卡的单位',chosen_and_adjacent:'所选单位及其左右相邻单位',adjacent_to_self:'自身左右相邻单位',adjacent_to_chosen:'所选单位左右相邻单位',trigger_unit: '触发单位', self: '自身', chosen: '选定单位', own_hq: '己方总部', enemy_hq: '敌方总部', all_friendly_units: '所有友方单位', all_enemy_units: '所有敌方单位', random_friendly_unit: '随机一个友方单位', random_enemy_unit: '随机一个敌方单位'};
const triggers = {on_activate:"主动",own_card_played:'己方打出卡牌后',enemy_card_played:'敌方打出卡牌后',on_keyword_lost:'失去词条时',on_kill:'消灭敌方单位后',after_attacked:'受到攻击后',own_unit_moved:'友方单位移动到前线后',enemy_unit_moved:'敌方单位移动到前线后',when_condition:"满足条件时",when_condition:'满足条件时',own_unit_attacked:'友方单位攻击后',enemy_unit_attacked:'敌方单位攻击后',own_unit_retreated:'友方单位撤退后',enemy_unit_retreated:'敌方单位撤退后',own_unit_returned:'友方单位回手后',enemy_unit_returned:'敌方单位回手后',on_leave:'离场时',on_veteran:'升为老兵时',own_unit_became_veteran:'友方单位升为老兵时',enemy_unit_became_veteran:'敌方单位升为老兵时','on_attack':'主动攻击时','own_unit_entered':'友方单位入场时','enemy_unit_entered':'敌方单位入场时','own_unit_attacked_hq':'友方单位攻击敌方总部后','enemy_unit_attacked_hq':'敌方单位攻击己方总部后',next_own_unit_deployed:"下一次己方部署单位后",after_attack:"主动攻击完成后",after_move:"移动完成后",after_action:"主动行动完成后",own_unit_died:"友方单位阵亡时",enemy_unit_died:"敌方单位阵亡时",on_stack_gained:'获得层数后',"own_unit_deployed":"己方部署其他单位后","enemy_unit_deployed":"敌方部署单位后","own_order_played":"己方指令结算后","enemy_order_played":"敌方指令结算后","on_attacked":"受到主动攻击时","on_damaged":"受到伤害后","next_own_turn_start":"己方下回合开始","next_opponent_turn_start":"敌方下回合开始","next_own_order_played":"下一张己方指令结算后",while_active:'在场期间',opponent_turn_start:'对方回合开始',opponent_turn_end:'对方回合结束',on_summon:'被召唤时',on_reveal: '触发时', on_play: '登场', own_turn_start: '己方回合开始', own_turn_end: '己方回合结束', on_death: '阵亡'};
const statNames = {event_damage:"本次受到的伤害",friendly_turn_number:"己方回合序号",enemy_turn_number:"敌方回合序号",source_base_health:'本卡初始防御力',enemy_unit_count:'敌方在场单位数',friendly_unit_count:'己方在场单位数',other_friendly_unit_count:'其他友方在场单位数'};
const amountText = n => n?.max_unit_stat?`等同于${maxUnitStatText(n)}的`: n?.count_units?`等同于${unitCountText(n.count_units)}的`: unitValue(n)?`等同于${unitValueText(n)}的`:n?.stat ? `等同于${statNames[n.stat]}的` : n;
const delta = n => n?.max_unit_stat?`+${maxUnitStatText(n)}`: n?.count_units?`+${unitCountText(n.count_units)}（结算时计数）`: unitValue(n)?`+${unitValueText(n)}`:n?.equipment_faction?`每件指定阵营装备×${n.scale}`:n?.equipment ? `每件【${n.equipment}】装备×${n.scale}` : n?.stat ? `+${statNames[n.stat]}（结算时计数）` : n >= 0 ? `+${n}` : String(n);
const selectorText = s => `${s.side==='any'?'任意一方':s.side==='enemy'?'敌方':'友方'}${({any:'',front:'前线',support:'后援线'})[s.row]}${s.faction_id?'指定阵营的':''}${unitClassText(s.unit_classes)}${s.include_hq?'或总部':''}`;
export function rulesText(def) {
  const counterNames = {enemy_unit_deployed:'对方部署单位后',enemy_order_played:'对方打出指令时',enemy_unit_attacked:'对方攻击友方单位时',enemy_hq_attacked:'对方攻击己方总部时'};
  const keyword = id => builtinDefinitions.findLast(d=>d.id===id);
  const lines = def.keywords.map(k => keyword(k.id) ? keyword(k.id).name + (Object.keys(k.params ?? {}).length ? ' ' + Object.values(k.params).join('/') : '') : k.id);
  if(def.kind==='hq')lines.unshift(`总部初始防御${def.health}；每回合抽${def.draw_rule.base}张牌。`+(def.draw_rule.adjustments??[]).map(a=>`若${premiseText(a.premise)}，抽牌数${a.delta>0?'+':''}${a.delta}。`).join(''));
  for(const tier of def.cost_surcharge??[])lines.unshift(`若${premiseText(tier.premise)}，本卡费用+${tier.amount}（多档只取最高档）。`);
  if(def.cost_override)lines.unshift(`若${premiseText(def.cost_override.premise)}，本卡费用为${def.cost_override.value}。`);
  if(def.cost_reduction)lines.unshift(`本卡费用减少${unitCountText(def.cost_reduction.per_unit)}×${def.cost_reduction.amount}（最低0，出牌前计算）。`);
  if (def.kind === 'counter') lines.unshift(`伏置：${counterNames[def.counter_trigger]}触发一次，触发时扣费；下次己方回合开始未触发则返回手牌。`);
  if(def.damage_bonuses?.length)lines.push('效果伤害：'+bonusText(def.damage_bonuses,keyword)+'。');
  const effect = (e, ability) => {
    const selector = ability.target ?? def.play_target;
    if(e.op==='select_units')return `选择${e.min}～${e.max}个${e.side==='ally'?'友方':e.side==='enemy'?'敌方':''}${e.unit_filter?.name_contains?`【${e.unit_filter.name_contains}】`:''}单位`;
    let target = e.target === 'chosen' && selector ? `${ability.target && ['on_death','own_turn_start','own_turn_end','opponent_turn_start','opponent_turn_end','next_own_turn_start','next_opponent_turn_start','next_own_order_played','next_own_unit_deployed','own_unit_deployed','enemy_unit_deployed','own_order_played','enemy_order_played','own_card_played','enemy_card_played','after_attacked','own_unit_moved','enemy_unit_moved','on_kill','on_attacked','on_damaged','on_stack_gained','after_attack','after_move','after_action','own_unit_died','enemy_unit_died','on_attack','own_unit_entered','enemy_unit_entered','own_unit_attacked_hq','enemy_unit_attacked_hq','own_unit_became_veteran','enemy_unit_became_veteran','on_veteran','own_unit_attacked','enemy_unit_attacked','own_unit_retreated','enemy_unit_retreated','own_unit_returned','enemy_unit_returned','on_leave'].includes(ability.trigger) && (selector.timing??'deploy')==='deploy'?'部署时选定的':'所选'}${selectorText(selector)}` : ['adjacent_to_chosen','chosen_and_adjacent'].includes(e.target)&&selector?`所选${selectorText(selector)}${e.target==='chosen_and_adjacent'?'及其':'的'}左右相邻单位`:(e.target==='selected_units'?'所选单位':targets[e.target]), duration = ability.trigger==='while_active' ? '' : e.duration === 'end_of_turn' ? '本回合' : e.duration === 'match' ? '永久' : e.duration==='next_own_turn_start'?'直到下个己方回合开始':e.duration==='next_opponent_turn_end'?'直到下个敌方回合结束':'在场期间';
    if(e.unit_filter)target+=({front:'中前线的',support:'中后援线的'})[e.unit_filter.row]??'';
    if(e.unit_filter)target+=filterDetail(e.unit_filter);
    if(e.unit_filter){const f=e.unit_filter;target+=`中${f.card_name?'名为【'+f.card_name+'】的':''}${f.name_contains?'名称含【'+f.name_contains+'】的':''}${f.unit_classes?unitClassText(f.unit_classes):'单位'}`;}
    switch (e.op) {
      case 'choose_effect': return '抉择（仅选一项）：'+e.options.map((o,i)=>`${i+1}. ${o.label}${o.premise?`（需${premiseText(o.premise)}）`:""}〔${o.effects.map(x=>effect(x,ability)).join('；')}〕`).join(' / ');
      case 'cancel_action': return '取消本次指令或总部攻击（费用不返还）';
      case 'damage': return `对${target}造成 ${amountText(e.amount)} 点伤害`+(e.max_amount!==undefined?`，最多${e.max_amount}点`:``)+(e.caps?.length?`（${e.caps.map(c=>filterDetail(c.filter)+unitClassText(c.filter.unit_classes)+`最多${c.amount}点`).join("；")}）`:``)+(e.bonuses?.length?'（'+bonusText(e.bonuses,keyword)+'，合并结算）':'')+(e.on_kill_summon?`；若本次击杀，在其原位置为其控制者召唤【${def.tokens.find(t=>t.token_id===e.on_kill_summon)?.name??e.on_kill_summon}】`:'');
      case 'heal': return `为${target}恢复 ${amountText(e.amount)} 点生命`;
      case 'draw': return `${e.player === 'owner' ? '' : '敌方'}抽${e.amount}张${e.filter?.kind?({unit:'单位',order:'指令',counter:'反制',field:'场地'})[e.filter.kind]:''}牌`;
      case 'if_killed': return `${e.per_unit?'本次伤害每消灭一个单位，':'若刚才的伤害消灭单位，'}${rulesText({...def,keywords:[],abilities:[{...ability,effects:e.effects}]}).split('：').slice(1).join('：')}`;
      case 'schedule': return `${e.lifetime==='turn'?'本回合，':''}${['next_own_turn_start','next_opponent_turn_start'].includes(e.trigger)?(e.repeat==='each_turn'?'每个':'')+(e.trigger==='next_own_turn_start'?'己方':'敌方')+(e.repeat==='each_turn'?'回合开始':`后续第${e.after_turns??1}回合开始`):(e.repeat==='each_event'?'每次':'下一次')+({next_own_unit_deployed:'己方部署单位后',next_own_unit_entered:'友方单位入场时',next_own_unit_attacked_hq:'友方单位攻击敌方总部后',next_own_order_played:'己方指令结算后'})[e.trigger]}：${rulesText({...def,keywords:[],abilities:[{...ability,effects:e.effects}]}).split('：').slice(1).join('：')}${e.times?`（共${e.times}次）`:''}${e.once_per_card?'（每张卡本局一次）':''}`;
      case 'become_trigger_unit': return '变为被消灭单位的复制'+(e.inherit==='permanent'?'（保留自身永久强化）':'');
      case 'transform': return `将${target}进化为【${def.tokens.find(t=>t.token_id===e.token_id)?.name??e.token_id}】${e.inherit==='permanent'?'（继承永久强化）':''}`;
      case 'prepare_counter': return `使敌方下一张指令无效${e.duration==='battle'?'（自身在场期间）':e.duration==='end_of_turn'?'（本回合）':''}`;
      case 'if_drawn': return `若本组抽到的牌${e.match==='all'?'全部':'至少一张'}为${e.parity==='even'?'偶':'奇'}数费用，${rulesText({...def,keywords:[],abilities:[{...ability,effects:e.effects}]}).split('：').slice(1).join('：')}`;
      case 'gain_kredits': return `获得 ${e.amount} 点本回合资源（${e.allow_overflow?'可超过资源槽':'不超过资源槽'}）`;
      case 'modify_stats': if(e.health_mode==='max_only')return `${target}防御上限${delta(e.health_delta)}${e.attack_delta?`，攻击${delta(e.attack_delta)}`:''}（${duration}）`; return `${target}${delta(e.attack_delta)}/${delta(e.health_delta)}（${duration}）`;
      case 'swap_stats': return `交换${target}的攻击力与剩余防御力（本次在场期间）`;
      case 'set_attack': return `${target}攻击力设为${typeof e.value==='object'?unitValueText(e.value):e.value}（${duration}）`;
      case 'lose_kredits': return `${e.player==='owner'?'己方':'敌方'}失去${e.amount}指挥点`;
      case 'trigger_death': return `触发${target}的阵亡效果`;
      case 'trigger_evolution': return `使${target}立即进化`;
      case 'summon_origin': return `召唤${e.amount}张原型`;
      case 'temporarily_remove': return `暂时移除${target}，${e.return_when==='immediate'?'立即':e.return_when==='end_of_turn'?'回合结束':e.return_when==='source_leaves'?'本单位离场后':`${e.return_when.includes('opponent')?'敌方':'己方'}第${e.after_turns??1}个后续回合${e.return_when.endsWith('end')?'结束':'开始'}`}${e.destination==='hand'?'返回手牌':'回到原位'}${e.return_cost!==undefined?'，费用变为'+e.return_cost:''}`;
      case 'become_veteran': return `使${target}升为老兵`;
      case 'take_control': return `控制${target}（${{end_of_turn:'本回合',next_own_turn_start:'直到己方下回合开始',battle:'直到离场'}[e.duration]}）`;
      case 'grant_ability': return `${target}获得“${rulesText({...def,kind:'unit',keywords:[],play_target:null,abilities:[e.ability]})}”（${duration}）`;
      case 'grant_keyword': return `${target}获得${keyword(e.keyword_id)?.name??e.keyword_id}（${duration}）`;
      case 'set_attack_limit': return `${target}每回合最多攻击 ${e.attacks} 次（${duration}）`;
      case 'remove_hand': return `移除${e.player==='owner'?'己方':'敌方'}手牌中的所有【${e.card_name}】`;
      case 'modify_stacks': return `${target}${e.stack==='heavy_armor'?'重甲':e.stack+'层数'} ${delta(e.amount)}（${duration}）`;
      case 'set_stacks': return `${target}${e.stack==='heavy_armor'?'重甲':e.stack+'层数'}设为 ${unitValue(e.amount)?unitValueText(e.amount):e.amount}（${duration}）`;
      case 'modify_operation_cost': return `${target}行动费${e.cost_set!==undefined?'为'+e.cost_set:e.per_stack?`每有1层${unitValueText({stack_count:e.per_stack}).replace(/层数$/,'')}${delta(e.cost_delta)}`:delta(e.cost_delta)}（${duration}）`;
      case 'remove_keyword': return `使${target}失去${keyword(e.keyword_id)?.name??e.keyword_id}`;
      case 'forbid_deploy': return `${e.player==='opponent'?'敌方':'己方'}下个回合不能从手牌部署单位`;
      case 'destroy': return `消灭${target}`;
      case 'pin': return `压制${target}（各自后续${e.turns}回合结束时解除）`;
      case 'suppress': return `抑制${target}`;
      case 'repair': return `完全修复${target}`;
      case 'reset_operations': return `重置${target}本回合已用行动次数`;
      case 'retreat': return `使${target}撤退`;
      case 'return_to_hand': return `将${target}返回其控制者手牌`+(e.cost_delta===undefined?'':`，${e.duration==='end_of_turn'?'本回合内':''}该牌下次打出费用${e.cost_delta>0?'+':''}${e.cost_delta}`);
      case 'remove': return `移除${target}，不触发阵亡`;
      case 'shuffle_into_deck': return `将${target}${e.position==='top'?'放到':e.position==='bottom'?'放到':'洗入'}${e.deck==='owner'?'其拥有者的':'己方'}牌库${e.position==='top'?'顶':e.position==='bottom'?'底':''}，不触发阵亡`;
      case 'tax_opponent_plays': return `下个敌方回合，敌方打出${({unit:'单位牌',order:'指令牌',any:'卡牌'})[e.card_kind]}的费用+${e.amount}`+(e.refund_per?`；己方下个回合开始时，敌方每因此多支付${e.refund_per}点，获得1点指挥点（可超过资源槽）`:'');
      case 'fight': return `自身与${target}交战`;
      case 'intel': return e.selection==='chosen'?`选择并查看敌方${e.amount}张手牌`:`情报 ${e.amount}`;
      case 'discard': return `${e.player==='owner'?'己方':'敌方'}${e.selection==='chosen'?'选择':'随机'}弃置 ${e.amount} 张${e.filter?.name_contains?`名称含【${e.filter.name_contains}】的`:e.filter?.card_name?`【${e.filter.card_name}】`:''}${e.filter?.kind==='unit'?'单位':''}手牌`;
      case 'research': return `研发：选择${e.token_ids.map(id=>'【'+def.tokens.find(t=>t.token_id===id)?.name+'】').join('或')}加入手牌`;
      case 'develop': return `开发：从${e.source==='tokens'?'指定衍生卡池':e.source==='deck'?'当前己方牌库（选中的原牌移出牌库）':'己方起始牌组卡池'}随机展示最多3种符合条件的卡牌，选择一张加入手牌`;
      case 'modify_hand_cost': return `${{hand:'留在手牌期间',end_of_turn:'本回合',match:'永久'}[e.duration]}，${{chosen:'选择一张',random:'随机一张',all:'所有',self:'本卡这张',drawn:'本组刚抽到的'}[e.selection]}己方手牌${e.filter?.faction_id?'（指定阵营）':''}${e.filter?.keyword_id?`（有${keyword(e.filter.keyword_id)?.name??e.filter.keyword_id}的）`:''}${e.filter?.without_keyword?`（没有${keyword(e.filter.without_keyword)?.name??e.filter.without_keyword}的）`:''}费用${e.cost_delta>0?'+':''}${e.cost_delta}（最低0）`;
      case 'modify_cards': {const zones=e.zones.map(z=>({battlefield:'场上',hand:'手牌',deck:'牌组'})[z]).join('、'),who={owner:'己方',opponent:'敌方',both:'双方'}[e.player],changes=[];if(e.attack_delta||e.health_delta)changes.push(`${delta(e.attack_delta??0)}/${delta(e.health_delta??0)}`);if(e.operation_cost_delta)changes.push(`行动费${e.operation_cost_delta>0?'+':''}${e.operation_cost_delta}`);for(const a of e.grant_abilities??[])changes.push('获得“'+rulesText({...def,kind:'unit',keywords:[],play_target:null,abilities:[a]})+'”');return `${e.duration==='match'?'永久':'在场期间'}强化${who}${zones}中${e.filter.same_as_discarded?'与所弃卡同名的':e.filter.card_name?'【'+e.filter.card_name+'】':e.filter.name_contains?'名称含【'+e.filter.name_contains+'】的':'全部'}单位：${changes.join('，')}`;}
      case 'gain_hq_defense': return `${e.player==='owner'?'己方':'敌方'}总部增加 ${e.amount} 点防御`;
      case 'modify_kredit_slots': return `${e.player==='owner'?'己方':'敌方'}资源槽 ${delta(e.amount)}`;
      case 'set_combat_priority': return `${target}${{attack:'主动攻击',retaliation:'反击',both:'交战'}[e.applies_to]}时先结算战斗伤害（${duration}）`;
      case 'grant_unit_class': return `${target}也视为${unitClassText([e.unit_class])}（${duration}，不改变主兵种行动规则）`;
      case 'noop': return '无额外效果';
      case 'modify_incoming_damage': {if(e.immune)return `${target}免疫${{combat:'战斗',effect:'效果',both:''}[e.damage_kind]}伤害（${duration}）`;const from=e.source_unit_classes?'来自'+unitClassText(e.source_unit_classes)+'的':'';const times=(e.source_kind?'，仅限'+({unit:'单位',order:'指令',counter:'反制',field:'场地',hq:'总部'})[e.source_kind]+'伤害':'')+(e.source_side&&e.source_side!=='any'?'，来源属于'+(e.source_side==='ally'?'己方':'敌方'):'')+(e.multiplier?'，伤害×'+e.multiplier:'');if(typeof e.amount==='object')return `${target}攻击力每高出伤害来源单位${e.amount.attack_gap.step}点，受到${from}${{combat:'战斗',effect:'效果',both:''}[e.damage_kind]}伤害-${e.amount.attack_gap.reduction}${times}（${duration}）`; return `${target}受到的${from}${{combat:'战斗',effect:'效果',both:''}[e.damage_kind]}伤害${e.amount?((e.amount>0?'+':'')+e.amount):''}${times}（${duration}）`; }
      case 'grant_order_target_reward': return `己方指令选中${target}时，己方获得${e.amount}指挥点（${duration}，不含本指令）`;
      case 'set_combat_damage_multiplier': if(e.attack_base==='opponent')return `${target}交战时以对方攻击力为基数（对总部仍用自身攻击力，倍率${e.multiplier}/${e.divisor??1}）`; if(e.multiplier===0)return (e.target_filter?`对${filterDetail(e.target_filter)+unitClassText(e.target_filter.unit_classes)}：`:'')+(e.target_attack_compare?`交战目标攻击${{gt:'大于',gte:'不低于',eq:'等于',ne:'不等于',lt:'小于',lte:'不高于'}[e.target_attack_compare]}自身时：`:'')+`${target}对${{any:'任意目标',infantry:'步兵',tank:'坦克',artillery:'炮兵',fighter:'战斗机',bomber:'轰炸机',hq:'总部'}[e.against]}${e.target_row&&e.target_row!=='any'?`（${e.target_row==='front'?'前线':'支援阵线'}）`:''}${{attack:'主动攻击',retaliation:'反击',both:'主动攻击或反击'}[e.applies_to]}时不造成战斗伤害（${duration}）`; return (e.target_filter?`对${filterDetail(e.target_filter)+unitClassText(e.target_filter.unit_classes)}：`:'')+(e.target_attack_compare?`交战目标攻击${{gt:'大于',gte:'不低于',eq:'等于',ne:'不等于',lt:'小于',lte:'不高于'}[e.target_attack_compare]}自身时：`:'')+ `${target}对${{any:'任意目标',infantry:'步兵',tank:'坦克',artillery:'炮兵',fighter:'战斗机',bomber:'轰炸机',hq:'总部'}[e.against]}${e.target_row&&e.target_row!=='any'?`（${e.target_row==='front'?'前线':'支援阵线'}）`:''}${e.attack_delta?`（本次攻击基数${delta(e.attack_delta)}）`:''}${{attack:'主动攻击',retaliation:'反击',both:'主动攻击或反击'}[e.applies_to]}时造成 ${e.multiplier}${e.divisor ? `/`+e.divisor : ""} 倍战斗伤害${e.divisor>1?`，${e.rounding==="ceil"?"向上":"向下"}取整`:""}${e.ignore_armor?"，无视重甲减免":""}（${duration}）`;
      case 'equip': case 'unequip': return `${target}${e.op==='equip'?'装备':'移除'} ${e.amount} 件【${e.tag}】`;
      case 'unit_limit': return `${e.player==='both'?'双方':e.player==='owner'?'己方':'敌方'}在场单位最多${e.amount}个`;
      case 'reshuffle_zones': return `${e.player==='both'?'双方':e.player==='owner'?'己方':'敌方'}将${e.zones.map(z=>({hand:'手牌',discard:'弃牌堆',battlefield:'在场单位'})[z]).join('、')}洗回各自牌库`;
      case 'liberate': return '解放为'+(def.tokens.find(t=>t.token_id===e.token_id)?.name??e.token_id);
      case 'transfer_card': {if(e.copy_buff){const {copy_buff:b,...base}=e;return `${effect(base,ability)}，该复制${delta(b.attack_delta)}/${delta(b.health_delta)}（${b.duration==='match'?'永久':'在场期间'}）`;} if(e.entry==='deploy')return `从${e.player==='opponent'?'敌方':'己方'}牌库${e.selection==='chosen'?'由其选择':'随机选择'}${e.amount}张单位，免费部署`; if(e.player==='opponent'){const local={...e};delete local.player;return effect(local,ability).replaceAll('己方','敌方').replace('手动选择','由敌方选择');}if(e.source==='self'&&e.mode==='move')return (e.destination==='hand'?'将阵亡原卡返回己方手牌':'将阵亡原卡放入牌库'+({top:'顶',bottom:'底',random:'随机位置'}[e.deck_position??'random']))+(e.overflow?'；手牌满则改放牌库顶':'');
  if(e.source==='attack_target')return `将被攻击单位的${e.amount}张复制${{hand:'加入手牌',deck:'洗入牌库',support:'召唤至后援线',source_position:'召唤至原位置'}[e.destination]}${e.copy_state==='current_stats'?'（保留当前攻击、防御上限与费用）':''}`;
  if(e.amount?.stat==='selected_destroyed_count')return `从己方弃牌区随机召唤等量${e.filter?.name_contains?`【${e.filter.name_contains}】`:''}单位`;
  if(e.source==='self'&&!e.filter){const dest={hand:'加入己方手牌',deck:'洗入己方牌库',support:'召唤至己方后援线',source_position:'召唤至原位置'}[e.destination];return `将自身的${e.amount}张复制${dest}${copyInheritanceText(e)}`;}const source={event_card:'触发事件的卡牌',deck:'己方牌组',discard:'己方弃牌区',hand:'当前手牌',self:'本卡',drawn:'本组刚抽到的手牌',starting_deck:'己方起始牌组卡池'}[e.source],dest={hand:'己方手牌',deck:'己方牌组随机位置',support:'己方后援线',source_position:'来源单位原位置'}[e.destination],f=e.filter??{};return `从${source}${e.selection==='highest_cost'?'随机选择费用最高的':e.selection==='random'?'随机选择':e.selection==='chosen'?'手动选择':'按顺序选择'} ${e.amount} 张${f.card_name?`【${f.card_name}】`:''}${f.sin!==undefined?({wrath:'暴怒',lust:'色欲',sloth:'怠惰',gluttony:'暴食',gloom:'忧郁',pride:'傲慢',envy:'嫉妒',null:'无罪孽'}[f.sin]):''}${f.unit_class?unitClassText([f.unit_class]):f.kind==='unit'?'单位':''}${f.faction_id?'（指定阵营）':''}${f.event_faction?'（事件卡同阵营）':''}${f.event_cost_distance!==undefined?`（费用差不超过${f.event_cost_distance}）`:''}卡牌，${e.mode==='copy'?'复制':'移动'}到${dest}${e.mode==='copy'?copyInheritanceText(e):''}${e.fallback_sources?`；无符合牌则依次从${e.fallback_sources.map(s=>({deck:'牌库',discard:'弃牌区',hand:'手牌'})[s]).join('、')}寻找`:''}`;}
      case 'search_deck': return `从己方牌组将 ${e.amount} 张【${e.card_name}】加入手牌`;
      case 'summon_from_deck': return `从己方牌组召唤 ${e.amount} 张【${e.card_name}】单位到后援线`;
      case 'create_card': { const t = def.tokens.find(t => t.token_id === e.token_id); return `将 ${e.amount} 张【${t.name}】加入${e.player==='owner'?'己方':'敌方'}手牌`; }
      case 'summon': { const t = def.tokens.find(t => t.token_id === e.token_id); return `在己方后援线召唤 ${e.amount} 个${t.name}（${t.attack}/${t.health}，行动费${t.operation_cost??1}）`; }
    }
  };
  for (const a of def.abilities) lines.push(`${a.zone==='hand'?'手牌中，':''}${a.trigger==='on_keyword_lost'?`失去${builtinDefinitions.find(d=>d.id===a.keyword_id)?.name??a.keyword_id}时`:a.trigger==='while_active'&&def.kind==='field'?'场地生效期间':a.trigger==='on_play'?(def.kind==='unit'?'部署时':def.kind==='field'?'生效时':'使用时'):a.after_turns>1?`${a.trigger==='next_own_turn_start'?'己方':'敌方'}第${a.after_turns}个后续回合开始`:(a.event_scope==='self'?triggers[a.trigger].replace(/^(友方单位|己方部署其他单位)/,'自身'):a.event_scope==='other'?triggers[a.trigger].replace(/^友方单位/,'其他友方单位'):triggers[a.trigger])}${a.occurrence?`（第${a.occurrence}次）`:''}${a.trigger==='on_stack_gained'?`（${a.stack}）`:''}${a.damage_step?`（每累计损失${a.damage_step}防御）`:""}${a.limit?`（${a.limit_scope==='turn'?'每回合':''}最多${a.limit}次）`:""}：${a.premise ? `若${premiseText(a.premise)}，则` : ""}${a.repeat!==undefined?`重复${a.repeat?.count_units?unitCountText(a.repeat.count_units):a.repeat}次（次数先锁定）：`:''}${a.effects.map(e => a.trigger === 'while_active' ? effect(e, a).replace('（）', '') : effect(e, a)).join('；')}。`);
  if (def.play_target) lines.unshift(`选择1个${selectorText(def.play_target)}（无目标时跳过选择）。`);
  return lines.length ? compactRules(lines.join('\n')) : '无额外能力。';
}
const intentLabels = {cost: '部署费用', operation_cost: '行动费用', attack: '攻击', health: '生命', unit_class: '兵种'};
const intentAssignment = '\\s*(?:(?:[:：=]|为|是)\\s*)?';
const intentNumber = '[+-]?\\d+(?:\\.\\d+)?';
const operationLabel = '(?:行动|操作)(?:费用|费)?';
const deploymentLabel = '部署(?:费用|费)?';
const attackLabel = '攻(?:击(?:力)?)?';
const healthLabel = '(?:防御(?:力)?|生命(?:值)?|血(?:量)?)';
// Consume whole attribute phrases in source order. Independent regex searches overlap:
// "3费部署0行动" must become [3费部署] [0行动], never [部署0] or cost=0.
const intentPhrases = [
  ['operation_cost', `${operationLabel}${intentAssignment}{n}\\s*(?:点\\s*)?(?:费用|费)?`],
  ['cost', `${deploymentLabel}${intentAssignment}{n}\\s*(?:点\\s*)?(?:费用|费)?`],
  ['attack', `${attackLabel}${intentAssignment}{n}(?:\\s*点)?`],
  ['health', `${healthLabel}${intentAssignment}{n}(?:\\s*点)?`],
  ['operation_cost', `{n}\\s*(?:点\\s*)?(?:费用?\\s*)?${operationLabel}`],
  ['cost', `{n}\\s*(?:点\\s*)?(?:费用?\\s*)?${deploymentLabel}`],
  ['attack', `{n}\\s*(?:点\\s*)?${attackLabel}`],
  ['health', `{n}\\s*(?:点\\s*)?${healthLabel}`],
  ['cost', `(?:费用|费)${intentAssignment}{n}`],
  ['cost', `{n}\\s*(?:点\\s*)?(?:费用|费)`]
];
const intentPattern = intentPhrases.map(([, phrase], index) => `(?:${phrase.replace('{n}', `(?<n${index}>${intentNumber})`)})`).join('|');
const unitAliases = {炮: 'artillery', 炮兵: 'artillery', 火炮: 'artillery', artillery: 'artillery', 步兵: 'infantry', infantry: 'infantry', 坦克: 'tank', tank: 'tank', 战斗机: 'fighter', fighter: 'fighter', 轰炸机: 'bomber', bomber: 'bomber'};
const unitNames = Object.keys(unitAliases).sort((a, b) => b.length - a.length).join('|');
const unitBoundary = '(?=$|[\\s，,。.;；、!?！？]|单位|卡|部署|行动|攻击|防御)';
const headUnitPattern = new RegExp(`^(?:请\\s*)?(?:帮我\\s*|给我\\s*)?(?:创建|制作|设计|生成|来|我想要|我要|要)?\\s*(?:一|1)?\\s*(?:张|个|门|辆|架)?\\s*(?:\\d+\\s*费\\s*)?(${unitNames})${unitBoundary}`, 'iu');
const explicitUnitPattern = new RegExp(`(?:^|[，,;；。\\n])\\s*(?:单位类型|兵种|类型)${intentAssignment}(${unitNames})${unitBoundary}`, 'giu');

export function extractExplicitCardConstraints(source) {
  const normalized = source.normalize('NFKC'), mentions = [];
  for (const match of normalized.matchAll(new RegExp(intentPattern, 'gu'))) {
    const index = intentPhrases.findIndex((_, i) => match.groups[`n${i}`] !== undefined);
    mentions.push({field: intentPhrases[index][0], value: Number(match.groups[`n${index}`]), text: match[0].trim(), index: match.index});
  }
  const head = headUnitPattern.exec(normalized);
  if (head) mentions.push({field: 'unit_class', value: unitAliases[head[1].toLowerCase()], text: head[0], index: 0});
  for (const match of normalized.matchAll(explicitUnitPattern)) mentions.push({field: 'unit_class', value: unitAliases[match[1].toLowerCase()], text: match[0], index: match.index});
  const constraints = {}, ambiguous_fields = [];
  for (const field of Object.keys(intentLabels)) {
    const values = [...new Set(mentions.filter(mention => mention.field === field).map(mention => mention.value))];
    if (values.length === 1) constraints[field] = values[0];
    else if (values.length > 1) ambiguous_fields.push(field);
  }
  return {constraints, ambiguous_fields, mentions};
}

export function checkExplicitNumbers(source, card, expanded = card) {
  const extracted = extractExplicitCardConstraints(source);
  if (extracted.ambiguous_fields.length) fail('SEMANTIC_VALIDATION_FAILED', `描述中的${extracted.ambiguous_fields.map(field => intentLabels[field]).join('、')}包含多个值，请明确最终值。`);
  for (const [field, expected] of Object.entries(extracted.constraints)) {
    if (expected !== card[field]) fail('SEMANTIC_VALIDATION_FAILED', `玩家明确指定${intentLabels[field]}为 ${expected}，但模型生成了 ${card[field]}；请修正或继续澄清。`, 422,
      [{code: 'INTENT_VALUE_MISMATCH', path: `/${field}`, message: `${intentLabels[field]}应为 ${expected}，实际为 ${card[field]}。`}]);
  }
  checkEffectAmounts(source, expanded);
}
export function checkEffectAmounts(source, expanded) {
  for (const [op, regex] of [['damage', /(?:造成\s*(\d+)\s*点?伤害|伤害\s*(\d+)\s*点?)/gu], ['draw', /(?:抽取|抽)\s*(\d+)\s*张/gu], ['heal', /(?:恢复|治疗)\s*(\d+)\s*点?生命/gu]]) {
    const mentioned = [...source.matchAll(regex)].map(m => Number(m[1] ?? m[2]));
    const actual = expanded.abilities.flatMap(a => leaves(a.effects)).filter(e => e.op === op).map(e => e.amount);
    if (mentioned.length > 0 && mentioned.length === actual.length && mentioned.some((n, index) => n !== actual[index])) fail('SEMANTIC_VALIDATION_FAILED', '可识别的技能数值与来源描述不一致，请继续澄清或修正。');
  }
}

function copyInheritanceText(e){return e.inherit_from===undefined?'（保留永久强化）':e.inherit_from.length?'（仅继承'+e.inherit_from.map(r=>'【'+r.name+'】').join('、')+'的永久强化）':'（不继承强化）';}


// Display-only projection. Never changes card definitions, revisions or program hashes.
export function cardPresentation(definition, registry={}, expanded=definition){
 const descriptions=[];const names=[];const printed=structuredClone(definition);printed.keywords=[];
 const builtins=builtinDefinitions;
 for(const ref of definition.keywords??[]){
  const entry=registry[`${ref.id}@${ref.version}`]?.definition??builtins.find(k=>k.id===ref.id&&k.version===ref.version);
  if(entry?.implementation.kind==='configurable')printed.abilities.push(...structuredClone(ref.abilities??[]));
  const name=entry?.name??ref.id;names.push(name+(Object.keys(ref.params??{}).length?' '+Object.values(ref.params).join('/') :''));
  if(entry?.description)descriptions.push(name+'：'+entry.description);
 }
 let text=rulesText(printed);
 // A target is stated on the effect itself; the mandatory/empty-target convention is in details.
 if(definition.play_target)text=text.replace(/^[^\n]*（无目标时跳过选择）。\n/u,'');
 text=shortText(text);
 if(['order','field'].includes(definition.kind))text=text.replace(/^(使用时|生效时)：/u,'');
 if(definition.kind==='counter')text=text.replace(/伏置：([^\n]+?)触发一次[^\n]*\n触发时：/u,'$1：');
 if(/^无额外能力。?$/u.test(text))text='';
 const manual=definition.display_text?.trim()??'';
 const rules_text=manual||[names.join('、'),text].filter(Boolean).join('\n');
 const keyword_names=[...new Set([...builtins.map(k=>k.name),...Object.values(registry).map(e=>e.definition?.name).filter(Boolean)])];
 return {rules_text,detailed_text:(manual?manual+'\n\n实际机制\n':'')+rulesText(expanded)+(descriptions.length?'\n\n词条说明\n'+descriptions.join('\n'):''),keyword_names};
}
