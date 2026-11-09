// Execute with the service stopped, as its service account, after tests and backup.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const directory=process.argv[2]??'/var/lib/frontline/data';
const original=JSON.parse(readFileSync(join(directory,'store.json'),'utf8'));
const groups=[[[184,185],'已支持逐卡配置的解放词条：登记词条后，每张卡独立填写触发、前提、强化和即时效果，也可由 DeepSeek 补齐。满足条件时每次在场触发一次，回手重置，在场强化离场消失。']];
const notes=Object.fromEntries(groups.flatMap(([ids,text])=>ids.map(id=>[id,text])));
if(Object.keys(notes).length!==2)throw Error('Unexpected report set');
const store=new Store(directory);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const key of Object.keys(s))delete s[key];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{})){
   const text=notes[Number(d.number.slice(3))];
   if(text&&d.status!=='resolved'){markResolved(s,d,{resolution:text+' 原卡与对话保留，请继续原会话重新生成或校验。',version:'0.8.52'});done.push(d.number);}
  }
  return done;
 });
 console.log(JSON.stringify({reports}));
}finally{await store.close();}
