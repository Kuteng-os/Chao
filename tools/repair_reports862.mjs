// Run only against an exact backed-up store while the service is stopped.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const groups=[
 [[225],'工坊新增“修改现有效果”模式。可将原本的抽牌替换成坦克抽牌，同时保留费用、基础属性、已有词条和衍生模板；请选择该模式重新理解机制。'],
 [[242],'支持手动选择0至2个友方玉石单位，统一消灭后随机召唤等量弃牌区玉石单位。可提前完成选择；数量不足或后援线已满时尽量结算。'],
 [[259],'支持授予当前友方单位“每次失去烟幕，攻击力+2”的能力。行动解除烟幕时先加攻击再结算伤害；增益在场有效，重复获得与失去烟幕可再次触发。'],
 [[262,263],'支持每次主动攻击后复制被攻击单位加入手牌，被击毁的目标也可复制，攻击总部不产生复制体。复制当前攻击、防御上限和费用，不携带受到的伤害；临时增益不会转成永久。'],
 [[265],'支持根据自身当前烟幕状态持续获得攻击力+2。获得烟幕即生效，失去或被抑制后撤销。']
];
const fixes=new Map(groups.flatMap(([ids,text])=>ids.map(n=>['CZ-'+String(n).padStart(6,'0'),text])));
const dir=process.argv[2]??'/var/lib/frontline/data',original=JSON.parse(readFileSync(join(dir,'store.json'),'utf8'));
const store=new Store(dir);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const key of Object.keys(s))delete s[key];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{}))if(fixes.has(d.number)&&d.status!=='resolved'){
   markResolved(s,d,{resolution:fixes.get(d.number)+' 请刷新工坊，从本报错继续原会话并重新校验。草稿和已登记卡牌未被自动改写。',version:'0.8.62'});done.push(d.number);
  }
  return done;
 });console.log(JSON.stringify({reports,count:reports.length}));
}finally{await store.close();}
