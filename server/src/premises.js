import {fail} from './codec.js';
export const premiseStats={enemy_deaths_this_turn:'本回合敌方单位阵亡数',friendly_deaths_this_turn:'本回合友方单位阵亡数',event_damage:'本次受到的伤害',friendly_turn_number:'己方回合序号',enemy_turn_number:'敌方回合序号',source_destroyed_count:'本卡本次消灭的单位数',enemy_unit_count:'敌方在场单位数',friendly_unit_count:'己方在场单位数',other_friendly_unit_count:'其他友方在场单位数',enemy_front_count:'敌方前线单位数',friendly_front_count:'己方前线单位数',enemy_support_count:'敌方后援线单位数',friendly_support_count:'己方后援线单位数',enemy_hand_count:'敌方手牌数',friendly_hand_count:'己方手牌数',enemy_deck_count:'敌方牌组张数',friendly_deck_count:'己方牌组张数',enemy_hq_health:'敌方总部防御力',friendly_hq_health:'己方总部防御力',enemy_kredits:'敌方剩余资源',friendly_kredits:'己方剩余资源',source_attack:'自身当前攻击力',source_health:'自身当前防御力',source_base_health:'本卡初始防御力'};
export const premiseKeywordNames={"core.blitz": "突击", "core.guard": "守护", "core.ambush": "伏击", "core.fury": "奋战", "core.smokescreen": "烟幕", "core.shock": "冲击", "core.mobilize": "动员", "core.alpine": "山地", "core.salvage": "缴获", "core.immune": "免疫", "core.untargetable": "不可指定", "core.revive": "复生"};
const unitTargets=['self','chosen','trigger_unit','attack_target'];
export const validStackName=s=>typeof s==='string'&&Array.from(s).length>=1&&Array.from(s).length<=32&&s===s.trim()&&!/[\u0000-\u001f\u007f-\u009f]/.test(s);
export const unitValue=v=>v?.stack_count??v?.unit_stat;
/** The highest current attack or health among one side's units; the HQ never counts and an empty side reads 0. */
export const validMaxUnitStat=v=>!!v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).join()==='max_unit_stat'&&!!v.max_unit_stat&&typeof v.max_unit_stat==='object'&&Object.keys(v.max_unit_stat).sort().join()==='side,stat'&&['ally','enemy'].includes(v.max_unit_stat.side)&&['attack','health'].includes(v.max_unit_stat.stat);
export const maxUnitStatText=v=>`${v.max_unit_stat.side==='ally'?'友方':'敌方'}单位中最高的${v.max_unit_stat.stat==='attack'?'攻击力':'防御力'}`;
export function validUnitValue(v){const q=unitValue(v);return !!q&&Object.keys(v).length===1&&Object.keys(q).sort().join()===(v.stack_count?'stack,target':'stat,target')&&['self','chosen','trigger_unit','creator','attack_target','effect_target'].includes(q.target)&&(v.stack_count?validStackName(q.stack):['attack','health','base_attack','base_health','operation_cost','cost','max_health'].includes(q.stat));}
export function unitValueText(v){const q=unitValue(v),who={self:'自身',chosen:'所选单位',trigger_unit:'触发单位',creator:'生成本卡的单位',attack_target:'攻击目标',effect_target:'受影响单位'}[q.target];return who+(v.stack_count?'的'+(q.stack==='heavy_armor'?'重甲':q.stack)+'层数':{attack:'当前攻击力',health:'当前防御力',base_attack:'初始攻击力',base_health:'初始防御力',operation_cost:'行动费用',cost:'打出费用',max_health:'防御上限'}[q.stat]);}
const compareNames={gt:'大于',gte:'不少于',eq:'等于',ne:'不等于',lte:'不多于',lt:'小于'};
export function validatePremise(p) {
  let nodes=0;
  const invalid=()=>fail('INVALID_PREMISE','条件无效或过于复杂：最多4层、24个节点。',422);
  const count=v=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).join()==='count_units'&&validUnitCount(v.count_units);
  const value=v=>validUnitValue(v)||count(v)||validMaxUnitStat(v)||Number.isInteger(v)&&v>=-100&&v<=100 || v&&typeof v==='object'&&Object.keys(v).join()==='stat'&&Object.hasOwn(premiseStats,v.stat);
  const visit=(v,depth)=>{
    if(!v||typeof v!=='object'||Array.isArray(v)||++nodes>24||depth>4)invalid();
    const keys=Object.keys(v).sort().join();
    if(v.test==='deployed_last_turn'){if(keys!=='filter,player,test'||!['owner','opponent'].includes(v.player)||!v.filter||Object.keys(v.filter).some(k=>!['card_name','name_contains','unit_classes','faction_id','sin','sins','exclude_sins'].includes(k))||!validUnitCount({...v.filter,side:'any'}))invalid();}
    else if(v.test==='unit_matches'){if(keys!=='filter,target,test'||!unitTargets.includes(v.target)||!validUnitCount({...v.filter,side:'any'}))invalid();}
    else if(v.test==='unit_side'){if(keys!=='side,target,test'||!unitTargets.includes(v.target)||!['ally','enemy'].includes(v.side))invalid();}
    else if(v.test==='deck_top'){if(keys!=='parity,player,test'||!['owner','opponent'].includes(v.player)||!['even','odd'].includes(v.parity))invalid();}
    else if(v.test==='previous_card'){if(Object.keys(v).some(k=>!['test','kind','player','card_name','filter','this_turn'].includes(k))||!['unit','order','field'].includes(v.kind)||!['owner','opponent'].includes(v.player)||v.card_name!==undefined&&!validCardFilter({card_name:v.card_name})||v.filter!==undefined&&!validCardFilter(v.filter)||v.this_turn!==undefined&&typeof v.this_turn!=='boolean')invalid();}
    else if(['event_card','hand_contains','played_this_turn'].includes(v.test)){if(Object.keys(v).some(k=>!(v.test==='event_card'?['test','filter']:['test','filter','player','min']).includes(k))||!validCardFilter(v.filter)||v.test!=='event_card'&&!['owner','opponent'].includes(v.player)||v.min!==undefined&&(!Number.isInteger(v.min)||v.min<1||v.min>100))invalid();}
    else if(v.test==='destroyed_by'){if(keys!=='test,unit_classes'||!validUnitCount({side:'any',unit_classes:v.unit_classes}))invalid();}
    else if(v.test==='turn_owner'){if(keys!=='side,test'||!['owner','opponent'].includes(v.side))invalid();}
    else if(v.test==='compare'){if(!['cmp,left,right,test','cmp,left,right,right_offset,test'].includes(keys)||v.right_offset!==undefined&&(!Number.isInteger(v.right_offset)||v.right_offset< -100||v.right_offset>100)||!value(v.left)||!value(v.right)||!Object.hasOwn(compareNames,v.cmp))invalid();}
    else if(v.test==='unit_keyword'){if(keys!=='keyword_id,state,target,test'||!unitTargets.includes(v.target)||!(/^[a-z][a-z0-9_]*[.][a-z][a-z0-9_]*$/.test(v.keyword_id))||!['printed','current','consumed'].includes(v.state))invalid();}
    else if(v.test==='unit_state'){if(keys!=='state,target,test'||!unitTargets.includes(v.target)||!['is_liberated','has_attacked','is_veteran','in_front','in_support'].includes(v.state))invalid();}
    else if(v.test==='not'){if(keys!=='item,test')invalid();visit(v.item,depth+1);}
    else if(['all','any'].includes(v.test)){if(keys!=='items,test'||!Array.isArray(v.items)||!v.items.length||v.items.length>6)invalid();v.items.forEach(x=>visit(x,depth+1));}
    else invalid();
  };visit(p,1);return p;
}
export function premiseUnitQueries(p){
 if(!p)return [];
 if(p.test==='compare')return [p.left,p.right].filter(unitValue).map(v=>({test:'unit_value',target:unitValue(v).target}));
 return ['unit_keyword','unit_state','unit_matches','unit_side'].includes(p.test)?[p]:[...(p.items??[]).flatMap(premiseUnitQueries),...(p.item?premiseUnitQueries(p.item):[])];
}
export function premiseText(p){
 if(p.test==='deployed_last_turn')return (p.player==='owner'?'己方':'敌方')+'上个回合部署过'+(p.filter.card_name?'【'+p.filter.card_name+'】':p.filter.name_contains?'名称含【'+p.filter.name_contains+'】的':'')+(p.filter.faction_id?'指定阵营的':'')+filterDetail(p.filter)+unitClassText(p.filter.unit_classes);
 if(p.test==='unit_matches')return ({self:'自身',chosen:'所选单位',trigger_unit:'触发单位',attack_target:'攻击目标'})[p.target]+'是'+filterDetail(p.filter)+unitClassText(p.filter.unit_classes);
 if(p.test==='unit_side')return '所查单位属于'+(p.side==='ally'?'己方':'敌方');
 if(p.test==='deck_top')return (p.player==='owner'?'己方':'敌方')+'牌库顶费用为'+(p.parity==='even'?'偶数':'奇数');
 if(p.test==='destroyed_by')return '被'+unitClassText(p.unit_classes)+'消灭';
 if(p.test==='previous_card')return (p.player==='owner'?'己方':'敌方')+(p.this_turn?'本回合':'')+'上一张打出的牌是'+(p.card_name?'【'+p.card_name+'】':cardFilterText(p.filter??{kind:p.kind}));
 if(p.test==='event_card')return '打出的牌为'+cardFilterText(p.filter);
 if(['hand_contains','played_this_turn'].includes(p.test))return (p.player==='owner'?'己方':'敌方')+(p.test==='hand_contains'?'手牌中有':'本回合使用过')+(p.min??1)+'张'+cardFilterText(p.filter);
 if(p.test==='turn_owner')return p.side==='owner'?'己方回合':'对方回合';
 if(['unit_keyword','unit_state'].includes(p.test)){
  const who={self:'自身',chosen:'所选单位',trigger_unit:'触发单位',attack_target:'攻击目标'}[p.target];
  if(p.test==='unit_state')return who+({is_liberated:'已解放',is_veteran:'是老兵',in_front:'位于前线',in_support:'位于支援阵线',has_attacked:'本次在场期间已主动攻击'})[p.state];
  return who+{printed:'卡面原生具有',current:'当前具有',consumed:'本次在场期间已消耗过'}[p.state]+(premiseKeywordNames[p.keyword_id]??p.keyword_id);
 }
  if(p.test==='not')return `不满足（${premiseText(p.item)}）`;
  if(['all','any'].includes(p.test))return p.items.map(x=>`（${premiseText(x)}）`).join(p.test==='all'?'且':'或');
  const text=v=>unitValue(v)?unitValueText(v):v?.max_unit_stat?maxUnitStatText(v):v?.count_units?unitCountText(v.count_units):v?.stat?premiseStats[v.stat]:String(v);
  return text(p.left)+compareNames[p.cmp]+text(p.right)+(p.right_offset?(p.right_offset>0?'+'+p.right_offset:p.right_offset):'');
}

