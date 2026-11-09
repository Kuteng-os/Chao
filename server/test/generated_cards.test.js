import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileCard,validateKeyword,validateCardBlueprint,docsURL} from '../src/validation.js';
import {freshCard,blueprint,readyCard} from '../../web/model.mjs';
const token=(kind='unit')=>({token_id:'child',name:'子卡',kind,cost:2,operation_cost:kind==='unit'?1:0,unit_class:kind==='unit'?'infantry':null,attack:kind==='unit'?2:0,health:kind==='unit'?4:0,keywords:[],abilities:kind==='unit'?[]:[{trigger:kind==='counter'?'on_reveal':'on_play',effects:[{op:'heal',target:'own_hq',amount:2}]}],...(kind==='counter'?{counter_trigger:'enemy_order_played'}:{})});
const make=t=>({...freshCard(),name:'母卡',tokens:[t],abilities:[{trigger:'on_play',effects:[{op:'create_card',token_id:t.token_id,amount:1,player:'owner'}]}]});
test('generated unit, order and counter definitions validate without becoming published cards',()=>{
 for(const kind of ['unit','order','counter']){const c=compileCard(make(token(kind)),{});assert.equal(c.compiled_program.expanded_definition.tokens[0].kind,kind);assert.match(c.rules_text,/加入己方手牌/);}
 const c=make(token('order'));c.abilities[0].effects[0]={op:'summon',token_id:'child',amount:1,row:'support'};assert.throws(()=>compileCard(c,{}),/只能直接召唤/);
 const zero=token();zero.cost=0;assert.equal(compileCard(make(zero),{}).definition.tokens[0].cost,0);
});
test('registered token keywords expand and are frozen in compiler bindings',()=>{
 const kw=JSON.parse(readFileSync(new URL('examples/keywords/standard_heavy_armor.json',docsURL),'utf8')),entry={...validateKeyword(kw),registry_status:'approved'};
 const t=token();t.keywords=[{id:kw.id,version:1,params:{x:3}}];const c=compileCard(make(t),{[kw.id+'@1']:entry});assert.equal(c.compiled_program.expanded_definition.tokens[0].abilities[0].effects[0].amount,3);assert.equal(c.keyword_bindings[0].definition_hash,entry.definition_hash);
 t.kind='order';t.unit_class=null;t.attack=t.health=t.operation_cost=0;assert.throws(()=>compileCard(make(t),{[kw.id+'@1']:entry}));
});
test('template libraries validate reachability, nested operations, target scope and per-body budgets',()=>{
 const c=make(token()),second={...token('order'),token_id:'second'};c.tokens.push(second);assert.doesNotThrow(()=>compileCard(c,{}));
 c.tokens[0].abilities=[{trigger:'on_death',effects:[{op:'create_card',token_id:'second',amount:1,player:'owner'}]}];assert(compileCard(c,{}));
 c.tokens[0].abilities[0].effects[0].token_id='missing';assert.throws(()=>compileCard(c,{}),/不存在/);
 const t=token();t.abilities=[{trigger:'on_summon',target:{side:'ally',row:'any'},effects:[{op:'heal',target:'chosen',amount:2}]}];assert(compileCard(make(t),{}));delete t.abilities[0].target;assert.throws(()=>compileCard(make(t),{}));
 t.abilities=Array.from({length:7},()=>({trigger:'own_turn_end',effects:Array.from({length:4},()=>({op:'draw',player:'owner',amount:1}))}));assert.throws(()=>compileCard(make(t),{}),/24/);
});
test('draft templates survive editing and can be supplied to AI before adding a creation effect',()=>{
 const c=make(token());c.abilities=[];assert.equal(readyCard(c,[]).tokens.length,1);assert.doesNotThrow(()=>validateCardBlueprint(blueprint(c),{}));assert.doesNotThrow(()=>compileCard(c,{}));
});
