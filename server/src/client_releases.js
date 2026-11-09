import {readFile,stat} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {join} from 'node:path';
import {fail} from './codec.js';

/** Releases are installed by the operator, never uploaded through player APIs. */
export class ClientReleases {
 constructor(directory){this.directory=directory;}
 async handle(req,res,path){
  if(req.method!=='GET'&&req.method!=='HEAD')return false;
  if(path==='/v1/client-release'){
   let bytes;try{bytes=await readFile(join(this.directory,'latest.json'));}catch{fail('NOT_FOUND','暂未发布客户端更新。',404);}
   res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-cache','Content-Length':bytes.length});res.end(req.method==='HEAD'?undefined:bytes);return true;
  }
  const m=/^\/v1\/client-files\/(Frontline-[A-Za-z0-9.-]+\.(?:pck|apk|exe|zip))$/.exec(path);if(!m)return false;
  const file=join(this.directory,m[1]);let info;try{info=await stat(file);}catch{fail('NOT_FOUND','更新文件不存在。',404);}if(!info.isFile())fail('NOT_FOUND','更新文件不存在。',404);
  let start=0,end=info.size-1,status=200;const headers={'Content-Type':m[1].endsWith('.apk')?'application/vnd.android.package-archive':'application/octet-stream','Accept-Ranges':'bytes','Cache-Control':'public, max-age=31536000, immutable','X-Content-Type-Options':'nosniff','Content-Disposition':`attachment; filename="${m[1]}"`};
  if(req.headers.range){const range=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range);if(!range||!Number.isSafeInteger(Number(range[1]))||Number(range[1])>=info.size){res.writeHead(416,{'Content-Range':`bytes */${info.size}`});res.end();return true;}start=Number(range[1]);end=range[2]?Math.min(Number(range[2]),end):end;if(!Number.isSafeInteger(end)||end<start){res.writeHead(416);res.end();return true;}status=206;headers['Content-Range']=`bytes ${start}-${end}/${info.size}`;}
  headers['Content-Length']=end-start+1;res.writeHead(status,headers);if(req.method==='HEAD')res.end();else{const stream=createReadStream(file,{start,end});stream.on('error',()=>res.destroy());res.on('close',()=>stream.destroy());stream.pipe(res);}return true;
 }
}
