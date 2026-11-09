// Read-only generation probes. Never register or modify player content.
import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {blueprint} from '../web/model.mjs';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const fixtures=JSON.parse(readFileSync(new URL('../tests/fixtures/repairs855.json',import.meta.url),'utf8'));
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved');
const cases=[
 ['bounce','使用时，选择一个场上的友方单位返回手牌；本回合结束前，该牌下一次部署费用-2。费用变化固定绑定刚返回的那张牌，不需要再选其他手牌。',c=>c.abilities.some(a=>a.effects.some(e=>e.op==='return_to_hand'&&e.target==='chosen'&&e.cost_delta===-2&&e.duration==='end_of_turn'))],
 ['history','部署时，若己方上一个回合部署过忧郁罪孽的单位，选择一个敌方单位撤退。历史按部署时的罪孽判断，后来离场也算；召唤不计，无合法敌方目标时跳过该效果。',c=>JSON.stringify(c.abilities).includes('deployed_last_turn')&&JSON.stringify(c.abilities).includes('gloom')&&JSON.stringify(c.abilities).includes('retreat')]
];
let next=0;const results=[];
async function run(){while(next<cases.length){const [key,source_text,verify]=cases[next++];const bp=blueprint(fixtures[key]);bp.abilities=[];delete bp.cost_surcharge;
 for(const kind of ['mechanism-review','card']){let attempts=0;try{
  const out=await provider.generate({kind,catalog,context:{target_kind:'card',source_text,card_blueprint:bp,history:[],confirmed_history:[],faction_catalog:[],component_catalog:[],card_reference_catalog:[]},signal:AbortSignal.timeout(240000),onAttempt:async()=>attempts++});
  const card=kind==='card'&&out.result.status==='ok'?applyCardBlueprint(out.result.card,bp):null;
  const compiled=card?compileCard(card,state.keywords):null;
  const pass=kind==='card'?!!compiled&&!!verify(compiled.compiled_program.expanded_definition):out.result.missing_capabilities.length===0;
  results.push({key,kind,attempts,pass,result:out.result});console.log(key,kind,pass?'PASS':'NEEDS_REVIEW',attempts);
 }catch(e){results.push({key,kind,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(key,kind,'FAIL',e.code??e.name);}
 writeFileSync('/var/log/frontline/provider855-completed.json',JSON.stringify(results,null,2));
 }
}}
await Promise.all([run(),run()]);console.log('DONE',results.filter(r=>r.pass).length,results.length);
