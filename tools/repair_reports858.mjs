// Run after verification, with the service stopped and an exact store backup.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const dir=process.argv[2]??'/var/lib/frontline/data',original=JSON.parse(readFileSync(join(dir,'store.json'),'utf8'));
const store=new Store(dir);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const k of Object.keys(s))delete s[k];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{}))if(d.number==='CZ-000222'&&d.status!=='resolved'){
   markResolved(s,d,{resolution:'已支持忧郁坦克筛选，并按牌库→弃牌区→手牌的顺序复制：只有当前区域没有符合牌时才查找下一区域。已修复衍生指令的全局部署监听，后续友方坦克每次部署可永久+1/+1。完整生成、编译及战斗流程已验证。请刷新工坊，在原会话继续理解机制并校验；草稿及已有卡牌保持原样。',version:'0.8.58'});
   done.push(d.number);
  }
  return done;
 });console.log(JSON.stringify({reports}));
}finally{await store.close();}
