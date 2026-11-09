// Run only against an exact backed-up store while the service is stopped.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const groups=[
 [[266],'支持获得超出资源槽的本回合指挥点；不会增加资源槽，下个己方回合正常重置。'],
 [[267,268,269],'支持相邻单位按罪孽排除筛选。非嫉妒包括未选择罪孽的单位；仅影响本单位同阵线左右相邻的友方单位。'],
 [[270,271],'空白衍生指令可先交给助手完善效果；完成后再保存。空白指令本身仍不可登记。'],
 [[272,273],'支持按本次打出卡牌的罪孽判断条件，覆盖单位、指令和场地。反制伏置不触发，公开生效后计入。'],
 [[274],'开发切换到牌库或初始牌组来源后，会清理衍生卡来源的旧选项。旧草稿请重新切换一次来源再校验。'],
 [[275,276],'已增加仅免疫战斗伤害，主动交战和反击均适用，仍受到技能/指令伤害。请重新生成，勿用超限重甲层数模拟。'],
 [[277,278,279],'支持手牌中同时有指定卡、判断本回合出牌记录，以及仅满足条件时出现的抉择选项。苍/赫可判断本回合上一张是否为另一张并获得茈。修改已有衍生效果请选择“修改现有效果”；未明确时机的原会话仍需补充时机。'],
 [[280],'“受到攻击后”的指定效果现在自动提供触发时选目标配置。旧草稿重新选择该时机和目标即可。']
];
const fixes=new Map(groups.flatMap(([ids,text])=>ids.map(n=>['CZ-'+String(n).padStart(6,'0'),text])));
const dir=process.argv[2]??'/var/lib/frontline/data',original=JSON.parse(readFileSync(join(dir,'store.json'),'utf8'));
const store=new Store(dir);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const key of Object.keys(s))delete s[key];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{}))if(fixes.has(d.number)&&d.status!=='resolved'){
   markResolved(s,d,{resolution:fixes.get(d.number)+' 请刷新工坊，从本报错继续原会话并重新校验。草稿和已登记卡牌未被自动改写。',version:'0.8.63'});done.push(d.number);
  }
  return done;
 });console.log(JSON.stringify({reports,count:reports.length}));
}finally{await store.close();}
