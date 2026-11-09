import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createApp} from '../src/index.js';
import {publishTestDeck} from '../../tools/publish_test_deck.mjs';

test('generic test deck publishes 40 legal cards with all unit classes and counter triggers, and retries without duplicates',async t=>{
  const dataDir=await mkdtemp(join(tmpdir(),'frontline-test-deck-')),invite='test-deck-invite-only-123456789';
  const app=await createApp({dataDir,host:'127.0.0.1',port:0,centralMode:true,inviteToken:invite,matches:false,provider:{configured:false,model:'test'}}),address=await app.listen();
  t.after(async()=>{await app.close();await rm(dataDir,{recursive:true,force:true});});
  const request=async(path,body,token)=>{
    const response=await fetch(`http://127.0.0.1:${address.port}`+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});
    const result=await response.json();assert(response.ok,JSON.stringify(result.error));return result;
  };
  const journal={operations:{}};
  const first=await publishTestDeck(request,journal,async()=>{},invite);
  const repeated=await publishTestDeck(request,journal,async()=>{},invite);
  assert.deepEqual(repeated,first);assert.equal(first.card_count,40);assert.equal(first.unique_cards,14);
  const detail=await request('/v1/public/decks/'+first.deck_id),definitions=detail.cards.map(c=>c.definition);
  assert.equal(detail.deck.author.name,'测试牌组');
  assert.equal(definitions.filter(d=>d.kind==='unit').length,8);
  assert.equal(definitions.filter(d=>d.kind==='order').length,3);
  assert.equal(definitions.filter(d=>d.kind==='counter').length,3);
  assert.equal(new Set(definitions.filter(d=>d.kind==='unit').map(d=>d.unit_class)).size,5);
  assert.equal(new Set(definitions.filter(d=>d.kind==='counter').map(d=>d.counter_trigger)).size,3);
  assert.equal(new Set(definitions.map(d=>d.rarity)).size,4);
  assert.equal(Object.keys(app.service.store.state.cards).length,14);
  assert.equal(Object.keys(app.service.store.state.shared_decks).length,1);
  assert.equal(Object.keys(app.service.store.state.accounts).length,0,'Publisher identity does not create privileged login accounts');
});
