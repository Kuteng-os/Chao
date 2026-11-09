// No player data mutations. Provider credentials come from the service environment.
import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {blueprint} from '../web/model.mjs';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const fixtures=JSON.parse(readFileSync(new URL('../tests/fixtures/repairs851.json',import.meta.url),'utf8'));
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved');
const cases=[
 ['choice','使用时抉择：选择一个敌方单位压制1回合；或选择一个友方步兵获得+2/+3，持续在场期间。先选分支，再选那个分支的目标，没有合法目标则该部分跳过。',c=>c.abilities.some(a=>a.effects.some(e=>e.op==='choose_effect'&&e.options.every(o=>o.target)))],
 ['return_drawn','使用时抽1张牌；若刚抽到的这张牌费用为奇数，就将这一张牌洗回己方牌库随机位置，否则留在手牌。只处理这次刚抽到的实例，满手烧毁则不洗回。',c=>JSON.stringify(c.abilities).includes('"source":"drawn"')],
 ['max_only','使用时选择一个友方单位，其防御上限+2，持续在场期间。当前防御不增加，不治疗。',c=>JSON.stringify(c.abilities).includes('"health_mode":"max_only"')]
];
const results=[];let next=0;
async function run(){while(next<cases.length){const [key,source_text,verify]=cases[next++];const card_blueprint=blueprint(fixtures[key]);card_blueprint.abilities=[];
 for(const kind of ['mechanism-review','card']){let attempts=0;try{
  const out=await provider.generate({kind,catalog,context:{source_text,card_blueprint,confirmed_history:[],history:[],faction_catalog:[],component_catalog:[],card_reference_catalog:[]},signal:AbortSignal.timeout(240000),onAttempt:async()=>attempts++});
  const card=kind==='card'&&out.result.status==='ok'?applyCardBlueprint(out.result.card,card_blueprint):null;
  const compiled=card?compileCard(card,state.keywords):null;
  const pass=kind==='card'?!!compiled&&!!verify(card):out.result.missing_capabilities.length===0;
  results.push({key,kind,attempts,pass,result:out.result});console.log(key,kind,pass?'PASS':'NEEDS_REVIEW',attempts);
 }catch(e){results.push({key,kind,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(key,kind,'FAIL',e.code??e.name);}
 writeFileSync('/var/log/frontline/provider851-completed.json',JSON.stringify(results,null,2));
 }
}}
await Promise.all([run(),run()]);console.log('DONE',results.filter(r=>r.pass).length,results.length);