export const classGroups={air:['fighter','bomber'],ground:['infantry','tank','artillery']};
export function validUnitCount(s){return !!s&&typeof s==='object'&&!Array.isArray(s)&&Object.keys(s).every(k=>['generated_by','is_liberated','without_keyword','side','row','unit_classes','card_name','name_contains','distinct_by','faction_id','keyword_id','attack','health','attack_parity','adjacent_to','is_veteran','sin','sins','exclude_sins','cost','kind'].includes(k))&&(!Object.hasOwn(s,'is_liberated')||typeof s.is_liberated==='boolean')&&(!s.without_keyword||/^[a-z][a-z0-9_]*[.][a-z][a-z0-9_]*$/.test(s.without_keyword))&&(!s.generated_by||s.generated_by==='salvage')&&(!s.kind||s.kind==='unit')&&validSinFilter(s)&&(!Object.hasOwn(s,'is_veteran')||typeof s.is_veteran==='boolean')&&(!s.faction_id||/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(s.faction_id))&&(!s.keyword_id||/^[a-z][a-z0-9_]*[.][a-z][a-z0-9_]*$/.test(s.keyword_id))&&['attack','health','cost'].every(k=>!Object.hasOwn(s,k)||s[k]&&Object.keys(s[k]).sort().join()==='cmp,value'&&Object.hasOwn(compareNames,s[k].cmp)&&Number.isInteger(s[k].value)&&s[k].value>=0&&s[k].value<=100)&&(!Object.hasOwn(s,'attack_parity')||['even','odd'].includes(s.attack_parity))&&(!Object.hasOwn(s,'adjacent_to')||['self','chosen'].includes(s.adjacent_to))&&['card_name','name_contains'].every(k=>!Object.hasOwn(s,k)||typeof s[k]==='string'&&Array.from(s[k]).length>=1&&s[k]===s[k].trim()&&Array.from(s[k]).length<=64&&!/[\u0000-\u001f\u007f-\u009f]/.test(s[k]))&&(!Object.hasOwn(s,'distinct_by')||s.distinct_by==='name')&&['ally','enemy','any'].includes(s.side)&&(!Object.hasOwn(s,'row')||['any','front','support'].includes(s.row))&&(!Object.hasOwn(s,'unit_classes')||Array.isArray(s.unit_classes)&&s.unit_classes.length>0&&s.unit_classes.length<=5&&new Set(s.unit_classes).size===s.unit_classes.length&&s.unit_classes.every(c=>['infantry','tank','artillery','fighter','bomber'].includes(c)));}
export function unitClassText(list){if(!list?.length||list.length===5)return '单位';const k=[...list].sort().join();if(k===[...classGroups.air].sort().join())return '空军';if(k===[...classGroups.ground].sort().join())return '陆军';return list.map(c=>({infantry:'步兵',tank:'坦克',artillery:'炮兵',fighter:'战斗机',bomber:'轰炸机'})[c]).join('、');}
export function unitCountText(s){return ({ally:'己方',enemy:'敌方',any:'双方'})[s.side]+({any:'在场',front:'前线',support:'后援线'})[s.row??'any']+(s.card_name?'【'+s.card_name+'】':s.name_contains?'名称含【'+s.name_contains+'】的':'')+filterDetail(s)+unitClassText(s.unit_classes)+(s.distinct_by==='name'?'种数（同名只计一次）':'数');}

