import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {referenceTemplates} from '../server/src/card_references.js';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved'),results=[];
const queue=['CZ-000269','CZ-000273','CZ-000276','CZ-000279'];
async function worker(){while(queue.length){const number=queue.shift();
 const report=Object.values(state.diagnostics).find(d=>d.number===number);
 const job=state.generations[report.generation_id];if(!job)throw Error('No job '+number);
 const context={source_text:job.source_text,card_blueprint:job.card_blueprint,target_kind:'card',history:job.history??[],review_history:job.history??[],confirmed_history:job.history??[],component_catalog:[],faction_catalog:[],card_template_catalog:referenceTemplates(state,job.source_text,job.history)};
 if(number==='CZ-000279')context.card_blueprint={...context.card_blueprint,effect_mode:'replace'};
 for(const kind of ['mechanism-review','card']){
  try{
   const out=await provider.generate({kind,catalog,context,onAttempt:async()=>{},signal:AbortSignal.timeout(240000)});let pass=out.result.missing_capabilities?.length===0;
   if(kind==='card'){pass=out.result.status==='ok';if(pass){const card=applyCardBlueprint(out.result.card,context.card_blueprint);compileCard(card,state.keywords);out.result.card=card;}}
   results.push({number,kind,pass,result:out.result});console.log(number,kind,pass?'PASS':'NEEDS_REVIEW');
  }catch(e){results.push({number,kind,pass:false,code:e.code,message:e.message});console.log(number,kind,'FAIL',e.code??e.name);}
  writeFileSync('/var/log/frontline/provider863-completed.json',JSON.stringify(results,null,2));
 }
}
}
await Promise.all([worker(),worker()]);
