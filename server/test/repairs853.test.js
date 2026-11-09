import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard,validateKeyword} from '../src/validation.js';
import {freshCard,changeKind,readyCard} from '../../web/model.mjs';
const definition={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.configure853',version:1,name:'逐卡配置',description:'各卡独立填写。',aliases:[],parameters:{},implementation:{kind:'configurable'}};
const registry={'custom.configure853@1':{...validateKeyword(definition),registry_status:'approved'}},catalog=Object.values(registry);
function order(){return {...freshCard(),name:'类型转换',kind:'order',unit_class:null,health:0,attack:0,operation_cost:0,appearance:{emblem:'order'},play_target:{side:'ally',row:'front',unit_classes:['tank']},keywords:[{id:definition.id,version:1,params:{},abilities:[{trigger:'on_play',effects:[{op:'heal',target:'chosen',amount:2}]}]}]};}
test('card-kind changes preserve configured effects and selected target restrictions',()=>{
 const original=order(),c=readyCard(changeKind(original,'counter'),catalog);
 assert.equal(original.keywords[0].abilities[0].trigger,'on_play');
 const a=c.keywords[0].abilities[0];assert.equal(a.trigger,'on_reveal');assert.equal(a.target.side,'ally');assert.deepEqual(a.target.unit_classes,['tank']);assert.equal(a.target.timing,'trigger');assert.equal(c.play_target,null);
 assert.doesNotThrow(()=>compileCard(c,registry));
 const back=readyCard(changeKind(c,'order'),catalog);assert.equal(back.keywords[0].abilities[0].trigger,'on_play');assert.doesNotThrow(()=>compileCard(back,registry));
});
test('plain order effects get the same valid target conversion',()=>{
 const c=order();c.abilities=c.keywords[0].abilities;c.keywords=[];
 assert.doesNotThrow(()=>compileCard(readyCard(changeKind(c,'counter'),catalog),registry));
});
test('headquarters configured targets are chosen at trigger time',()=>{
 const c=changeKind(order(),'hq');c.keywords[0].abilities[0].trigger='own_turn_start';c.keywords[0].abilities[0].target={side:'ally',row:'any',timing:'deploy'};
 const fixed=readyCard(c,catalog);assert.equal(fixed.keywords[0].abilities[0].target.timing,'trigger');assert.doesNotThrow(()=>compileCard(fixed,registry));
});