export function filterDetail(s){return (s.generated_by==='salvage'?'缴获的':'')+(Object.hasOwn(s,'is_liberated')?(s.is_liberated?'已解放的':'未解放的'):'')+(s.without_keyword?'不具有'+(premiseKeywordNames[s.without_keyword]??s.without_keyword)+'的':'')+sinFilterText(s)+(s.cost?'费用'+compareNames[s.cost.cmp]+s.cost.value+'的':'')+(Object.hasOwn(s,'is_veteran')?(s.is_veteran?'老兵':'非老兵'):'')+(s.adjacent_to?({self:'自身',chosen:'所选单位'})[s.adjacent_to]+'左右相邻的':'')+(s.keyword_id?'具有'+(premiseKeywordNames[s.keyword_id]??s.keyword_id)+'的':'')+['attack','health'].filter(k=>s[k]).map(k=>(k==='attack'?'攻击力':'防御力')+compareNames[s[k].cmp]+s[k].value+'的').join('')+(s.attack_parity?'攻击力为'+(s.attack_parity==='even'?'偶':'奇')+'数的':'');}

const sinNames={wrath:'暴怒',lust:'色欲',sloth:'怠惰',gluttony:'暴食',gloom:'忧郁',pride:'傲慢',envy:'嫉妒',null:'无罪孽'};
export const validSinFilter=f=>(!Object.hasOwn(f,'sin')||Object.hasOwn(sinNames,String(f.sin)))&&['sins','exclude_sins'].every(k=>!Object.hasOwn(f,k)||Array.isArray(f[k])&&f[k].length>=1&&f[k].length<=8&&new Set(f[k]).size===f[k].length&&f[k].every(x=>Object.hasOwn(sinNames,String(x))));
export const sinFilterText=f=>(Object.hasOwn(f,'sin')?sinNames[f.sin]+'的':'')+(f.sins?f.sins.map(x=>sinNames[x]).join('、')+'的':'')+(f.exclude_sins?'非'+f.exclude_sins.map(x=>sinNames[x]).join('、')+'的':'');
export const validCardFilter=f=>!!f&&typeof f==='object'&&!Array.isArray(f)&&Object.keys(f).length>0&&Object.keys(f).every(k=>['card_name','name_contains','kind','sin','sins','exclude_sins'].includes(k))&&validSinFilter(f)&&(!f.kind||['unit','order','field','counter'].includes(f.kind))&&['card_name','name_contains'].every(k=>!Object.hasOwn(f,k)||typeof f[k]==='string'&&Array.from(f[k]).length>=1&&Array.from(f[k]).length<=64&&f[k]===f[k].trim()&&!/[\u0000-\u001f\u007f-\u009f]/.test(f[k]));
export const cardFilterText=f=>(f.card_name?'【'+f.card_name+'】':f.name_contains?'名称含【'+f.name_contains+'】的':'')+sinFilterText(f)+({unit:'单位',order:'指令',field:'场地',counter:'反制'}[f.kind]??'牌');
