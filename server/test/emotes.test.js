import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID,createHash} from 'node:crypto';
import {PNG} from 'pngjs';
import {decodeEmote} from '../src/emote_decode.js';
import {createApp} from '../src/index.js';
import {CentralMatches} from '../src/central_matches.js';
const fixtures=JSON.parse(await readFile(new URL('./emote_fixtures.json',import.meta.url),'utf8'));
const provider={configured:false,model:'test',async generate(){throw Error('No provider calls');}};
const inviteToken='emote-test-only-invite-1234567890';

test('GIF animation preserves transparent pixels, timing, clear and restore-previous disposal',()=>{
  for(const fixture of fixtures){
    const result=decodeEmote(Buffer.from(fixture.gif,'base64')),atlas=PNG.sync.read(result.png);
    assert.deepEqual(result.durations,[80,140,240]);assert.equal(result.columns,3);
    for(let f=0;f<3;f++)for(let y=0;y<4;y++)for(let x=0;x<6;x++){
      const i=(y*6+x)*4,a=(y*atlas.width+f*6+x)*4;
      assert.equal(atlas.data[a+3],fixture.pixels[f][i+3]);
      if(atlas.data[a+3])assert.deepEqual([...atlas.data.subarray(a,a+3)],fixture.pixels[f].slice(i,i+3));
    }
  }
  const bad=Buffer.from(fixtures[0].gif,'base64');bad.writeUInt16LE(65535,6);assert.throws(()=>decodeEmote(bad),/1024/);
  assert.throws(()=>decodeEmote(Buffer.from('<script>bad</script>')),/GIF/);
  const png=PNG.sync.write({width:2,height:1,data:Buffer.from([1,2,3,0,10,20,30,127])});
  const output=PNG.sync.read(decodeEmote(png).png);assert.deepEqual(output.data,Buffer.from([1,2,3,0,10,20,30,127]));
});

test('author upload, public atlas, eight slots, isolation, delete, and restart through HTTP',async t=>{
  const dataDir=await mkdtemp(join(tmpdir(),'chao-emotes-'));
  const options={centralMode:true,inviteToken,matches:false,host:'127.0.0.1',port:0,provider,dataDir};
  let app=await createApp(options),address=await app.listen(),base=`http://127.0.0.1:${address.port}`;
  t.after(async()=>{await app.close();await rm(dataDir,{recursive:true,force:true});});
  async function req(path,body,token,method=body===undefined?'GET':'POST'){
    const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});
    return {status:r.status,body:r.headers.get('content-type')?.includes('image/')?Buffer.from(await r.arrayBuffer()):await r.json()};
  }
  const a=(await req('/v1/sessions',{invite_code:inviteToken,display_name:'作者 A'})).body,b=(await req('/v1/sessions',{invite_code:inviteToken,display_name:'作者 B'})).body;
  const body={name:'透明动画',image_base64:fixtures[0].gif};
  assert.equal((await req('/v1/emotes',body)).status,401);
  assert.equal((await req('/v1/emotes',{...body,name:'x'.repeat(25)},a.access_token)).status,422);
  const created=await req('/v1/emotes',body,a.access_token);assert.equal(created.status,201,JSON.stringify(created.body));
  const e=created.body.emote;assert.equal(e.owner_id,a.owner_id);
  assert.equal(e.scale_percent,46,'legacy size is preserved by default');
  const listed=(await req('/v1/public/emotes')).body.emotes;assert.equal(listed[0].author,'作者 A');
  const atlas=(await req('/v1/emotes/assets/'+e.asset_id+'.png')).body;assert.equal(createHash('sha256').update(atlas).digest('hex'),e.asset_id);
  assert.equal((await req('/v1/emote-loadout',{slots:[e.emote_id]},a.access_token,'PUT')).status,422);
  assert.equal((await req('/v1/emote-loadout',{slots:Array(8).fill(randomUUID())},a.access_token,'PUT')).status,422);
  const slots=[e.emote_id,'','','',e.emote_id,'','',''];
  assert.equal((await req('/v1/emote-loadout',{slots},a.access_token,'PUT')).status,200);
  assert.deepEqual((await req('/v1/emote-loadout',undefined,b.access_token)).body.slots,Array(8).fill(''));
  assert.equal((await req('/v1/emotes/'+e.emote_id,{name:'偷改'},b.access_token,'PATCH')).status,403);
  assert.equal((await req('/v1/emotes/'+e.emote_id,{name:'改名'},a.access_token,'PATCH')).status,200);
  assert.equal((await req('/v1/emotes/'+e.emote_id,{scale_percent:150},b.access_token,'PATCH')).status,403);
  for(const scale of [0,24,201,'100',null])assert.equal((await req('/v1/emotes/'+e.emote_id,{scale_percent:scale},a.access_token,'PATCH')).status,422);
  assert.equal((await req('/v1/emotes/'+e.emote_id,{scale_percent:150},a.access_token,'PATCH')).status,200);
  await app.close();app=await createApp(options);address=await app.listen();base=`http://127.0.0.1:${address.port}`;
  assert.deepEqual((await req('/v1/emote-loadout',undefined,a.access_token)).body.slots,slots);
  assert.equal((await req('/v1/public/emotes')).body.emotes[0].name,'改名');
  assert.equal((await req('/v1/public/emotes')).body.emotes[0].scale_percent,150,'author scale survives restart');
  assert.equal((await req('/v1/emotes/'+e.emote_id+'/delete',{},b.access_token)).status,403);
  assert.equal((await req('/v1/emotes/'+e.emote_id+'/delete',{},a.access_token)).status,200);
  assert.deepEqual((await req('/v1/public/emotes')).body.emotes,[]);
  assert.deepEqual((await req('/v1/emote-loadout',undefined,a.access_token)).body.slots,Array(8).fill(''));
});

