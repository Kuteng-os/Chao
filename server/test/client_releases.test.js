import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {createServer} from 'node:http';
import {generateKeyPairSync,verify} from 'node:crypto';
import {promisify} from 'node:util';
import {execFile} from 'node:child_process';
import {ClientReleases} from '../src/client_releases.js';
const run=promisify(execFile);

test('release downloads support exact byte ranges and never resolve arbitrary paths',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'frontline-release-test-'));
 await writeFile(join(dir,'latest.json'),'{}');await writeFile(join(dir,'Frontline-0.8.0.pck'),'0123456789');
 const releases=new ClientReleases(dir),server=createServer(async(req,res)=>{try{if(!await releases.handle(req,res,new URL(req.url,'http://local').pathname)){res.writeHead(404);res.end();}}catch{res.writeHead(404);res.end();}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
 t.after(async()=>{await new Promise(r=>server.close(r));await rm(dir,{recursive:true,force:true});});
 const partial=await fetch(base+'/v1/client-files/Frontline-0.8.0.pck',{headers:{Range:'bytes=2-5'}});assert.equal(partial.status,206);assert.equal(partial.headers.get('content-range'),'bytes 2-5/10');assert.equal(await partial.text(),'2345');
 assert.equal((await fetch(base+'/v1/client-files/Frontline-0.8.0.pck',{headers:{Range:'bytes=100-'}})).status,416);
 const head=await fetch(base+'/v1/client-files/Frontline-0.8.0.pck',{method:'HEAD'});assert.equal(head.headers.get('content-length'),'10');assert.equal(await head.text(),'');
 assert.equal((await fetch(base+'/v1/client-files/%2e%2e%2flatest.json')).status,404);
 assert.equal((await fetch(base+'/v1/client-files/Frontline-0.8.0.pck',{method:'PUT',body:'bad'})).status,404);
 assert.equal((await fetch(base+'/v1/client-release')).headers.get('cache-control'),'no-cache');
});

test('patch-only publishing reuses verified base installers and rejects rollback',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'frontline-publisher-test-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});const key=join(dir,'key.pem'),notes=join(dir,'notes.txt');
 await writeFile(key,privateKey.export({type:'pkcs8',format:'pem'}));await writeFile(notes,'Test release');
 for(const ext of ['pck','exe','apk'])await writeFile(join(dir,'Frontline-0.8.0.'+ext),'base '+ext);
 const publisher=resolve(import.meta.dirname,'../../tools/publish_client.mjs');
 await run(process.execPath,[publisher,dir,key,'0.8.0','800',notes]);
 await writeFile(join(dir,'Frontline-0.8.1.pck'),'patch only');
 await run(process.execPath,[publisher,dir,key,'0.8.1','801',notes]);
 const envelope=JSON.parse(await readFile(join(dir,'latest.json'),'utf8')),payload=JSON.parse(envelope.payload);
 assert(verify('RSA-SHA256',Buffer.from(envelope.payload),publicKey,Buffer.from(envelope.signature,'base64')));
 assert.equal(payload.files.pck.path,'/v1/client-files/Frontline-0.8.1.pck');assert.equal(payload.files.apk.path,'/v1/client-files/Frontline-0.8.0.apk');
 await assert.rejects(run(process.execPath,[publisher,dir,key,'0.8.0','800',notes]));
 assert.equal(await readFile(join(dir,'latest.json'),'utf8'),JSON.stringify(envelope));
});
