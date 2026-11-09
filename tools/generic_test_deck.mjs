// A playable baseline, not a claim of competitive balance or exhaustive rule coverage.
export const TEST_DECK_NAME = '通用测试牌组';
export function genericTestDeck(factionId) {
  const ref = (id,params={}) => ({id,version:1,params});
  const ability = (trigger,effects) => ({trigger,effects});
  const base = (name,kind,cost,rarity) => ({schema_version:'1.0.0',ruleset_version:'frontline-1',name:'测试·'+name,faction_id:factionId,flavor_text:'',kind,cost,rarity,unit_class:null,operation_cost:0,attack:0,health:0,keywords:[],abilities:[],tokens:[],play_target:null,appearance:{emblem:kind}});
  const unit = (name,count,cls,cost,atk,hp,op=1,keywords=[],abilities=[]) => ({count,definition:{...base(name,'unit',cost,count===1?'elite':count===3?'limited':'standard'),unit_class:cls,operation_cost:op,attack:atk,health:hp,keywords,abilities,appearance:{emblem:cls}}});
  const order = (name,count,cost,effects,play_target=null) => ({count,definition:{...base(name,'order',cost,count===4?'standard':'limited'),play_target,abilities:[ability('on_play',effects)]}});
  const counter = (name,cost,counter_trigger,effects) => ({count:2,definition:{...base(name,'counter',cost,'special'),counter_trigger,abilities:[ability('on_reveal',effects)]}});
  return [
    unit('步兵班',4,'infantry',2,2,3),
    unit('守备步兵',3,'infantry',3,2,5,1,[ref('core.guard')]),
    unit('突击坦克',4,'tank',4,4,3,1,[ref('core.blitz')]),
    unit('野战炮',3,'artillery',3,2,3),
    unit('战斗机',3,'fighter',4,3,4),
    unit('轰炸机',3,'bomber',5,4,4,2),
    unit('重甲步兵',3,'infantry',3,2,4,1,[ref('standard.heavy_armor',{x:1})]),
    unit('指挥车',1,'tank',6,4,6,1,[],[ability('on_play',[{op:'modify_stats',target:'all_friendly_units',attack_delta:1,health_delta:1,duration:'battle'}])]),
    order('补给',4,2,[{op:'draw',player:'owner',amount:2}]),
    order('定点打击',3,2,[{op:'damage',target:'chosen',amount:3}],{side:'enemy',row:'any'}),
    order('总部修复',3,1,[{op:'heal',target:'own_hq',amount:4}]),
    counter('部署伏击',1,'enemy_unit_deployed',[{op:'damage',target:'trigger_unit',amount:2}]),
    counter('指令干扰',1,'enemy_order_played',[{op:'cancel_action'}]),
    counter('总部防线',1,'enemy_hq_attacked',[{op:'cancel_action'},{op:'damage',target:'trigger_unit',amount:1}]),
  ];
}
