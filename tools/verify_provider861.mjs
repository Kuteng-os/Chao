import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {referenceTemplates} from '../server/src/card_references.js';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved'),results=[];
for(const number of ['CZ-000226','CZ-000228','CZ-000260','CZ-000261']){
 const report=Object.values(state.diagnostics).find(d=>d.number===number);
 const job=Object.values(state.generations).filter(j=>j.conversation_id===report.conversation_id).sort((a,b)=>b.round-a.round)[0];
 const context={source_text:job.source_text,card_blueprint:job.card_blueprint,target_kind:'card',history:job.history??[],review_history:job.history??[],confirmed_history:job.history??[],component_catalog:[],faction_catalog:[],card_template_catalog:referenceTemplates(state,job.source_text,job.history)};
 for(const kind of number==='CZ-000228'?['mechanism-review','card']:['mechanism-review']){
  try{
   const out=await provider.generate({kind,catalog,context,onAttempt:async()=>{},signal:AbortSignal.timeout(240000)});let pass=out.result.missing_capabilities?.length===0;
   if(kind==='card'){pass=out.result.status==='ok';if(pass)compileCard(applyCardBlueprint(out.result.card,job.card_blueprint),state.keywords);}
   results.push({number,kind,pass,result:out.result});console.log(number,kind,pass?'PASS':'NEEDS_REVIEW');
  }catch(e){results.push({number,kind,pass:false,code:e.code,message:e.message});console.log(number,kind,'FAIL',e.code??e.name);}
  writeFileSync('/var/log/frontline/provider861-completed.json',JSON.stringify(results,null,2));
 }
}
