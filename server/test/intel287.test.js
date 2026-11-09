import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,schemas} from '../src/validation.js';
import {freshCard,blueprint} from '../../web/model.mjs';
import {makePrompt,promptSchema} from '../src/provider.js';
import Ajv from 'ajv';

const intel={op:'intel',amount:1,selection:'chosen'};
const card={...freshCard(),name:'窥探',kind:'order',unit_class:null,cost:0,operation_cost:0,attack:0,health:0,appearance:{emblem:'order'},abilities:[{trigger:'on_play',effects:[intel,{op:'draw',player:'owner',amount:1}]}]};
const keyword={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.peek',version:1,name:'窥探',aliases:[],description:'选择敌方手牌查看。',parameters:{n:{type:'integer',minimum:1,maximum:9}},implementation:{kind:'template',abilities:[{trigger:'on_play',effects:[{...intel,amount:{param:'n'}}]}]}};

test('CZ-287 chosen intel supports cards, nested effects, tokens and parameterized keywords',()=>{
 const compiled=compileCard(card,{});
 assert.match(compiled.rules_text,/选择并查看敌方1张手牌/);
 assert.equal(compiled.definition.play_target,null);
 assert.doesNotThrow(()=>validateKeyword(keyword));
 const fixtures={chosen:card,multiple:{...card,abilities:[{trigger:'on_play',effects:[{...intel,amount:9},{op:'draw',player:'owner',amount:1}]}]},random:{...card,abilities:[{trigger:'on_play',effects:[{op:'intel',amount:2}]}]}};
 for(const wrap of [e=>e,e=>({op:'choose_effect',options:[{label:'查看',effects:[e]},{label:'抽牌',effects:[{op:'draw',player:'owner',amount:1}]}]})])assert.doesNotThrow(()=>compileCard({...card,abilities:[{trigger:'on_play',effects:[wrap(intel)]}]},{}));
 assert.doesNotThrow(()=>compileCard({...card,tokens:[{token_id:'peek',name:'衍生窥探',kind:'order',unit_class:null,cost:0,operation_cost:0,attack:0,health:0,keywords:[],abilities:card.abilities}]},{}));
 for(const selection of ['all','top','enemy',null,3])assert.throws(()=>compileCard({...card,abilities:[{trigger:'on_play',effects:[{...intel,selection}]}]},{}));
 const validate=new Ajv({strict:false}).compile(JSON.parse(promptSchema(schemas.card)));
 assert(validate(card),JSON.stringify(validate.errors));
 writeFileSync(new URL('../../tests/fixtures/intel287.json',import.meta.url),JSON.stringify({fixtures,hashes:Object.fromEntries(Object.entries(fixtures).map(([k,v])=>[k,compileCard(v,{}).compiled_program_hash])),keyword},null,2));
});

test('CZ-287 generation knows hidden-position selection without requiring a unit target',()=>{
 for(const kind of ['card','keyword','mechanism-review'])for(const bp of [null,blueprint(card),blueprint(card,'replace')]){
  const prompt=makePrompt(kind,[],bp);
  assert(prompt.includes('按卡背位置选未公开的敌方手牌'));
  assert(prompt.includes('不能设置单位play_target'));
  assert(Buffer.byteLength(prompt)<200000,`${kind}: ${Buffer.byteLength(prompt)}`);
 }
});
