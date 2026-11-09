import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {Store} from '../src/store.js';
import {CardService} from '../src/service.js';
import {CloudCatalog} from '../src/cloud_catalog.js';
import {derivedId} from '../src/derived_cards.js';
import {compileCard,applyCardBlueprint,validateCardBlueprint} from '../src/validation.js';
import {freshCard,blueprint} from '../../web/model.mjs';
import {cardFace} from '../../web/catalog.mjs';
const draw={trigger:'on_play',effects:[{op:'draw',player:'owner',amount:1}]};
const card=()=>({...freshCard(),name:'手写描述',abilities:[structuredClone(draw)]});

test('manual descriptions are display-only, literal, optional, and validated for parents and tokens',()=>{
 const c=card(),automatic=compileCard(c,{});c.display_text='闪击（这是手写的）\n<script>自定义</script> [b]文字[/b]';
 const result=compileCard(c,{});assert.equal(result.short_rules_text,c.display_text);
 assert.equal(result.rules_text,automatic.rules_text);assert.deepEqual(result.compiled_program.expanded_definition.abilities,c.abilities);
 assert.match(result.detailed_text,/实际机制\n.*抽/u);
 const html=cardFace({definition:c,rules_text:'陈旧缓存'},[]);assert(html.includes('&lt;script&gt;'));assert(!html.includes('<script>'));assert(!html.includes('陈旧缓存'));
 c.display_text=' \n ';assert.equal(compileCard(c,{}).short_rules_text,automatic.short_rules_text);
 for(const bad of [null,1,{},'x'.repeat(2001),'bad\u0000text']){c.display_text=bad;assert.throws(()=>compileCard(c,{}));}
 const parent=card();parent.tokens=[{token_id:'child',name:'衍生',unit_class:'infantry',attack:1,health:1,keywords:[],display_text:'\u0000'}];
 assert.throws(()=>compileCard(parent,{}));
});

test('AI append preserves author text even when the model omits or rewrites it',()=>{
 const fixed=card();fixed.display_text='登场：补给。';fixed.tokens=[{token_id:'child',name:'衍生',unit_class:'infantry',attack:1,health:1,keywords:[],display_text:'我的衍生描述'}];
 const bp=blueprint(fixed);validateCardBlueprint(bp,{});
 for(const rewrite of [undefined,'模型擅自改写']){
  const candidate=card();candidate.tokens=structuredClone(fixed.tokens);
  if(rewrite===undefined)delete candidate.tokens[0].display_text;else candidate.tokens[0].display_text=rewrite;
  candidate.display_text=rewrite;
  const merged=applyCardBlueprint(candidate,bp);assert.equal(merged.display_text,fixed.display_text);assert.equal(merged.tokens[0].display_text,fixed.tokens[0].display_text);
 }
 const candidate=card();candidate.display_text='模型描述';assert(!Object.hasOwn(applyCardBlueprint(candidate,blueprint(card())),'display_text'));
});

test('saving and clearing text revises both catalogs, retains old versions, and enforces ownership',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'chao-text860-')),store=await new Store(dir).init();
 try{
  const service=new CardService(store,{configured:false,model:'test'}),catalog=new CloudCatalog(service),faction=randomUUID();
  await store.transaction(s=>s.factions[faction]={faction_id:faction,name:'阵营',color:'#334455',role:'major',owner_id:'alice'});
  const c={...card(),faction_id:faction,display_text:'自写正文\n（请保留括号）',tokens:[{token_id:'child',name:'衍生',unit_class:'infantry',attack:1,health:1,keywords:[],display_text:'衍生的正文'}]};
  const save=async(d,previous,owner='alice')=>{const draft=await service.manualDraft(owner,{request_id:randomUUID(),definition:d});return service.confirmCard(owner,{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash,...(previous?{base_revision:previous.revision}:{})},previous?.card_id);};
  const first=await save(c),child=derivedId(first.card_id,'child');
  assert.equal(catalog.card(null,first.card_id).rules_text,c.display_text);assert.equal(catalog.card(null,child).rules_text,c.tokens[0].display_text);
  assert.match(catalog.card(null,first.card_id).detailed_text,/实际机制/);
  await assert.rejects(save({...c,display_text:'越权'},first,'bob'));
  const cleared=structuredClone(c);delete cleared.display_text;delete cleared.tokens[0].display_text;
  await save(cleared,first);assert.notEqual(catalog.card(null,first.card_id).rules_text,c.display_text);
  assert.equal(catalog.card(null,first.card_id,1).rules_text,c.display_text);assert.equal(catalog.card(null,child,1).rules_text,c.tokens[0].display_text);
  assert(!Object.hasOwn(catalog.card(null,child).definition,'display_text'));
 }finally{await store.close();await rm(dir,{recursive:true,force:true});}
});
