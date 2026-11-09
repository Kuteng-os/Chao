// Read-only production provider verification; never stores test cards or answers.
import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,applyCardBlueprint} from '../server/src/validation.js';
import {freshCard,changeKind,blueprint} from '../web/model.mjs';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const catalog=Object.values(state.keywords).filter(k=>k.registry_status==='approved');
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const results=[];
const cases=[
 ['83','order','抽一张单位和一张指令：从己方牌库顶向下依次各抽一张符合类型的牌，其他牌原序保留，不足取实际数量。若实际抽到的己方牌中任意一张卡面打出费用为偶数（含0），己方总部防御+5，共一次。'],
 ['85','order','使用时从牌库顶向下抽2张指令牌，不足取实际数量；若打出本牌之前己方上一张打出的牌是指令，获得2点指挥点。上一张跨回合保留，不含当前牌，首张不满足。'],
 ['88','order','使用时抽两张牌，下下个己方回合开始额外抽一张牌，仅一次。'],
 ['80','unit','在场期间，本单位每次受到普通战斗伤害（主动攻击或反击）时，自身当前攻击每高出伤害来源单位2点，所受伤害-1；正差向下取整，不足2不减，最低伤害0，每次重新比较。不影响效果伤害。'],
 ['73','order','3费指令，使用时没有额外效果，不选目标，正常花费、进入弃牌并触发打出指令。']
];
for(const [label,kind,source_text] of cases){
 const bp=blueprint({...changeKind(freshCard(),kind),name:'验证'+label,cost:3});let attempts=0;
 try{
  const out=await provider.generate({kind:'card',catalog,context:{source_text,card_blueprint:bp,confirmed_history:[],faction_catalog:Object.values(state.factions).map(f=>({id:f.faction_id,name:f.name})),component_catalog:[],card_reference_catalog:Object.values(state.cards).map(v=>({card_id:v.at(-1).card_id,name:v.at(-1).definition.name}))},signal:AbortSignal.timeout(250000),onAttempt:async()=>attempts++});
  const compiled=out.result.status==='ok'?compileCard(applyCardBlueprint(out.result.card,bp),state.keywords):null;
  results.push({label,attempts,pass:!!compiled,result:out.result,compiled,metadata:out.metadata});console.log(label,compiled?'PASS':'NEEDS_REVIEW',attempts);
 }catch(e){results.push({label,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(label,'FAIL',e.code??e.name);}
 writeFileSync('/var/log/frontline/provider841-completed.json',JSON.stringify(results,null,2));
}
console.log('DONE',results.filter(r=>r.pass).length,results.length);
