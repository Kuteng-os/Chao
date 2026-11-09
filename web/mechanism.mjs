import {esc,label} from './model.mjs';
export function conversationUI(turns){
  if(!turns.length)return '';
  return `<details class="mechanism-history"><summary>对话记录 · ${turns.length} 条</summary><div class="mechanism-turns">${turns.map(t=>`<article class="mechanism-turn ${t.role==='user'?'from-player':'from-assistant'}"><strong>${t.role==='user'?'你':'机制助手'}</strong><p class="rules">${esc(t.text)}</p></article>`).join('')}</div></details>`;
}
export function passUI(passed){return passed?`<div class="mechanism-pass" role="status"><span aria-hidden="true">✓</span><strong>通过</strong><p>效果已校验并加入此牌</p></div>`:'';}
export function premiseSummary(p){
 if(p.test==='deployed_last_turn')return (p.player==='owner'?'己方':'敌方')+'上个回合部署过'+(p.filter.sin?({wrath:'暴怒',lust:'色欲',sloth:'怠惰',gluttony:'暴食',gloom:'忧郁',pride:'傲慢',envy:'嫉妒'})[p.filter.sin]+'的':'')+countText({...p.filter,side:'any'}).replace(/^双方在场/,'').replace(/数$/,'');
 if(p.test==='unit_side')return label(p.target)+'属于'+(p.side==='ally'?'己方':'敌方');
 if(p.test==='unit_matches')return label(p.target)+'符合：'+countText({...p.filter,side:'any'}).replace(/数$/,'');
 if(p.test==='deck_top')return (p.player==='owner'?'己方':'敌方')+'牌库顶费用为'+(p.parity==='even'?'偶数':'奇数');
 if(p.test==='previous_card')return (p.player==='owner'?'己方':'敌方')+'上一张打出的牌是'+({unit:'单位',order:'指令',field:'场地'})[p.kind];
 if(p.test==='destroyed_by')return '被'+p.unit_classes.map(label).join('、')+'消灭';
 if(p.test==='turn_owner')return p.side==='owner'?'己方回合':'对方回合';
  if(['unit_keyword','unit_state'].includes(p.test)){
    const who={self:'自身',chosen:'所选单位',trigger_unit:'触发单位',attack_target:'攻击目标'}[p.target];
    if(p.test==='unit_state')return who+({has_attacked:'本次在场期间已主动攻击',is_veteran:'是老兵',in_front:'位于前线',in_support:'位于支援阵线'})[p.state];
    return who+{printed:'卡面原生具有',current:'当前具有',consumed:'本次在场期间已消耗过'}[p.state]+label(p.keyword_id);
  }
  const names={event_damage:"本次受到的伤害",friendly_turn_number:"己方回合序号",enemy_turn_number:"敌方回合序号",source_destroyed_count:'本卡本次消灭的单位数',enemy_unit_count:'敌方单位数',friendly_unit_count:'友方单位数',other_friendly_unit_count:'其他友方单位数',enemy_front_count:'敌方前线单位数',friendly_front_count:'友方前线单位数',enemy_support_count:'敌方后援线单位数',friendly_support_count:'友方后援线单位数',enemy_hand_count:'敌方手牌数',friendly_hand_count:'己方手牌数',enemy_deck_count:'敌方牌组张数',friendly_deck_count:'己方牌组张数',enemy_hq_health:'敌方总部防御力',friendly_hq_health:'己方总部防御力',enemy_kredits:'敌方剩余资源',friendly_kredits:'己方剩余资源',source_attack:'自身当前攻击力',source_health:'自身当前防御力',source_base_health:'本卡初始防御力'};
  if(p.test==='not')return `不满足（${premiseSummary(p.item)}）`;
  if(['all','any'].includes(p.test))return p.items.map(x=>`（${premiseSummary(x)}）`).join(p.test==='all'?'且':'或');
  const text=v=>v?.stack_count?label(v.stack_count.target)+'的'+label(v.stack_count.stack)+'层数':v?.unit_stat?label(v.unit_stat.target)+({attack:'当前攻击力',health:'当前防御力',base_attack:'初始攻击力',base_health:'初始防御力',operation_cost:'行动费用',cost:'打出费用',max_health:'防御上限'}[v.unit_stat.stat]):v?.count_units?countText(v.count_units):v?.stat?names[v.stat]??v.stat:String(v);
  return `${text(p.left)}${{gt:'大于',gte:'不少于',eq:'等于',ne:'不等于',lte:'不多于',lt:'小于'}[p.cmp]}${text(p.right)}`;
}

export function countText(s){const c=s.unit_classes??[],set=new Set(c),kind=!c.length||c.length===5?'单位':c.length===2&&set.has('fighter')&&set.has('bomber')?'空军':c.length===3&&['infantry','tank','artillery'].every(x=>set.has(x))?'陆军':c.map(label).join('、');return {ally:'己方',enemy:'敌方',any:'双方'}[s.side]+{any:'在场',front:'前线',support:'后援线'}[s.row??'any']+(s.card_name?'【'+s.card_name+'】':s.name_contains?'名称含【'+s.name_contains+'】的':'')+(s.adjacent_to?label(s.adjacent_to)+'左右相邻的':'')+(Object.hasOwn(s,'is_veteran')?(s.is_veteran?'老兵':'非老兵'):'')+(s.keyword_id?'具有'+keywordName(s.keyword_id)+'的':'')+['attack','health'].filter(k=>s[k]).map(k=>(k==='attack'?'攻击':'防御')+cmpNames[s[k].cmp]+s[k].value+'的').join('')+(s.attack_parity?'攻击为'+(s.attack_parity==='even'?'偶':'奇')+'数的':'')+kind+(s.distinct_by==='name'?'种数（同名只计一次）':'数');}

const cmpNames={gt:'大于',gte:'不少于',eq:'等于',ne:'不等于',lte:'不多于',lt:'小于'};
const keywordName=id=>({'core.guard':'守护','core.blitz':'闪击','core.ambush':'伏击','core.smokescreen':'烟幕','core.shock':'冲击','core.immune':'免疫','core.fury':'奋战','core.mobilize':'动员','core.alpine':'山地','core.salvage':'缴获','core.untargetable':'不可指定'})[id]??label(id);
