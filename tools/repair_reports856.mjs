// Execute only after the release is verified, with the service stopped and a store backup.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const directory=process.argv[2]??'/var/lib/frontline/data';
const original=JSON.parse(readFileSync(join(directory,'store.json'),'utf8'));
const numbers=new Set(['CZ-000217','CZ-000218','CZ-000219','CZ-000220']);
const store=new Store(directory);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const key of Object.keys(s))delete s[key];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{}))if(numbers.has(d.number)&&d.status!=='resolved'){
   markResolved(s,d,{resolution:'已支持所选单位受到伤害翻倍、仅来自坦克等指定兵种的伤害翻倍、受到战斗伤害+1，以及到下个己方回合开始或下个敌方回合结束的期限。到期只移除本效果，保留其他强化。原卡与对话保留，请按最新意图继续原会话重新生成或校验。',version:'0.8.56'});done.push(d.number);
  }
  return done;
 });console.log(JSON.stringify({reports}));
}finally{await store.close();}
