// Read-only provider verification: never creates cards, jobs or messages in the store.
import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved');
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const details={
 99:'阵亡：将刚阵亡的这张原卡返回己方手牌，手牌满则改为放在己方牌库顶。不复制，不取同名其他牌；保留仍有效的永久强化，临时在场状态清除。',
 100:'阵亡：将自身原卡返回手牌；若手牌满则烧毁，不复制。',
 101:'在现有对全体敌军造成2点伤害的基础上，若目标当前有守护则额外+2伤害。追加在同一个伤害包，一次造成4点，其他目标2点。不要另造成一次2点。',
 102:'在现有对全体敌军造成2点伤害的基础上，若目标是步兵（含附加步兵身份）则额外+2伤害。追加在同一个伤害包，一次造成4点，其他目标2点。',
 105:'使用时，对双方所有场上单位造成1点伤害，不含总部。每有一个单位被本次伤害直接击杀，己方总部当前防御与上限+1，能超过20。其他连锁阵亡不计。',
 107:'使用时，对双方所有场上单位造成1点伤害，不含总部。每有一个单位被本次伤害直接击杀（含己方），就在己方支援线召唤一个1费1行动费1攻击1防御的步兵衍生单位，无额外能力。支援线满则不召唤。',
 112:'阵亡：选择己方手牌中一张元素阵营卡，部署费用-1，最低0，可叠加。包括单位、指令、反制和场地。只在该卡留在手牌期间生效，离开手牌即失效。伏置反制仍视为隐藏手牌。',
 113:'阵亡：由控制者查看己方牌库中全部符合条件的玉石阵营单位，自己选择一张，将该原卡从牌库移出并召唤到己方支援线，不支付其费用。不随机，不复制。没有候选或支援线满则无效果。'
};
const cases=Object.keys(details).map(Number),results=[];
let next=0;
async function run(){while(next<cases.length){const n=cases[next++];const report=Object.values(state.diagnostics).find(r=>r.number==='CZ-'+String(n).padStart(6,'0'));const job=state.generations[report.generation_id];
 const context={source_text:details[n],card_blueprint:job.card_blueprint,confirmed_history:[],history:job.history??[],faction_catalog:Object.values(state.factions).map(f=>({id:f.faction_id,name:f.name})),component_catalog:[],card_reference_catalog:[]};
 for(const kind of ['card','mechanism-review']){let attempts=0;
  try{const out=await provider.generate({kind,catalog,context,signal:AbortSignal.timeout(250000),onAttempt:async()=>attempts++});
   const compiled=kind==='card'&&out.result.status==='ok'?compileCard(applyCardBlueprint(out.result.card,job.card_blueprint),state.keywords):null;
   const pass=kind==='card'?!!compiled:!out.result.missing_capabilities.length;
   results.push({label:n,kind,attempts,pass,result:out.result,compiled});console.log(n,kind,pass?'PASS':'NEEDS_REVIEW',attempts);
  }catch(e){results.push({label:n,kind,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(n,kind,'FAIL',e.code??e.name);}
  writeFileSync('/var/log/frontline/provider843-completed.json',JSON.stringify(results,null,2));
 }
}}
await Promise.all([run(),run()]);console.log('DONE',results.filter(r=>r.pass).length,results.length);
