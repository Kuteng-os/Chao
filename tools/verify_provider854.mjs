// Read-only generation probes. Never register or modify player content.
import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {blueprint} from '../web/model.mjs';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const fixtures=JSON.parse(readFileSync(new URL('../tests/fixtures/repairs854.json',import.meta.url),'utf8'));
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved');
const cases=[
 ['counter','敌方单位攻击一个友方单位时，交战前消灭攻击者和被攻击者，正常触发阵亡。按所选反制触发条件执行。',c=>c.counter_trigger==='enemy_unit_attacked'&&JSON.stringify(c.abilities).includes('attack_target')],
 ['cost','使用时抽1张牌。己方第5回合起此牌费用额外增加1，第8回合起额外增加2，只取最高档；出牌前计算，费用不足不能打出。',c=>c.cost_surcharge?.length===2],
 ['liberate','本单位自身撤退后解放为已有衍生形态released。本次在场只解放一次，原地变为衍生形态的4/4、行动费0、闪击，替换原有能力。保留行动、压制和已受损伤。离场恢复原型。',c=>JSON.stringify(c.abilities).includes('liberate')&&JSON.stringify(c.abilities).includes('event_scope')],
 ['field','本场地生效时，双方手牌、弃牌区和所有在场单位洗回各自牌库，不含总部和本场地。然后双方各自从自己牌库选择一张单位免费部署，触发部署效果。在本场地生效期间，双方各自在场最多1个单位，已有1个时不能再部署或召唤。双方所有单位持续+5/+5并获得守护、闪击、奋战、免疫，后来入场也有效，场地被替换后撤销。',c=>['reshuffle_zones','unit_limit','grant_keyword'].every(op=>JSON.stringify(c.abilities).includes(op))]
];
let next=0;const results=[];
async function run(){while(next<cases.length){const [key,source_text,verify]=cases[next++];const bp=blueprint(fixtures[key]);bp.abilities=[];delete bp.cost_surcharge;
 for(const kind of key==='field'?['mechanism-review','card']:['card']){let attempts=0;try{
  const out=await provider.generate({kind,catalog,context:{target_kind:'card',source_text,card_blueprint:bp,history:[],confirmed_history:[],faction_catalog:[],component_catalog:[],card_reference_catalog:[]},signal:AbortSignal.timeout(240000),onAttempt:async()=>attempts++});
  const card=kind==='card'&&out.result.status==='ok'?applyCardBlueprint(out.result.card,bp):null;
  const compiled=card?compileCard(card,state.keywords):null;
  const pass=kind==='card'?!!compiled&&!!verify(compiled.compiled_program.expanded_definition):out.result.missing_capabilities.length===0;
  results.push({key,kind,attempts,pass,result:out.result});console.log(key,kind,pass?'PASS':'NEEDS_REVIEW',attempts);
 }catch(e){results.push({key,kind,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(key,kind,'FAIL',e.code??e.name);}
 writeFileSync('/var/log/frontline/provider854-completed.json',JSON.stringify(results,null,2));
 }
}}
await Promise.all([run(),run()]);console.log('DONE',results.filter(r=>r.pass).length,results.length);
