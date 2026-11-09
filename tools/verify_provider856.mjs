// Read-only provider probes. No player content is registered or modified.
import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {blueprint} from '../web/model.mjs';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const fixtures=JSON.parse(readFileSync(new URL('../tests/fixtures/repairs856.json',import.meta.url),'utf8'));
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved');
const cases=[
 ['tank','使用时，选择一个敌方单位，其攻击力变为0，受到来自坦克的伤害翻倍，直到下个己方回合开始。'],
 ['all','使用时，选择一个敌方单位，其攻击力变为0，受到的所有伤害翻倍，直到下个己方回合开始。'],
 ['combat','使用时，选择一个敌方单位，其攻击力变为0，受到战斗伤害+1，直到下个己方回合开始。'],
 ['end','使用时，选择一个敌方单位，其攻击力变为0，受到战斗伤害+1，直到下个敌方回合结束。']
];
let next=0;const results=[];
async function run(){while(next<cases.length){const [key,source_text]=cases[next++];if(process.env.PROBE_CASE&&key!==process.env.PROBE_CASE)continue;const bp=blueprint(fixtures[key]);bp.abilities=[];
 for(const kind of ['mechanism-review','card']){let attempts=0;try{
  const out=await provider.generate({kind,catalog,context:{target_kind:'card',source_text,card_blueprint:bp,history:[],confirmed_history:[],faction_catalog:[],component_catalog:[],card_reference_catalog:[]},signal:AbortSignal.timeout(240000),onAttempt:async()=>attempts++});
  const card=kind==='card'&&out.result.status==='ok'?applyCardBlueprint(out.result.card,bp):null;
  const compiled=card?compileCard(card,state.keywords):null;
  const effects=compiled?.compiled_program.expanded_definition.abilities.flatMap(a=>a.effects)??[],expected=fixtures[key].abilities[0].effects;
  const pass=kind==='card'?!!compiled&&expected.every(e=>effects.some(actual=>Object.entries(e).every(([k,v])=>JSON.stringify(actual[k])===JSON.stringify(v)))):out.result.missing_capabilities.length===0&&out.result.questions.length===0;
  results.push({key,kind,attempts,pass,result:out.result});console.log(key,kind,pass?'PASS':'NEEDS_REVIEW',attempts);
 }catch(e){results.push({key,kind,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(key,kind,'FAIL',e.code??e.name);}
 writeFileSync('/var/log/frontline/provider856'+(process.env.PROBE_CASE?'-'+process.env.PROBE_CASE:'')+'-completed.json',JSON.stringify(results,null,2));
 }
}}
await Promise.all([run(),run()]);console.log('DONE',results.filter(r=>r.pass).length,results.length);
