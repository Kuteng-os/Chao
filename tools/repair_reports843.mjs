// Run offline after taking a fresh store backup. No card definitions are changed.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
const store=new Store(process.argv[2]??'/var/lib/frontline/data');await store.init();
const resolutions={
 99:'已支持阵亡原卡回手，手牌满则改放己方牌库顶；保留永久强化，清除临时在场状态。可继续原会话。',
 100:'已支持精确取回刚阵亡的原卡，手牌满则烧毁。无需以阵亡 self 目标实现，不会复制或误取同名卡。可继续原会话。',
 101:'已支持按目标当前有效词条追加伤害。对守护+2与原伤害合并为一个伤害包，不另造第二次伤害。可继续原会话确认范围并生成。',
 102:'已支持按目标兵种为同一次伤害增加数值：步兵额外+2，其他目标不变；附加兵种身份也参与筛选。结算次数的原澄清问题仍可回答。',
 103:'已支持按本次伤害直接击杀的单位数量逐次增加总部防御或结算其他效果。总部加上限还是仅治疗等尚未确认的细节仍可在原对话完善。',
 104:'已支持按本次直接击杀数量逐次增加己方总部当前防御和上限；原会话及后续已回答的内容保留。',
 105:'已支持按本次对双方单位的伤害直接击杀数，逐个为己方总部当前防御和上限+1；不计算其他连锁阵亡。原答案保留。',
 106:'已支持一次对双方所有单位造成伤害，并按直接击杀数在己方支援阵线召唤衍生单位；不要求在死者原位置召唤。请继续原会话。',
 107:'已支持对双方单位群体伤害后，每直接击杀一个单位就在己方支援线召唤一名指定衍生单位。新召唤单位不会再次受到本次群体伤害，满线不额外召唤。',
 108:'已统一0费卡的表单、机制理解输入和正式卡校验，不再要求把0费改成1费。原基础数值保留，可以重新提交。',
 109:'已支持由控制者手选一张符合条件的手牌降低打出费用，支持所有卡牌类型、叠加及最低0。持续时间等尚未确认的细节仍可继续原对话。',
 110:'已支持手选卡牌减费：留在手牌期间、本回合或整局永久可分别表达。持续时间和范围继续以原会话确认内容为准。',
 111:'已支持按元素阵营筛选手牌并由玩家选择减费，所有类型可参与；离手失效与永久可分别设置，原对话可继续。',
 112:'已支持你已确认的机制：选择一张元素阵营手牌（所有类型），其留在手牌期间费用-1，可叠加、最低0；离开手牌失效。原答案保留。',
 113:'已支持从己方牌库展示全部符合玉石阵营和单位条件的候选，由玩家选一张移出牌库并召唤至己方支援线。候选仅本人可见；满线或无候选不消耗卡牌。'
};
try{const done=await store.transaction(s=>{const done=[];for(const d of Object.values(s.diagnostics??{})){const message=resolutions[Number(d.number.slice(3))];if(message&&d.status!=='resolved'){markResolved(s,d,{resolution:message,version:'0.8.43'});done.push(d.number);}}return done;});console.log(JSON.stringify({reports:done}));}finally{await store.close();}
