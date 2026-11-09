import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {deflateSync} from 'node:zlib';
import {PNG} from 'pngjs';
import {createApp} from '../src/index.js';
import {RequestBudget} from '../src/request_limits.js';
import {inspectPNG} from '../src/png_guard.js';
import {decodeEmote} from '../src/emote_decode.js';
import {ImageWorkers} from '../src/image_workers.js';
import {CentralMatches} from '../src/central_matches.js';
import {validateKeyword} from '../src/validation.js';

const provider={configured:false,model:'test',async generate(){throw Error('No upstream calls');}};
async function fixture(t,options={}){
  const dataDir=await mkdtemp(join(tmpdir(),'chao-security-'));
  const app=await createApp({dataDir,provider,centralMode:true,inviteToken:'isolated-audit-invite-0123456789',matches:false,host:'127.0.0.1',port:0,...options});
  const address=await app.listen(),base=`http://127.0.0.1:${address.port}`;
  t.after(async()=>{await app.close();await rm(dataDir,{recursive:true,force:true});});
  return {app,base};
}
// A streaming client that deliberately has NOT sent the final HTTP chunk.
function unfinished(base){
  let request;
  const response=new Promise((resolve,reject)=>{
    request=http.request(base+'/v1/accounts/login',{method:'POST',headers:{'Content-Type':'application/json'}},res=>{
      const chunks=[];res.on('data',c=>chunks.push(c));res.on('end',()=>resolve({status:res.statusCode,body:JSON.parse(Buffer.concat(chunks))}));
    });request.on('error',reject);
  });
  return {request,response};
}

test('chunked oversized body is rejected before EOF; health remains responsive', {timeout:10000},async t=>{
  const {base}=await fixture(t);
  const {request,response}=unfinished(base);t.after(()=>request.destroy());
  request.write('x'.repeat(4097));
  const result=await response;
  assert.equal(result.status,413);assert.equal(result.body.error.code,'INPUT_TOO_LONG');
  assert.equal((await fetch(base+'/health')).status,200);
});

