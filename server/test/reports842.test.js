import test from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {compileCard,validateKeyword,schemas} from '../src/validation.js';
import {freshCard,changeKind,editorError} from '../../web/model.mjs';
import {makePrompt,promptSchema} from '../src/provider.js';
import Ajv from 'ajv';
const base=(name,kind='order')=>({...changeKind(freshCard(),kind),name});
const faction='408c3c32-19c5-49ce-9a9d-055c38d516ba';
const kill={...base('击杀追加'),play_target:{side:'enemy',row:'any'},abilities:[{trigger:'on_play',effects:[{op:'damage',target:'chosen',amount:2},{op:'draw',player:'owner',amount:1},{op:'if_killed',effects:[{op:'draw',player:'owner',amount:1}]}]}]};
const gear={...base('阵营装备'),play_target:{side:'ally',row:'any',faction_id:faction},abilities:[{trigger:'on_play',effects:[{op:'equip',target:'chosen',tag:'剑',amount:1}]}]};
const choice={...base('双心'),abilities:[{trigger:'on_play',effects:[{op:'choose_effect',options:[{label:'抽牌',effects:[{op:'draw',player:'owner',amount:2}]},{label:'总部强化',effects:[{op:'gain_hq_defense',player:'owner',amount:7},{op:'schedule',trigger:'next_own_turn_start',after_turns:1,effects:[{op:'gain_hq_defense',player:'owner',amount:2}]}]}]}]}]};
const undead={...base('亡灵','unit'),abilities:[{trigger:'on_death',effects:[{op:'transfer_card',source:'self',mode:'move',destination:'hand',selection:'random',amount:1}]}]};
const fixtures=[kill,gear,choice,undead].map(c=>compileCard(c,{}));
writeFileSync(new URL('../../tests/reports842.json',import.meta.url),JSON.stringify({cards:fixtures}));
test('89-98 compile in schema, editor, blueprint and keyword templates',()=>{
 for(const c of [kill,gear,choice,undead]){assert.equal(editorError(c),'');assert(!compileCard(c,{}).rules_text.includes('[object'));const k={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.case',version:1,name:'测试机制',description:'测试',aliases:[],parameters:{},implementation:{kind:'template',abilities:c.abilities}};assert(validateKeyword(k));}
 assert.match(fixtures[0].rules_text,/若刚才的伤害消灭/);assert.match(fixtures[1].rules_text,/指定阵营/);assert.match(fixtures[2].rules_text,/后续第1回合/);assert.match(fixtures[3].rules_text,/原卡返回/);
 for(const kind of ['card','keyword','mechanism-review'])for(const s of ['if_killed','schedule','阵亡原卡回手'])assert(makePrompt(kind,[]).includes(s));
});
test('reject ambiguous death returns, absent kill predecessor, unsafe delayed targets and invalid factions',()=>{
 const check=(c,fn)=>{c=structuredClone(c);fn(c);assert.throws(()=>compileCard(c,{}));};
 check(kill,c=>c.abilities[0].effects.shift());check(kill,c=>c.abilities[0].effects[2].effects=[{op:'if_killed',effects:[{op:'noop'}]}]);
 for(const patch of [{amount:2},{destination:'support'},{filter:{kind:'unit'}},{selection:'top'},{inherit_from:[]}])check(undead,c=>Object.assign(c.abilities[0].effects[0],patch));
 check(undead,c=>c.abilities[0].trigger='on_play');
 for(const patch of [{faction_id:'剑'},{include_hq:true}])check(gear,c=>Object.assign(c.play_target,patch));
 const delayed=()=>structuredClone(choice.abilities[0].effects[0].options[1].effects[1]);
 const captured=structuredClone(choice);captured.play_target={side:'ally',row:'any'};captured.abilities[0].effects=[{...delayed(),effects:[{op:'heal',target:'chosen',amount:2}]}];assert.doesNotThrow(()=>compileCard(captured,{}));
 check(captured,c=>c.abilities[0].effects[0].lifetime='source');
 for(const amount of [0,100,1.5]){const e=delayed();e.after_turns=amount;check(choice,c=>c.abilities[0].effects=[e]);}
 for(const e of [{op:'heal',target:'chosen',amount:2},delayed()]){const d=delayed();d.effects=[e];check(choice,c=>c.abilities[0].effects=[d]);}
});
test('deduplicated prompt schemas resolve without losing constraints',()=>{
 const ajv=new Ajv({strict:false});const compact=JSON.parse(promptSchema(schemas.card));const validate=ajv.compile(compact);
 assert(promptSchema(schemas.card).length<JSON.stringify(schemas.card).length);
 for(const c of [kill,gear,choice,undead])assert(validate(c),JSON.stringify(validate.errors));
 const bad=structuredClone(choice);bad.abilities[0].effects[0].options[1].effects[1].after_turns=0;assert(!validate(bad));
 for(const kind of ['card','keyword','mechanism-review'])assert(Buffer.byteLength(makePrompt(kind,[]))<200000);
});
