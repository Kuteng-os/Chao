import {readFileSync,writeFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard,validateKeyword} from '../server/src/validation.js';
import {blueprint} from '../web/model.mjs';
const state=JSON.parse(readFileSync('/var/lib/frontline/data/store.json','utf8'));
const fixture=JSON.parse(readFileSync(new URL('../tests/fixtures/repairs852.json',import.meta.url),'utf8'));
const entry={...validateKeyword(fixture.keyword),registry_status:'approved'};
const registry={...state.keywords,'custom.release@1':entry};
const catalog=Object.values(registry).filter(k=>k.registry_status==='approved');
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const text='登记通用词条解放。每张卡独立填写解放前提、攻防强化与即时效果；满足前提时每次在场仅触发一次，回手恢复原型。这次只登记通用词条，具体数值由各卡填写。';
const bp=blueprint(fixture.card);bp.keywords[0].abilities=[];
const cases=[
 ['review','mechanism-review',{source_text:text,target_kind:'keyword',suggested_name:'解放'},r=>r.missing_capabilities.length===0&&r.questions.length===0],
 ['keyword','keyword',{source_text:text,suggested_name:'解放',assigned_id:'custom.release',assigned_version:1},r=>{const d=r.keyword??r.definition;return !!d&&validateKeyword(d).definition.implementation.kind==='configurable';}],
 ['card','card',{source_text:'本卡的解放：在场敌方单位数首次大于0时，自身+2/+1，持续在场期间，并抽1张牌。每次在场只触发一次，回手重置。填写已选解放词条的空配置，基础数值不变。',card_blueprint:bp},r=>{if(r.status!=='ok')return false;const c=compileCard(r.card,registry);return r.card.keywords[0].abilities?.[0]?.trigger==='when_condition'&&c.compiled_program.expanded_definition.abilities.some(a=>a.effects.some(e=>e.op==='modify_stats'));}]
];
const results=[];
for(const [key,kind,input,verify] of cases){let attempts=0;try{const out=await provider.generate({kind,catalog,context:{confirmed_history:[],history:[],faction_catalog:[],component_catalog:[],card_reference_catalog:[],...input},signal:AbortSignal.timeout(240000),onAttempt:async()=>attempts++});let pass=false;try{pass=!!verify(out.result);}catch{}results.push({key,kind,attempts,pass,result:out.result});console.log(key,pass?'PASS':'NEEDS_REVIEW',attempts);}catch(e){results.push({key,kind,attempts,pass:false,error:{code:e.code,message:e.message}});console.log(key,'FAIL',e.code??e.name);}writeFileSync('/var/log/frontline/provider852-completed.json',JSON.stringify(results,null,2));}
console.log('DONE',results.filter(r=>r.pass).length,results.length);
