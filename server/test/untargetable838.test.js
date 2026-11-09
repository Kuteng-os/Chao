import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileCard,builtinDefinitions,validateKeyword} from '../src/validation.js';
import {latestCards} from '../src/derived_cards.js';
import {makePrompt} from '../src/provider.js';
import {ruleCapabilities} from '../src/rule_capabilities.js';

const registry=Object.fromEntries(builtinDefinitions.map(d=>[`${d.id}@${d.version}`,{...validateKeyword(d,{allowBuiltin:true}),registry_status:'approved'}]));
const fixture=()=>JSON.parse(readFileSync(new URL('../../tests/kill837_card.json',import.meta.url),'utf8'));
test('CZ76 builtin survives compiled derived catalogs and prompt capabilities',()=>{
 const c=fixture();c.tokens[0].keywords=[{id:'core.untargetable',version:1,params:{}}];
 c.abilities[0].premise={test:'compare',left:{unit_stat:{target:'chosen',stat:'health'}},cmp:'gt',right:0};
 const result=compileCard(c,registry);
 const cards=latestCards({cards:{c:[{card_id:'c',revision:1,...result}]},keywords:registry});
 const luser=cards.find(x=>x.definition.name==='luser');
 assert(luser);assert.match(luser.rules_text,/不可指定/);
 assert.equal(compileCard(luser.definition,registry).compiled_program_hash,luser.compiled_program_hash);
 for(const kind of ['card','keyword','mechanism-review']){
  const prompt=makePrompt(kind,Object.values(registry));
  assert(prompt.includes('core.untargetable@1'));assert(prompt.includes('普通攻击照常'));assert(prompt.includes('不能仅按 friendly_unit_count>=1'));
 }
 assert.equal(ruleCapabilities.battle_rules.effect_target_immunity,true);
 assert.equal(ruleCapabilities.battle_rules.minimum_client_build,906);
});
test('CZ76 grant supports duration and rejects invented variants',()=>{
 const c=fixture();c.tokens[0].abilities=[{trigger:'on_play',effects:[{op:'grant_keyword',target:'self',keyword_id:'core.untargetable',keyword_version:1,duration:'battle'}]}];
 // Preserve token reachability with a separate on-play order creation.
 c.tokens[0].abilities.push({trigger:'on_play',effects:[{op:'create_card',token_id:'daoguan',amount:1,player:'owner'}]});
 for(const duration of ['battle','end_of_turn','match']){c.tokens[0].abilities[0].effects[0].duration=duration;assert(compileCard(c,registry));}
 c.tokens[0].abilities[0].effects[0].keyword_version=99;assert.throws(()=>compileCard(c,registry));
 const b=fixture();b.tokens[0].keywords=[{id:'core.untargetable',version:1,params:{x:1}}];assert.throws(()=>compileCard(b,registry));
});
