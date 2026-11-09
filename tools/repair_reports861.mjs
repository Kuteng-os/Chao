// Run only against an exact backed-up store while the service is stopped.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const groups=[
 [[223,224,226],'已核对罪孽坦克筛选、区域回退与整局部署监听。修复内层 trigger_unit 被外层指令时机误判，更新助手规则；真实生成流程已验证。'],
 [[227,237],'支持同一实际卡整局只接受一次指定强化：返手重下不重复，多次使用相同来源指令不重复，新复制卡另算。'],
 [[228,229,241],'支持来源在场时对单位及总部的伤害增减光环，可区分伤害来源、指令和兵种；离场或抑制立即撤销。'],
 [[230],'新增整次被攻击后触发，包含实际受到0伤害的情形；来源需存活，治疗在交战后结算。'],
 [[231],'生成助手可引用卡库中已登记卡牌的冻结效果与衍生模板，不必重新猜测【偶遇】的内容；同名不同版本仍需确认。'],
 [[232],'解放及满足条件后可以继续抉择，选择授予不同的关键词或属性，不再仅限部署时。'],
 [[233],'开发支持从当前实际牌库抽取候选，选中后移出那一张原牌，未选候选不离开牌库。'],
 [[234],'条件比较支持双方总部防御差，包括恰好高8点的边界。'],
 [[235,236],'单位筛选增加已解放/未解放，独立于是否老兵，可用于排除已解放单位的范围伤害。'],
 [[238,239],'已确认当前模型服务可以正常完成机制复述和生成；此前的余额不足响应已恢复。'],
 [[240],'半额伤害仍需作者选择向上或向下取整；编辑器现在会在提交前明确提示缺少取整方式，不再只给通用结构错误。'],
 [[243,244,245,258],'暂时移除支持后续指定的己方/敌方回合开始或结束归还，并可清除临时强化、保留永久强化及原有受伤和行动次数。'],
 [[246],'只修改防御上限现在支持负值，当前防御会限制在新上限以内；0值仍会明确报错。'],
 [[247],'光环支持“其他友方单位”，正确排除来源自身，离场后增益撤销。'],
 [[248,249,250],'新增击杀敌方单位后的事件及被消灭者快照，可复制死者入手或将自身变为其复制；继承模式仍由作者确认。'],
 [[251],'支持交战时以对方当前攻击力计算本单位伤害，同时覆盖主动攻击和反击，对总部仍使用自身攻击力。'],
 [[252,253],'支持本回合阵亡数条件费用，以及仅在手牌中监听阵亡并修改本卡费用；场上行动费变化使用独立能力组。'],
 [[254],'补齐同阵线战斗机对轰炸机的保护，以及单卡绕过该保护的内置词条；其他攻击限制保持有效。'],
 [[255],'新增仅禁止指令指定的词条。普通攻击和单位技能仍可选择，范围与随机效果正常。'],
 [[256,257,264],'新增监听己方单位推进前线事件，自身与触发单位为同一实例时只加一次。持续时间仍需在原会话中确认。'],
 [[260],'抽牌后的减费可以精确绑定本组实际抽入手牌的实例，不影响之前已有的同名手牌。'],
 [[261],'单位筛选支持缴获来源标记，可在部署缴获单位后同时强化该单位和监听者。']
];
const fixes=new Map(groups.flatMap(([ids,text])=>ids.map(n=>['CZ-'+String(n).padStart(6,'0'),text])));
const dir=process.argv[2]??'/var/lib/frontline/data',original=JSON.parse(readFileSync(join(dir,'store.json'),'utf8'));
const store=new Store(dir);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const key of Object.keys(s))delete s[key];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{}))if(fixes.has(d.number)&&d.status!=='resolved'){
   markResolved(s,d,{resolution:fixes.get(d.number)+' 请刷新工坊，从本报错继续原会话并重新校验。草稿和已登记卡牌未被自动改写。',version:'0.8.61'});done.push(d.number);
  }
  return done;
 });console.log(JSON.stringify({reports,count:reports.length}));
}finally{await store.close();}
