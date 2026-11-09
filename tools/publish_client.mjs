// Build a signed cumulative resource patch manifest. Keep the private key outside releases.
// node tools/publish_client.mjs <release-folder> <private-key> <version> <integer-build> <notes-file>
import {readFile,writeFile,rename} from 'node:fs/promises';
import {createHash,sign,verify,createPublicKey} from 'node:crypto';
import {join} from 'node:path';
const [dir,keyFile,version,buildText,notesFile]=process.argv.slice(2),build=Number(buildText);
if(!dir||!keyFile||!/^\d+\.\d+\.\d+$/.test(version)||!Number.isSafeInteger(build)||build<800||!notesFile)throw Error('Provide release directory, signing key, semver, build >= 800 and notes file.');
const key=await readFile(keyFile);let previous;
try{
 const envelope=JSON.parse(await readFile(join(dir,'latest.json'),'utf8'));
 if(!verify('RSA-SHA256',Buffer.from(envelope.payload),createPublicKey(key),Buffer.from(envelope.signature,'base64')))throw Error('Previous release signature is invalid.');
 previous=JSON.parse(envelope.payload);
 if(build<=previous.build)throw Error('Build numbers must increase; published files must remain immutable.');
}catch(error){if(error.code!=='ENOENT')throw error;}
const minimumBase=Number(process.env.FRONTLINE_MINIMUM_BASE_BUILD||previous?.minimum_base_build||800);
if(!Number.isSafeInteger(minimumBase)||minimumBase<800||minimumBase>build)throw Error('Invalid minimum base build.');
const files={};for(const extension of ['pck','exe','apk']){
 let filename=`Frontline-${version}.${extension}`,data;
 try{data=await readFile(join(dir,filename));}
 catch(error){
  if(error.code!=='ENOENT'||extension==='pck'||!previous)throw error;
  const existing=previous.files[extension];
  if(!existing||!new RegExp('^/v1/client-files/Frontline-[A-Za-z0-9.-]+\\.'+extension+'$').test(existing.path))throw Error('Invalid previous installer path.');
  filename=existing.path.split('/').pop();data=await readFile(join(dir,filename));
  if(data.length!==existing.bytes||createHash('sha256').update(data).digest('hex')!==existing.sha256)throw Error('Previous installer was modified.');
 }
 files[extension]={path:'/v1/client-files/'+filename,bytes:data.length,sha256:createHash('sha256').update(data).digest('hex')};
}
const payload=JSON.stringify({schema:1,version,build,minimum_base_build:minimumBase,patch_abi:'frontline-4.7-1',published_at:new Date().toISOString(),notes:await readFile(notesFile,'utf8'),files});
const signature=sign('RSA-SHA256',Buffer.from(payload),key).toString('base64');
await writeFile(join(dir,'latest.json.tmp'),JSON.stringify({payload,signature}));
await rename(join(dir,'latest.json.tmp'),join(dir,'latest.json'));
console.log('Signed release',version,build,Object.fromEntries(Object.entries(files).map(([k,v])=>[k,v.bytes])));
