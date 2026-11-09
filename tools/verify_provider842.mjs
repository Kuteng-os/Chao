// Read-only generation checks: no test cards, messages or generation jobs are persisted.
import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {freshCard,changeKind,blueprint} from '../web/model.mjs';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved');
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const results=[],cases=[
 ['89','order','使用时选择一个敌方单位造成2点伤害，然后抽1张牌。如果这次2点伤害直接消灭该单位，再抽1张。不包含总部，无合法目标时跳过伤害但正常抽1张；击杀奖励仅一次。'],
 ['92','order','使用时选择一个己方剑阵营单位，给它装备一件名为剑的装备，装备件数+1；不改变攻防。只按阵营判断而非罪孽。不选总部。没有合法目标则没有效果。'],
 ['97','order','使用时抉择，仅选一项：一、抽2张牌；二、己方总部立即加7防御，下一个己方回合开始再加2防御，仅一次。后续+2只在选择第二项时触发，不是独立常驻能力。'],
 ['98','unit','阵亡后将刚阵亡的本张原卡从弃牌区返回己方手牌，不复制。清除本次在场临时增益、损伤和压制等在场状态，仅保留仍有效的永久强化；手牌满则烧毁。相同名字的其他弃牌不受影响。']
];
for(const [label,kind,source_text] of cases){
 const bp=blueprint({...changeKind(freshCard(),kind),name:'验证'+label,cost:3});let attempts=0;
 try{
  const out=await provider.generate({kind:'card',catalog,context:{source_text,card_blueprint:bp,confirmed_history:[],faction_catalog:Object.values(state.factions).map(f=>({id:f.faction_id,name:f.name})),component_catalog:[],card_reference_catalog:[]},signal:AbortSignal.timeout(250000),onAttempt:async()=>attempts++});
  const compiled=out.result.status==='ok'?compileCard(applyCardBlueprint(out.result.card,bp),state.keywords):null;
  results.push({label,attempts,pass:!!compiled,result:out.result,compiled,metadata:out.metadata});console.log(label,compiled?'PASS':'NEEDS_REVIEW',attempts);
 }catch(e){results.push({label,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(label,'FAIL',e.code??e.name);}
 writeFileSync('/var/log/frontline/provider842-completed.json',JSON.stringify(results,null,2));
}
console.log('DONE',results.filter(r=>r.pass).length,results.length);
