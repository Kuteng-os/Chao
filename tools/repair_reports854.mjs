// Run after verified deployment, with the service stopped and a store backup.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const directory=process.argv[2]??'/var/lib/frontline/data';
const original=JSON.parse(readFileSync(join(directory,'store.json'),'utf8'));
const groups=[
 [[199,200],'已加入“敌方攻击友方单位”反制，可在交战前分别消灭攻击者与被攻击者，正常结算阵亡。请将反制触发下拉框改为该时机后继续生成。'],
 [[201,202,203],'已支持双方手牌、弃牌和在场单位洗回牌库，各自选择单位免费部署，场地单位数量上限及持续攻防/词条光环。总部和场地不洗回，部署与召唤效果分别结算。'],
 [[205],'单位现可给全体友方提供固定光环；仅增加防御上限不会治疗，来源离场或抑制后光环撤销。'],
 [[206],'“待解放”已经登记，可从词条档案引用现有词条或进入其编辑入口修改；重复登记仍提示名称冲突，不会创建两份同名词条。'],
 [[207,209],'已支持原地解放为本牌衍生形态、替换原能力，保留行动/压制状态，每次在场一次，离场恢复原型；自身撤退/回手可单独筛选。'],
 [[208,210],'已补齐解放形态与自身事件规则；模型输出为空或截断时以更大预算重试一次，失败后可以继续讨论或重新生成。'],
 [[211,212],'已支持条件额外打出费：按己方回合序号分档，只取最高档，打出前展示并检查完整费用，费用不足不能打出。'],
 [[213,214],'生成失败、未支持或取消后可以继续修改原复述并重新确认；仍校验原配置和复述哈希，避免串卡或重复并发生成。']
];
const notes=Object.fromEntries(groups.flatMap(([ids,note])=>ids.map(id=>[id,note])));
if(Object.keys(notes).length!==15)throw Error('Unexpected report set');
const store=new Store(directory);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const key of Object.keys(s))delete s[key];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{})){
   const note=notes[Number(d.number.slice(3))];
   if(note&&d.status!=='resolved'){markResolved(s,d,{resolution:note+' 原卡与对话保留，请继续原会话重新生成或校验。',version:'0.8.54'});done.push(d.number);}
  }
  return done;
 });console.log(JSON.stringify({reports}));
}finally{await store.close();}
