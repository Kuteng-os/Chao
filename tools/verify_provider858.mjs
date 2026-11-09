import{readFileSync,writeFileSync}from'node:fs';
import{DeepSeekProvider}from'../server/src/provider.js';
import{compileCard,applyCardBlueprint,walkEffects}from'../server/src/validation.js';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const {job}=JSON.parse(readFileSync('/var/log/frontline/report222-source.json','utf8'));
const bp=job.card_blueprint,provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved'),results=[];
let confirmed;
for(const kind of ['mechanism-review','card']){
 let attempts=0;
 try{
  const out=await provider.generate({kind,catalog,context:{target_kind:'card',source_text:job.source_text,card_blueprint:bp,history:job.history,confirmed_history:job.history,...(confirmed?{formal_text:confirmed,confirmed_mechanism:confirmed}:{}),faction_catalog:[],component_catalog:[],card_reference_catalog:[]},signal:AbortSignal.timeout(240000),onAttempt:async()=>attempts++});
  let pass=out.result.missing_capabilities?.length===0&&out.result.questions?.length===0;
  if(kind==='mechanism-review')confirmed=out.result.formal_text;
  if(kind==='card'&&out.result.status==='ok'){
   const card=applyCardBlueprint(out.result.card,bp),c=compileCard(card,state.keywords),expanded=c.compiled_program.expanded_definition;
   const created=expanded.abilities.flatMap(a=>walkEffects(a.effects)).find(e=>e.op==='create_card');
   const token=expanded.tokens.find(t=>t.token_id===created?.token_id),effects=token?.abilities.flatMap(a=>walkEffects(a.effects))??[];
   const transfer=effects.find(e=>e.op==='transfer_card'&&e.mode==='copy'),schedule=effects.find(e=>e.op==='schedule');
   pass=token?.cost===3&&transfer?.source==='deck'&&JSON.stringify(transfer.fallback_sources)==='["discard","hand"]'&&transfer.filter?.sin==='gloom'&&transfer.filter?.unit_class==='tank'&&schedule?.trigger==='next_own_unit_deployed'&&schedule.repeat==='each_event'&&schedule.lifetime==='match'&&schedule.times===undefined&&schedule.effects.some(e=>e.op==='modify_stats'&&e.target==='trigger_unit'&&e.duration==='match'&&e.attack_delta===1&&e.health_delta===1&&JSON.stringify(e.unit_filter?.unit_classes)==='["tank"]');
   if(pass)writeFileSync('/var/log/frontline/provider858-parity.json',JSON.stringify([{name:'222-youth-derived',definition:card,keywords:Object.values(state.keywords).map(k=>k.definition),expected:{...c,ok:true}}]));
  }
  results.push({kind,attempts,pass:!!pass,result:out.result});console.log(kind,pass?'PASS':'NEEDS_REVIEW',attempts);
 }catch(e){results.push({kind,pass:false,error:e.message});console.log(kind,'FAIL',e.code??e.name);}
 writeFileSync('/var/log/frontline/provider858-completed.json',JSON.stringify(results,null,2));
}
