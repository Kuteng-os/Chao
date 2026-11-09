// Read-only live-provider probe. Does not create cards, jobs, reports or messages.
import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {blueprint} from '../web/model.mjs';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const fixtures=JSON.parse(readFileSync(new URL('../tests/fixtures/repairs850.json',import.meta.url),'utf8'));
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved');
const cases=[
 ['veteran','veteran','进入前线后升为老兵，老兵形态使用已经定义的 veteran 衍生单位。升级不触发登场，也不刷新本回合的攻击或移动次数。',c=>c.abilities.some(a=>a.trigger==='after_move'&&a.effects.some(e=>e.op==='become_veteran'))],
 ['choice','choice','使用时，选择一个敌方单位并压制其1回合；然后抉择：己方总部当前防御与上限+3，或对刚才选择的该单位造成1点伤害。',c=>c.play_target&&c.abilities.some(a=>a.effects.some(e=>e.op==='choose_effect'&&e.options.some(o=>o.effects.some(x=>x.target==='chosen'))))],
 ['attack_gain','attack_gain','主动攻击时，在伤害结算前，获得本次被攻击单位当前攻击和当前防御数值的攻防加成。持续在场期间，可叠加。攻击总部时不获得。',c=>c.abilities.some(a=>a.trigger==='on_attack')&&JSON.stringify(c.abilities).includes('attack_target')],
 ['control','control','使用时控制一个所选敌方单位，持续到本回合结束，然后将它归还原控制者。',c=>c.abilities.some(a=>a.effects.some(e=>e.op==='take_control'&&e.duration==='end_of_turn'))]
];
const results=[];let next=0;
async function run(){while(next<cases.length){const [label,key,source_text,verify]=cases[next++];const card_blueprint=blueprint(fixtures[key]);card_blueprint.abilities=[];
 for(const kind of ['mechanism-review','card']){let attempts=0;try{
  const out=await provider.generate({kind,catalog,context:{source_text,card_blueprint,confirmed_history:[],history:[],faction_catalog:[],component_catalog:[],card_reference_catalog:[]},signal:AbortSignal.timeout(240000),onAttempt:async()=>attempts++});
  const card=kind==='card'&&out.result.status==='ok'?applyCardBlueprint(out.result.card,card_blueprint):null;
  const compiled=card?compileCard(card,state.keywords):null;
  const pass=kind==='card'?!!compiled&&!!verify(card):out.result.missing_capabilities.length===0;
  results.push({label,kind,attempts,pass,result:out.result,card});console.log(label,kind,pass?'PASS':'NEEDS_REVIEW',attempts);
 }catch(e){results.push({label,kind,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(label,kind,'FAIL',e.code??e.name);}
 writeFileSync('/var/log/frontline/provider850-completed.json',JSON.stringify(results,null,2));
 }
}}
await Promise.all([run(),run()]);console.log('DONE',results.filter(r=>r.pass).length,results.length);
