import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {catalogUpdates} from '../src/catalog_updates.js';
test('catalog delta is stable across restarts and tracks all public card metadata',()=>{
 const ids=[randomUUID(),randomUUID(),randomUUID()];
 const snapshot={cards:[{card_id:ids[0],revision:1,definition:{name:'A'},art:null,author:{name:'A'}},{card_id:ids[1],revision:1,definition:{name:'B'}}],keywords:[{name:'守护'}],factions:[{name:'阵营'}],lifecycle:{cards:{},keywords:{},factions:{}}};
 const first=catalogUpdates({},snapshot);assert.equal(first.cards.length,2);
 const unchanged=catalogUpdates(JSON.parse(JSON.stringify(first.fingerprints)),structuredClone(snapshot));
 assert.deepEqual(unchanged.cards,[]);for(const key of ['keywords','factions','lifecycle'])assert.equal(unchanged[key],null);
 snapshot.cards[0].author.name='新作者名';snapshot.cards[0].art={id:'a'.repeat(64)};snapshot.cards.push({card_id:ids[2],revision:1});
 const update=catalogUpdates(first.fingerprints,snapshot);assert.deepEqual(update.cards.map(c=>c.card_id),[ids[0],ids[2]]);
 snapshot.cards.splice(1,1);snapshot.lifecycle.cards[ids[1]]={deleted:true};snapshot.keywords[0].name='新词条名';
 const deleted=catalogUpdates(update.fingerprints,snapshot);assert.deepEqual(deleted.removed,[ids[1]]);assert.deepEqual(deleted.cards,[]);assert.ok(deleted.keywords);assert.ok(deleted.lifecycle);
});
test('invalid client catalog manifests are rejected',()=>{
 const snapshot={cards:[],keywords:[],factions:[],lifecycle:{}};
 for(const input of [null,[],{unknown:1},{cards:[]},{cards:{bad:'a'.repeat(64)}},{cards:{[randomUUID()]:'not-a-hash'}},{keywords:12},{factions:'bad'}])assert.throws(()=>catalogUpdates(input,snapshot));
 assert.deepEqual(catalogUpdates({},snapshot).cards,[]);
});
