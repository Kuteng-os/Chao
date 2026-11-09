// Run after verified deployment, with the service stopped and a store backup.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const directory=process.argv[2]??'/var/lib/frontline/data';
const original=JSON.parse(readFileSync(join(directory,'store.json'),'utf8'));
const groups=[
 [[215],'已支持精确回手减费：费用变化绑定返回的那张牌实例，本回合内下次打出费用-2；不影响同名手牌，不需要再选手牌，打出或回合结束后失效。'],
 [[216],'已支持己方上一个回合的部署记录，忧郁按罪孽判断，单位之后离场不影响记录；普通召唤不计入。部署时由玩家选择敌方单位撤退，无目标则跳过。']
];
const notes=Object.fromEntries(groups.flatMap(([ids,note])=>ids.map(id=>[id,note])));
if(Object.keys(notes).length!==2)throw Error('Unexpected report set');
const store=new Store(directory);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const key of Object.keys(s))delete s[key];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{})){
   const note=notes[Number(d.number.slice(3))];
   if(note&&d.status!=='resolved'){markResolved(s,d,{resolution:note+' 原卡与对话保留，请继续原会话重新生成或校验。',version:'0.8.55'});done.push(d.number);}
  }
  return done;
 });console.log(JSON.stringify({reports}));
}finally{await store.close();}
