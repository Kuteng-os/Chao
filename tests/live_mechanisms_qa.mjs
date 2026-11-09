// Opt-in, bounded paid provider smoke. Does not write to the production store.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DeepSeekProvider} from '../server/src/provider.js';
import {compileCard} from '../server/src/validation.js';
const provider=new DeepSeekProvider({apiKey:process.env.DEEPSEEK_API_KEY,model:process.env.DEEPSEEK_MODEL,baseURL:process.env.DEEPSEEK_BASE_URL});
const state=JSON.parse(readFileSync(process.env.CARD_DATA_DIR+'/store.json','utf8'));
const catalog=Object.values(state.keywords).map(x=>({definition:x.definition,definition_hash:x.definition_hash}));
const base={name:'回归测试',kind:'unit',unit_class:'infantry',cost:1,operation_cost:1,attack:3,health:4,keywords:[],abilities:[],tokens:[],play_target:null,effect_mode:'append'};
async function call(kind,source,blueprint){let attempts=0;return provider.generate({kind,catalog,context:{target_kind:'card',source_text:source,card_blueprint:blueprint,review_history:[],confirmed_history:[],component_catalog:[]},signal:AbortSignal.timeout(250000),onAttempt:async()=>{assert(++attempts<=2);}});}
const ambiguous=await call('mechanism-review','这张卡造成伤害无视重甲，只会造成攻击力一般的伤害',base);
assert(ambiguous.result.questions.length>0,'ambiguous half damage must ask');assert.equal(ambiguous.result.missing_capabilities.length,0);console.log('LIVE_HALF_REVIEW_ASKS',JSON.stringify(ambiguous.result.questions));
const half=await call('card','该单位本次在场期间，主动攻击与反击均造成当前攻击力的一半战斗伤害，向上取整，并无视目标重甲减免。对任意目标生效。',base);
assert.equal(half.result.status,'ok');const compiled=compileCard(half.result.card,state.keywords);const rule=compiled.compiled_program.expanded_definition.abilities.flatMap(a=>a.effects).find(e=>e.op==='set_combat_damage_multiplier');
assert(rule&&rule.multiplier===1&&rule.divisor===2&&rule.rounding==='ceil'&&rule.ignore_armor===true&&rule.applies_to==='both');console.log('LIVE_HALF_COMPILES',compiled.rules_text);
const order={...base,kind:'order',unit_class:null,operation_cost:0,attack:0,health:0};
const source='打出本指令时，若敌方前线与支援阵线存活单位总数严格大于己方存活单位数，则己方抽2张牌；不含总部，否则不抽。';
const review=await call('mechanism-review',source,order);assert.equal(review.result.missing_capabilities.length,0);assert.equal(review.result.questions.length,0);console.log('LIVE_CONDITION_REVIEW_OK');
const generated=await call('card',source,order);assert.equal(generated.result.status,'ok');const c=compileCard(generated.result.card,state.keywords);const a=c.definition.abilities.find(a=>a.premise);assert(a&&a.effects.some(e=>e.op==='draw'&&e.amount===2));console.log('LIVE_CONDITION_COMPILES',c.rules_text);
