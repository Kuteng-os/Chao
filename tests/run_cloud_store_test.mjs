// Isolated real HTTP bridge: never uses the production profile, provider or .env.
import {createServer} from 'node:http';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {FACTION_ID, seedFactions} from '../server/test/faction_fixture.js';
import {createApp} from '../server/src/index.js';

const root = fileURLToPath(new URL('../', import.meta.url));
const dir = await mkdtemp(join(tmpdir(), 'chao-cloud-store-'));
const invite = 'isolated-test-invite-1234567890';
const provider = {configured:false, model:'isolated', async generate(){throw Error('No model calls in store tests');}};
const apps = [], proxies = [];
const definition = name => ({schema_version:'1.0.0',ruleset_version:'frontline-1',name,faction_id:FACTION_ID,flavor_text:'',kind:'unit',unit_class:'infantry',cost:2,operation_cost:1,attack:2,health:3,keywords:[],play_target:null,abilities:[],tokens:[],appearance:{emblem:'infantry'}});
try {
  for (let i=0;i<2;i++) {
    const app = await createApp({dataDir:join(dir,'server'+i),centralMode:true,inviteToken:invite,host:'127.0.0.1',port:0,matches:false,provider});
    await seedFactions(app.service.store);
    const address = await app.listen(); apps.push({app,base:`http://127.0.0.1:${address.port}`});
  }
  const call = async (path,body,token) => {
    const response=await fetch(apps[0].base+path,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
    const value=await response.json(); if(!response.ok) throw Error(JSON.stringify(value)); return value;
  };
  const seed = await call('/v1/sessions',{invite_code:invite,display_name:'Fixture publisher'});
  const draft1 = (await call('/v1/card-drafts',{request_id:randomUUID(),definition:definition('历史单位')},seed.access_token)).result;
  const old = await call('/v1/cards',{request_id:randomUUID(),draft_id:draft1.draft_id,draft_hash:draft1.draft_hash},seed.access_token);
  const draft2 = (await call('/v1/card-drafts',{request_id:randomUUID(),definition:{...definition('历史单位'),attack:4}},seed.access_token)).result;
  await call(`/v1/cards/${old.card_id}/revisions`,{request_id:randomUUID(),draft_id:draft2.draft_id,draft_hash:draft2.draft_hash,base_revision:1},seed.access_token);
  let dropped=false, syncIds=[], secondAuth=[];
  for (let i=0;i<2;i++) {
    const server=createServer(async(req,res)=>{
      try {
        if(i===1) secondAuth.push(req.headers.authorization||'');
        if(req.url==='/test-stats') { res.setHeader('content-type','application/json'); res.end(JSON.stringify({sync_ids:syncIds,second_auth:secondAuth,old_id:old.card_id})); return; }
        let bytes=[]; for await(const chunk of req) bytes.push(chunk); const body=Buffer.concat(bytes);
        if(i===0&&req.url==='/v1/card-sync') syncIds.push(JSON.parse(body).request_id);
        const upstream=await fetch(apps[i].base+req.url,{method:req.method,headers:{'content-type':'application/json',...(req.headers.authorization?{authorization:req.headers.authorization}:{})},...(body.length?{body}:{} )});
        const text=await upstream.text();
        if(i===0&&req.url==='/v1/card-sync'&&!dropped&&upstream.ok) {
          dropped=true; res.writeHead(503,{'content-type':'application/json'});res.end(JSON.stringify({error:{message:'Simulated acknowledgement lost after commit'}}));return;
        }
        res.writeHead(upstream.status,{'content-type':'application/json'});res.end(text);
      } catch(e) { res.writeHead(500);res.end(JSON.stringify({error:{message:e.message}})); }
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve)); proxies.push(server);
  }
  const godot=process.env.GODOT_BIN||'D:/工程/GT/Godot_v4.7-stable_win64.exe';
  const child=spawn(godot,['--headless','--path',root,'--script','tests/test_cloud_store.gd'],{cwd:root,windowsHide:true,stdio:'inherit',env:{...process.env,FRONTLINE_PROFILE_PATH:join(dir,'profile.json'),FRONTLINE_TEST_SERVER_URL:`http://127.0.0.1:${proxies[0].address().port}`,FRONTLINE_TEST_OTHER_URL:`http://127.0.0.1:${proxies[1].address().port}`,FRONTLINE_TEST_INVITE:invite}});
  const timeout=setTimeout(()=>child.kill(),90000);
  const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',resolve);});clearTimeout(timeout);
  process.exitCode=code===0?0:1;
} finally {
  for(const proxy of proxies) {proxy.closeAllConnections();await new Promise(r=>proxy.close(r));}
  for(const {app} of apps) await app.close();
  const target=resolve(dir); if(!target.startsWith(resolve(tmpdir())+'\\')&&!target.startsWith(resolve(tmpdir())+'/')) throw Error('Unsafe cleanup target');
  await rm(target,{recursive:true,force:true});
}
