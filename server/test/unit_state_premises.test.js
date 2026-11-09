import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard} from '../src/validation.js';
import {validatePremise,premiseText} from '../src/premises.js';
import {freshCard,changeKind} from '../../web/model.mjs';
import {premiseSummary} from '../../web/mechanism.mjs';
import {makePrompt} from '../src/provider.js';
const query=(state='printed')=>({test:'unit_keyword',target:'chosen',keyword_id:'core.shock',state});
const order=()=>({...changeKind(freshCard(),'order'),name:'状态分支',play_target:{side:'ally',row:'any'},abilities:[{trigger:'on_play',premise:query(),effects:[{op:'draw',player:'owner',amount:1}]}]});
test('unit state leaves are bounded and compose without weakening validation',()=>{
 for(const state of ['printed','current','consumed'])assert.doesNotThrow(()=>compileCard({...order(),abilities:[{...order().abilities[0],premise:query(state)}]},{}));
 for(const p of [{...query(),extra:true},{...query(),target:'enemy_hq'},{...query(),keyword_id:'invalid id'},{...query(),state:'ever'},{test:'unit_state',target:'chosen',state:'arbitrary_script'}])assert.throws(()=>validatePremise(p));
 for(const target of ['self','trigger_unit']){const c=order();c.abilities[0].premise.target=target;assert.throws(()=>compileCard(c,{}));}
 for(const trigger of ['while_active','next_own_turn_start']){const c=order();c.abilities[0].trigger=trigger;assert.throws(()=>compileCard(c,{}));}
 const c=order();c.play_target.include_hq=true;assert.throws(()=>compileCard(c,{}));
 c.play_target=null;assert.throws(()=>compileCard(c,{}));
 const p={test:'all',items:[query(),{test:'not',item:{test:'unit_state',target:'chosen',state:'has_attacked'}}]};assert.doesNotThrow(()=>validatePremise(p));
 assert.match(premiseText(p),/卡面原生具有冲击/);assert.match(premiseSummary(p),/本次在场期间已主动攻击/);
});
test('all generation stages know printed/current/consumed and one-time branch evaluation',()=>{
 for(const kind of ['card','keyword','mechanism-review']){const p=makePrompt(kind,[]);for(const text of ['mechanics-20','unit_keyword','has_attacked','printed','consumed','共用 play_target'])assert(p.includes(text),kind+text);}
});