test('stalled uploads expire without occupying the write budget; aborted and rejected requests release it', {timeout:10000},async t=>{
  const {base}=await fixture(t,{requestLimits:{maxRequests:1},bodyTimeoutMs:80});
  const first=unfinished(base);t.after(()=>first.request.destroy());first.request.write('{');
  await new Promise(r=>setTimeout(r,15));
  const second=await fetch(base+'/v1/accounts/login',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
  assert.equal(second.status,429);
  assert.equal((await fetch(base+'/health')).status,200);
  assert.equal((await first.response).status,408);
  const after=await fetch(base+'/v1/accounts/login',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
  assert.equal(after.status,400);
  const interrupted=unfinished(base);interrupted.response.catch(()=>{});interrupted.request.write('{');
  await new Promise(r=>setTimeout(r,15));interrupted.request.destroy();await new Promise(r=>setTimeout(r,15));
  assert.equal((await fetch(base+'/v1/accounts/login',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,400);
});

test('body reservations cap aggregate memory and per-owner work, with idempotent cleanup',()=>{
  const budget=new RequestBudget({maxRequests:3,maxPerOwner:1,maxBytes:10});
  const a=budget.acquire('a',6);
  assert.throws(()=>budget.acquire('a',1),{code:'RATE_LIMITED'});
  assert.throws(()=>budget.acquire('b',5),{code:'RATE_LIMITED'});
  const b=budget.acquire('b',4);a();a();b();
  assert.equal(budget.requests,0);assert.equal(budget.bytes,0);assert.equal(budget.owners.size,0);
});

test('non-object JSON and prototype-shaped input return validation errors, not server faults',async t=>{
  const {base}=await fixture(t);
  for(const body of ['null','[]','3','{"__proto__":{"role":"admin"}}']){
    const res=await fetch(base+'/v1/accounts/login',{method:'POST',headers:{'Content-Type':'application/json'},body});
    assert.equal(res.status,400);assert.equal((await res.json()).error.code,'INVALID_REQUEST');
  }
  assert.equal({}.role,undefined);
});

test('frozen keyword catalog selectors reject malformed hashes and preserve valid historical lookups',async t=>{
  const {base}=await fixture(t,{centralMode:false});
  const current=await (await fetch(base+'/v1/keywords')).json();
  for(const selector of ['constructor','__proto__','toString','invalid',current.keyword_registry_hash.toUpperCase()]){
    const res=await fetch(base+'/v1/keywords?registry_hash='+encodeURIComponent(selector));
    assert.equal(res.status,400,selector);
    assert.equal((await res.json()).error.code,'INVALID_REQUEST');
  }
  const known=await fetch(base+'/v1/keywords?registry_hash='+current.keyword_registry_hash);
  assert.equal(known.status,200);assert.deepEqual(await known.json(),current);
  const unknown=await fetch(base+'/v1/keywords?registry_hash='+'0'.repeat(64));
  assert.equal(unknown.status,404);assert.equal((await unknown.json()).error.code,'NOT_FOUND');
});

const crc32=bytes=>{let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0;};
function chunk(type,bytes){const out=Buffer.alloc(bytes.length+12);out.writeUInt32BE(bytes.length);out.write(type,4,'ascii');bytes.copy(out,8);out.writeUInt32BE(crc32(out.subarray(4,-4)),out.length-4);return out;}
function interlaced(raw=Buffer.from([0,12,34,56,128])){
  const header=Buffer.alloc(13);header.writeUInt32BE(1);header.writeUInt32BE(1,4);header[8]=8;header[9]=6;header[12]=1;
  return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
}

test('PNG guard rejects duplicate headers, missing end, trailing payload and compressed expansion',()=>{
  const good=interlaced();assert.deepEqual(inspectPNG(good),{width:1,height:1});
  for(const bad of [Buffer.concat([good.subarray(0,33),good.subarray(8)]),good.subarray(0,-12),Buffer.concat([good,Buffer.from('extra')]),interlaced(Buffer.alloc(1024*1024))]){
    assert.throws(()=>inspectPNG(bad),/PNG/);assert.throws(()=>decodeEmote(bad),/PNG/);
  }
});

test('valid interlaced PNG retains translucent pixels',()=>{
  const image=PNG.sync.read(decodeEmote(interlaced()).png);
  assert.equal(image.width,1);assert.deepEqual([...image.data],[12,34,56,128]);
});

test('multiplicative keyword validation work is bounded while ordinary parameter ranges stay valid',()=>{
  const effects=['a','b','c','d'].map(param=>({op:'draw',player:'owner',amount:{param}}));
  const definition={schema_version:'1.0.0',ruleset_version:'frontline-1',id:'custom.audit',version:1,name:'预算检查',aliases:[],description:'检查',parameters:Object.fromEntries(['a','b','c','d'].map(p=>[p,{type:'integer',minimum:1,maximum:10}])),implementation:{kind:'template',abilities:Array.from({length:4},()=>({trigger:'on_play',effects}))}};
  assert.throws(()=>validateKeyword(definition),{code:'RULE_BUDGET_EXCEEDED'});
  for(const p of Object.values(definition.parameters))p.maximum=3;
  assert.doesNotThrow(()=>validateKeyword(definition));
  const workBudget={remaining:15000};
  assert.doesNotThrow(()=>validateKeyword(definition,{workBudget}));
  assert.throws(()=>validateKeyword(definition,{workBudget}),{code:'RULE_BUDGET_EXCEEDED'});
});

test('card art is decoded in shared bounded workers and shutdown releases outstanding tasks',async()=>{
  const pool=new ImageWorkers();
  try{
    const input=PNG.sync.write({width:1,height:1,data:Buffer.from([7,8,9,127])});
    const a=pool.decode('./card_art_decode.js',input,'INVALID_ART'),b=pool.decode('./emote_decode.js',input,'INVALID_EMOTE');
    assert.throws(()=>pool.decode('./card_art_decode.js',input,'INVALID_ART'),{code:'RATE_LIMITED'});
    const [art,emote]=await Promise.all([a,b]);
    assert.deepEqual([...PNG.sync.read(Buffer.from(art.png)).data],[7,8,9,127]);assert(emote.ok);
    const canceled=pool.decode('./card_art_decode.js',input,'INVALID_ART');pool.close();
    await assert.rejects(canceled,{code:'INVALID_ART'});assert.equal(pool.tasks.size,0);
  }finally{pool.close();}
});

test('room backlog and lobby backlog are bounded; sweeps do not abort a busy match',async t=>{
  const central=new CentralMatches({store:{state:{}}});t.after(()=>central.close());
  clearInterval(central.sweepTimer);
  let unblock;const gate=new Promise(resolve=>unblock=resolve),room={id:'audit-room',status:'active',queue:Promise.resolve()};
  central.rooms.set(room.id,room);let aborted=false;central.abort=async()=>{aborted=true;};central.reconcile=async()=>{};
  const jobs=Array.from({length:64},()=>central.serial(room,()=>gate));
  await assert.rejects(central.serial(room,()=>{}),{code:'RATE_LIMITED'});
  await central.sweep();assert.equal(aborted,false);assert.equal(room.pendingOperations,64);
  unblock();await Promise.all(jobs);assert.equal(room.pendingOperations,0);
  await assert.rejects(central.serial(room,()=>{throw Error('expected');}),/expected/);
  assert.equal(room.pendingOperations,0);await central.serial(room,()=>{});
  let release;const pending=new Promise(resolve=>release=resolve);
  const lobby=Array.from({length:32},()=>central.global(()=>pending));
  await assert.rejects(central.global(()=>{}),{code:'RATE_LIMITED'});release();await Promise.all(lobby);assert.equal(central.globalPending,0);
  central.rooms.clear();
});
