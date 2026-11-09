// Run with frontline.service stopped; deployment backs up store.json first.
import {randomUUID} from 'node:crypto';
import {Store} from '../server/src/store.js';
import {CardService} from '../server/src/service.js';
import {walkEffects} from '../server/src/validation.js';
import {markResolved} from '../server/src/diagnostics.js';
const store=new Store(process.argv[2]??'/var/lib/frontline/data');await store.init();
const faction='40afae76-e05e-4471-92ce-b48ff89d58a1',hatch='06c0ce91-5cf3-4ff9-97ff-d2f1fe341371';
const resolutions={
 89:'已支持检查同组最近一次伤害的直接击杀结果。可先伤害、固定抽1张，再在确实消灭单位时额外抽1张；未击杀或无目标不多抽。请继续原对话生成。',
 90:'已支持使用阵营限定指令和能力的单位目标。剑阵营使用真实阵营标识，独立于罪孽；装备具体加成、目标敌我与持续时间仍可在原对话完善。',
 91:'已支持按剑阵营筛选装备目标，非该阵营单位不能选中。尚未确认的装备细节继续保留在原对话中。',
 92:'已支持指令/效果选择目标时限定阵营，剑阵营单位可合法筛选。已回答内容保留，可继续生成。',
 93:'已支持抉择分支绑定延迟效果：选择总部强化才登记下一己方回合+4；选抽牌不会触发该延迟强化。可继续原对话生成。',
 94:'已支持抉择分支内的延迟结算。选择总部分支立即+5、下一己方回合+4；选抽2张分支不会获得总部强化。',
 95:'已支持总部+7分支绑定下一己方回合+2，选择抽2张不会登记该延迟效果。已有固定抽牌能力是保留还是替换仍需在原草稿中明确，未擅自修改。',
 96:'已支持抉择选中分支才登记延迟效果：总部立即+7、下一己方回合+2只在总部选项生效。原会话和已回答内容保留。',
 97:'已支持抉择选中分支才登记延迟效果：总部立即+7、下一己方回合+2只在总部选项生效，且仅触发一次。可继续原对话生成。',
 98:'已支持阵亡后原卡回手，精确取回刚阵亡的实体，不复制或误取同名牌。清除临时在场状态，保留仍有效的永久强化；满手烧毁。可继续原对话生成。',
 70:'已验证模型调用额度恢复及会话续作。每日上限500次，北京时间次日00:00恢复；额度限制仍有效，原会话和已回答内容保留，可从原草稿继续。',
 71:'总部初始防御范围仍为1—100。现已在提交模型和保存前提示具体字段范围，保留原输入，不再消耗模型调用后才报结构错误。请将超限数值调整到范围内。',
 72:'总部初始防御范围仍为1—100。现已在提交模型和保存前提示具体字段范围，保留原输入；请将超限数值调整到范围内。',
 73:'已支持无额外效果的指令（noop）：正常支付费用、进入弃牌区并触发打出指令事件，不产生附加效果。可继续原对话生成。',
 77:'已支持不可指定 core.untargetable：禁止双方指令和技能指定，普通攻击仍可选中；范围、随机、自身及自动效果不受影响。可继续原对话生成。',
 78:'已支持不可指定 core.untargetable：禁止双方指令和技能指定，普通攻击仍可选中；范围、随机、自身及自动效果不受影响。可继续原对话生成。',
 79:'已支持按当前回合归属限定效果，可用于己方/对方回合内的阵亡事件，并与其他前提组合。是否包括自身阵亡仍请在原对话确认。',
 80:'已支持逐次比较交战单位当前攻击力：正攻击差每满2点减1伤害，不足2点不计，伤害最低0。支持战斗/效果伤害范围；请在原对话确认适用范围。',
 81:'已支持按当前攻击力差分档减伤（每满2点减2），可以与交战先手组合。每次受伤重新计算；先手和减伤的适用范围仍请在原对话确认。',
 82:'已支持按牌种抽牌及本组抽牌费用奇偶判定。你已确认：各抽一张单位和指令，任意一张打出费用为偶数便令己方总部防御+5，仅一次。原答案保留，可继续生成。',
 83:'已支持按牌种抽牌及本组抽牌费用奇偶判定。各抽一张单位和指令；实际抽到的牌中任意一张打出费用为偶数时，总部防御+5一次。原答案保留，可继续生成。',
 84:'已支持按指令牌筛选抽取，以及查询本牌打出前己方上一张牌的类型。已回答的法术=指令、抽取不足取实际数量等信息保留。',
 85:'已支持查询本牌之前己方上一张打出的牌，跨回合保留、不会把本牌算作上一张；可与按牌种抽取及资源奖励组合。原对话可继续。',
 86:'已支持按牌种抽牌：从牌库顶向下抽取匹配牌，其他牌原序保留，不足取实际数量，保留抽牌统计。法术的具体牌种若尚未确认，可继续原对话确认。',
 87:'已支持按装备来源卡的阵营统计装备件数，可令单位按件持续获得攻击加成；移除装备后同步更新。装备名称和罪孽不会替代阵营判定。原对话中未确认的范围和持续方式可继续确认。',
 88:'已支持延迟至第2—6个后续己方或敌方回合开始，仅结算一次。下下个己方回合对应第2个己方回合；可以保留立即抽2张、到时再抽1张的顺序。'
};
try{
 const source=store.state.cards[hatch]?.at(-1);if(source?.definition.name!=='最后的孵化')throw Error('Hatching identity changed; review migration.');
 const service=new CardService(store,{configured:false});const changes=[];
 for(const versions of Object.values(store.state.cards)){
  const old=versions.at(-1);if(old.definition.faction_id!==faction)continue;
  const def=structuredClone(old.definition);let changed=false;
  for(const a of def.abilities)if(a.trigger==='on_death')for(const e of walkEffects(a.effects))if(e.op==='transfer_card'&&e.source==='self'&&e.mode==='copy'){
   const next=[{card_id:hatch,name:source.definition.name}];if(JSON.stringify(e.inherit_from)!==JSON.stringify(next)){e.inherit_from=next;changed=true;}
  }
  if(!changed)continue;
  const draft=await service.manualDraft(old.owner_id,{request_id:randomUUID(),definition:def});
  await store.transaction(s=>{s.drafts[draft.result.draft_id].provenance={source_kind:'maintenance',source_text:'0.8.42：R公司阵亡复制仅继承最后的孵化永久强化；其余卡牌配置保留。'};});
  const next=await service.confirmCard(old.owner_id,{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash,base_revision:old.revision},old.card_id);
  changes.push({card_id:old.card_id,name:old.definition.name,from:old.revision,to:next.revision});
 }
 const reports=await store.transaction(s=>{
  const done=[];for(const item of Object.values(s.diagnostics??{})){
   const n=Number(item.number?.slice(3));if(!resolutions[n]||item.status==='resolved')continue;
   markResolved(s,item,{resolution:resolutions[n],version:'0.8.42'});done.push(item.number);
  }return done;
 });
 console.log(JSON.stringify({card_revisions:changes,reports},null,2));
}finally{await store.close();}
