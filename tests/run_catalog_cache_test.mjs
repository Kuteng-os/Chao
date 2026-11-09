import {createServer} from 'node:http';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {createApp} from '../server/src/index.js';
import {compileCard} from '../server/src/validation.js';
import {FACTION_ID,seedFactions} from '../server/test/faction_fixture.js';
const root=fileURLToPath(new URL('..',import.meta.url)),dir=await mkdtemp(join(tmpdir(),'chao-cache-'));
const provider={configured:false,model:'test',async generate(){throw Error('No model calls');}};
const app=await createApp({dataDir:join(dir,'server'),centralMode:true,inviteToken:'catalog-test-invite-1234567890',host:'127.0.0.1',port:0,matches:false,provider});
let proxy,child;const counts={requests:0,changed:[],keywords:[],factions:[]};let delay=false;
try{
 await seedFactions(app.service.store);const address=await app.listen(),base=`http://127.0.0.1:${address.port}`;
 const session=async name=>{const res=await fetch(base+'/v1/sessions',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({invite_code:'catalog-test-invite-1234567890',display_name:name})});return res.json();};
 const author=await session('卡库作者'),viewer=await session('本地玩家');
 const definition=name=>({schema_version:'1.0.0',ruleset_version:'frontline-1',name,faction_id:FACTION_ID,flavor_text:'',kind:'unit',unit_class:'infantry',cost:2,operation_cost:1,attack:2,health:3,keywords:[],play_target:null,abilities:[],tokens:[],appearance:{emblem:'infantry'}});
 const ids=Array.from({length:33},()=>randomUUID());
 const make=(state,index,revision=1)=>({card_id:ids[index],revision,...compileCard({...definition(`缓存卡${String(index).padStart(2,'0')}`),attack:revision+1},state.keywords),owner_id:author.owner_id,created_at:'2026-09-26T00:00:00Z'});
 await app.service.store.transaction(state=>{for(let i=0;i<32;i++)state.cards[ids[i]]=[make(state,i)];});
 proxy=createServer(async(req,res)=>{
  try{
   if(req.url==='/test/change'){
    await app.service.store.transaction(state=>{state.cards[ids[0]].push(make(state,0,2));state.cards[ids[32]]=[make(state,32)];state.content_lifecycle.cards[ids[1]]={archived:true};state.factions[FACTION_ID].name='已更新阵营';state.factions[FACTION_ID].revision++;});
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify({ok:true,first:ids[0],archived:ids[1],removed:ids[2]}));return;
   }
   if(req.url==='/test/delete'){
    await app.service.store.transaction(state=>{delete state.cards[ids[2]];state.content_lifecycle.cards[ids[2]]={deleted:true};state.content_lifecycle.cards[ids[1]]={archived:false};});
    res.setHeader('Content-Type','application/json');res.end('{"ok":true}');return;
   }
   if(req.url==='/test/stats'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify(counts));return;}
   if(req.url==='/test/series'){
    await app.service.store.transaction(state=>{state.card_series.names['2']='都市纪事';state.card_series.names['3']='新篇章';state.card_series.current=3;state.card_series.revision++;});
    res.setHeader('Content-Type','application/json');res.end('{"ok":true}');return;
   }
   if(req.url==='/test/delay'){delay=true;res.setHeader('Content-Type','application/json');res.end('{"ok":true}');return;}
   let bytes=[];for await(const c of req)bytes.push(c);const body=Buffer.concat(bytes);
   const response=await fetch(base+req.url,{method:req.method,headers:{'Content-Type':'application/json',...(req.headers.authorization?{Authorization:req.headers.authorization}:{})},...(body.length?{body}: {})});
   const result=await response.json();
   if(req.url==='/v1/catalog/updates'){counts.requests++;counts.changed.push(result.cards?.length??-1);counts.keywords.push(result.keywords?.length??0);counts.factions.push(result.factions?.length??0);if(delay)await new Promise(r=>setTimeout(r,350));}
   res.writeHead(response.status,{'Content-Type':'application/json'});res.end(JSON.stringify(result));
  }catch(e){res.writeHead(500,{'Content-Type':'application/json'});res.end(JSON.stringify({error:{message:e.message}}));}
 });
 await new Promise(resolve=>proxy.listen(0,'127.0.0.1',resolve));
 child=spawn(process.env.GODOT_BIN||'D:/工程/GT/Godot_v4.7-stable_win64.exe',['--headless','--path',root,'--script','res://tests/test_catalog_cache.gd'],{windowsHide:true,stdio:'inherit',env:{...process.env,FRONTLINE_PROFILE_PATH:join(dir,'profile.json'),CACHE_TEST_URL:`http://127.0.0.1:${proxy.address().port}`,CACHE_TEST_TOKEN:viewer.access_token,CACHE_TEST_OWNER:viewer.owner_id}});
 const timer=setTimeout(()=>child.kill(),90000);const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',resolve);});clearTimeout(timer);process.exitCode=code===0?0:1;
 console.log('CATALOG_HTTP_COUNTS',JSON.stringify(counts));
}finally{if(proxy)await new Promise(resolve=>proxy.close(resolve));await app.close();await rm(dir,{recursive:true,force:true});}
