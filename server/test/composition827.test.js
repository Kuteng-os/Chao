import test from 'node:test';
import assert from 'node:assert/strict';
import {compileCard,rulesText} from '../src/validation.js';
import {validatePremise,premiseText} from '../src/premises.js';
import {freshCard,changeKind,readyCard} from '../../web/model.mjs';
import {filterCards,filterDefaults,cleanFilters,filterError,cardFace} from '../../web/catalog.mjs';
import {makePrompt} from '../src/provider.js';
const card=()=>({...freshCard(),name:'测试'});
const count=(side='ally',unit_classes=['fighter','bomber'])=>({test:'compare',left:{count_units:{side,unit_classes}},cmp:'gte',right:1});
test('typed conditions, selectors, durations and adjacency compile through both card and shared schema',()=>{
 const c={...changeKind(card(),'order'),play_target:{side:'enemy',row:'any',unit_classes:['tank']},abilities:[{trigger:'on_play',premise:count(),effects:[{op:'modify_stats',target:'adjacent_to_chosen',attack_delta:1,health_delta:2,duration:'match'}]}]};
 const r=compileCard(c,{});assert.match(r.rules_text,/永久/);assert.match(r.rules_text,/空军/);assert.match(r.rules_text,/坦克/);assert(readyCard(c,[]).play_target);
 for(const invalid of [{side:'wrong'},{side:'ally',unit_classes:[]},{side:'ally',unit_classes:['tank','tank']},{side:'ally',unit_classes:['navy']},{side:'ally',code:'eval'}])assert.throws(()=>validatePremise({...count(),left:{count_units:invalid}}));
 for(const side of ['ally','enemy','any'])for(const type of ['infantry','tank','artillery','fighter','bomber'])assert.doesNotThrow(()=>compileCard({...c,abilities:[{...c.abilities[0],premise:count(side,[type])}]},{}));
 const invalid=structuredClone(c);invalid.play_target.include_hq=true;assert.throws(()=>compileCard(invalid,{}));
 invalid.play_target=null;assert.throws(()=>compileCard(invalid,{}));
 const long={...card(),name:'长'.repeat(64)};assert.doesNotThrow(()=>compileCard(long,{}));assert.throws(()=>compileCard({...long,name:'长'.repeat(65)},{}));
 for(const kind of ['card','keyword','mechanism-review'])for(const term of ['count_units','adjacent_to_chosen','match','64字符'])assert(makePrompt(kind,[]).includes(term));
});
test('compact text preserves actual program order and groups recurring trigger headings',()=>{
 const c=card();c.abilities=[{trigger:'on_play',effects:[{op:'pin',target:'all_friendly_units',turns:1},{op:'pin',target:'all_enemy_units',turns:1},{op:'suppress',target:'all_friendly_units'},{op:'suppress',target:'all_enemy_units'}]},{trigger:'next_own_turn_start',premise:{test:'compare',left:{stat:'friendly_unit_count'},cmp:'gt',right:{stat:'enemy_unit_count'}},effects:[{op:'destroy',target:'all_friendly_units'}]},{trigger:'next_own_turn_start',premise:count(),effects:[{op:'damage',target:'own_hq',amount:10}]}];
 const before=JSON.stringify(c),text=rulesText(c);assert.match(text,/抑制所有单位/);assert.match(text,/压制所有单位/);assert.match(text,/己方在场单位更多/);assert.equal(text.match(/己方下回合开始/g).length,1);assert.equal(JSON.stringify(c),before);
});
test('catalog AND filters handle zero, groups, unicode, permission and stable numeric ranges',()=>{
 const records=[{card_id:'a',definition:{...card(),name:'零费坦克',unit_class:'tank',cost:0,attack:0,health:3,keywords:[{id:'core.guard'}]},author:{id:'x',name:'毛巾'},owned_by_me:true,rules_text:'守护'},{card_id:'b',definition:{...card(),name:'火焰飞机',unit_class:'fighter',cost:8,attack:5,health:7,faction_id:'f'},author:{id:'y',name:'他人'},can_edit:true,rules_text:'抽牌'},{card_id:'c',definition:{...changeKind(card(),'order'),name:'指令',cost:0},author:{id:'y',name:'他人'}}];
 const run=f=>filterCards(records,{...filterDefaults,...f},{factions:[{faction_id:'f',name:'元素'}]});
 assert.deepEqual(run({cost:'0',kind:'ground',attackMin:'0',attackMax:'0',keyword:'core.guard',author:'x',own:true,q:'零费 守护'}).map(r=>r.card_id),['a']);
 assert.deepEqual(run({kind:'air',faction:'f',q:'元素 抽牌',cost:'8+'}).map(r=>r.card_id),['b']);
 assert.equal(run({own:true}).length,1);assert.equal(run({healthMin:'1'}).length,2);assert.equal(run({author:'unknown'}).length,0);assert(filterError({...filterDefaults,attackMin:'5',attackMax:'1'}));assert.equal(run({attackMin:'5',attackMax:'1'}).length,0);
 assert.equal(cleanFilters({own:'yes',q:[],sort:123}).own,false);
 const html=cardFace(records[1],[{faction_id:'f',name:'元素',color:'#123456',background_id:'a'.repeat(64)}]);assert.match(html,/data-faction-color="#303538"/);assert.match(html,/a{64}\.png/);assert(!html.includes('作者'));
 const escaped=cardFace({...records[0],definition:{...records[0].definition,name:'<script>'}},[]);assert(!escaped.includes('<script>'));
});