test('emotes reach both seats without consuming a move or exposing private state; retries and cooldown',async t=>{
  const id=randomUUID(),owners=[randomUUID(),randomUUID()],entry={emote_id:id,scale_percent:125};
  const central=new CentralMatches({store:{state:{emotes:{[id]:entry},identities:{}}}});t.after(()=>central.close());
  const room={id:randomUUID(),code:'123456',status:'active',players:owners,views:[{state_seq:12,players:[{hand:['own']},{hand:[]}]},{state_seq:12,players:[{hand:[]},{hand:['opponent']}] }],seq:12,lastSeen:[Date.now(),Date.now()],queue:Promise.resolve()};
  central.rooms.set(room.id,room);
  const body={request_id:randomUUID(),emote_id:id,point:[2500,7500]};
  const send=(owner,b)=>central.handle({method:'POST',pathname:`/v1/rooms/${room.id}/emotes`,owner,body:b});
  await assert.rejects(send(randomUUID(),body),e=>e.code==='FORBIDDEN');
  await assert.rejects(send(owners[0],{...body,point:[-1,1]}),e=>e.code==='INVALID_EMOTE');
  const sent=await send(owners[0],body);assert.equal(sent.body.state_seq,12);assert.equal(sent.body.emote_events.length,1);assert.equal(sent.body.emote_events[0].player,0);assert.deepEqual(sent.body.emote_events[0].point,[2500,7500]);
  assert.deepEqual(central.snapshot(room,1).emote_events,sent.body.emote_events);
  assert.equal(sent.body.emote_events[0].scale_percent,125,'both seats receive authoritative size');
  entry.scale_percent=50;assert.equal(central.snapshot(room,1).emote_events[0].scale_percent,125,'published event retains its size after author edit');
  await assert.rejects(send(owners[0],{...body,scale_percent:200}),e=>e.code==='INVALID_REQUEST');
  assert.deepEqual(central.snapshot(room,1).state.players[0].hand,[]);
  await send(owners[0],body);assert.equal(room.emoteEvents.length,1);
  await assert.rejects(send(owners[0],{...body,point:[5000,5000]}),e=>e.code==='IDEMPOTENCY_CONFLICT');
  await assert.rejects(send(owners[0],{...body,request_id:randomUUID()}),e=>e.code==='RATE_LIMITED');
  await send(owners[1],{...body,request_id:randomUUID()});assert.equal(room.emoteEvents.length,2);
  room.emoteEvents[0].sent_at-=6000;assert.equal(central.snapshot(room,0).emote_events.length,1);
  entry.deleted=true;await assert.rejects(send(owners[1],{...body,request_id:randomUUID()}),e=>e.code==='NOT_FOUND');
  central.rooms.clear();
});
