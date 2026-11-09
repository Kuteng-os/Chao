import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Store} from '../src/store.js';
import {CardMedia,validateMedia,inspectWav} from '../src/card_media.js';
import {compileCard,validateKeyword,validateCardBlueprint,applyCardBlueprint} from '../src/validation.js';
import {makePrompt} from '../src/provider.js';
const field=()=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name:'测试场地',flavor_text:'',kind:'field',unit_class:null,cost:1,operation_cost:0,attack:0,health:0,keywords:[],play_target:null,abilities:[],tokens:[],appearance:{emblem:'field'}});
const aura=()=>({trigger:'while_active',effects:[{op:'modify_stats',target:'all_friendly_units',attack_delta:1,health_delta:0,duration:'battle'}]});
function wav(seconds=1){const b=Buffer.alloc(44+Math.round(seconds*22050)*2);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVE',8);b.write('fmt ',12);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(22050,24);b.writeUInt32LE(44100,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(b.length-44,40);return b;}
test('field compiler accepts bounded auras and rejects non-unit lifecycle',()=>{
 const c=field();assert.ok(compileCard(c,{}));c.abilities=[aura()];assert.match(compileCard(c,{}).rules_text,/场地生效期间/);
 for(const trigger of ['on_death','on_summon','on_reveal']){c.abilities[0].trigger=trigger;assert.throws(()=>compileCard(c,{}));}
 for(const effect of [{op:'draw',player:'owner',amount:1},{...aura().effects[0],attack_delta:{stat:'enemy_unit_count'}},{...aura().effects[0],target:'self'}]){c.abilities=[{trigger:'while_active',effects:[effect]}];assert.throws(()=>compileCard(c,{}));}
 c.abilities=[aura()];c.media={sounds:{play:'a'.repeat(64)},background:'b'.repeat(64),music:'c'.repeat(64)};
 const {schema_version,ruleset_version,flavor_text,...bp}=c;const fixed=validateCardBlueprint(bp,{});assert.deepEqual(applyCardBlueprint({...c,media:{sounds:{}}},fixed,{mergeEffects:false}).media,c.media);
 c.kind='order';c.appearance.emblem='order';assert.throws(()=>compileCard(c,{}));
 assert.match(makePrompt('mechanism-review',[]),/双方共享唯一场地/);
});
test('field aura templates support fixed integer parameters',()=>{
 const d={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.test_field',version:1,name:'战地激励',description:'友方攻击增加',aliases:[],parameters:{n:{type:'integer',minimum:1,maximum:3}},implementation:{kind:'template',abilities:[aura()]}};
 d.implementation.abilities[0].effects[0].attack_delta={param:'n'};assert.ok(validateKeyword(d));
});
test('audio uploads are bounded, durable and referenced by authorized assets',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'chao-media-'));const store=await new Store(dir).init();
 try{const service=new CardMedia(store),input=wav(),result=await service.upload('alice',{kind:'sound',wav_base64:input.toString('base64')});assert.deepEqual(await service.audio(result.asset.id),input);assert.equal(inspectWav(input),1);
 const c=field();c.media={sounds:{play:result.asset.id}};validateMedia(store.state,'alice',c);assert.throws(()=>validateMedia(store.state,'bob',c));
 store.state.cards.test=[{definition:c}];validateMedia(store.state,'bob',c);
 await assert.rejects(service.upload('alice',{kind:'sound',wav_base64:wav(13).toString('base64')}));
 const music=await service.upload('alice',{kind:'music',wav_base64:wav(13).toString('base64')});c.media.sounds.play=music.asset.id;assert.throws(()=>validateMedia(store.state,'alice',c));delete c.media.sounds.play;c.media.music=music.asset.id;validateMedia(store.state,'alice',c);
 for(const data of [Buffer.from('bad'),Buffer.concat([input,Buffer.from('extra')]),(()=>{const b=Buffer.from(input);b.writeUInt32LE(0xffffffff,40);return b;})()])assert.throws(()=>inspectWav(data));
 }finally{await store.close();await rm(dir,{recursive:true,force:true});}
});
