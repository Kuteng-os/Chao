import {ApiError, fail, normalize, strictParse} from './codec.js';

// Reservations cover reading AND processing, so queued store writes cannot keep
// an unlimited number of large decoded bodies alive after their sockets finish.
export class RequestBudget {
  constructor({maxRequests=64, maxPerOwner=8, maxBytes=64*1024*1024}={}) {
    Object.assign(this,{maxRequests,maxPerOwner,maxBytes});
    this.requests=0; this.bytes=0; this.owners=new Map();
  }
  acquire(owner,bytes) {
    const count=this.owners.get(owner)??0;
    if(this.requests>=this.maxRequests||count>=this.maxPerOwner||this.bytes+bytes>this.maxBytes)
      fail('RATE_LIMITED','服务器正在处理其他请求，请稍后重试。',429);
    this.requests++;this.bytes+=bytes;this.owners.set(owner,count+1);
    let released=false;
    return ()=>{if(released)return;released=true;this.requests--;this.bytes-=bytes;
      const remaining=this.owners.get(owner)-1;
      if(remaining)this.owners.set(owner,remaining);else this.owners.delete(owner);
    };
  }
}

export function closeUnreadRequest(req,res) {
  if(req.complete||req.destroyed)return;
  res.shouldKeepAlive=false;if(!res.headersSent)res.setHeader('Connection','close');
  // Drain in-flight bytes without retaining them so the peer receives the error
  // response instead of an immediate TCP reset. Never wait for EOF to respond.
  req.resume();
  const timer=setTimeout(()=>req.destroy(),1000);timer.unref();
  req.once('close',()=>clearTimeout(timer));
}

export function readJSONBody(req,maxBytes,timeoutMs=15000) {
  if(Number(req.headers['content-length'])>maxBytes)
    return Promise.reject(new ApiError('INPUT_TOO_LONG',`请求超过 ${maxBytes/1024} KiB。`,413));
  return new Promise((resolve,reject)=>{
    let size=0,done=false;const chunks=[];
    const finish=(error,value)=>{
      if(done)return;done=true;clearTimeout(timer);
      req.off('data',data);req.off('end',end);req.off('aborted',abort);req.off('error',abort);
      if(error){chunks.length=0;req.pause();reject(error);}else resolve(value);
    };
    const data=chunk=>{size+=chunk.length;
      if(size>maxBytes)return finish(new ApiError('INPUT_TOO_LONG',`请求超过 ${maxBytes/1024} KiB。`,413));
      chunks.push(chunk);
    };
    const abort=()=>finish(new ApiError('INVALID_REQUEST','请求已中断，请重试。',400));
    const end=()=>{try{
      const body=normalize(strictParse(Buffer.concat(chunks,size),maxBytes));
      if(!body||typeof body!=='object'||Array.isArray(body))fail('INVALID_REQUEST','请求必须为 JSON 对象。',400);
      finish(null,{body,size});
    }catch(error){finish(error);}};
    const timer=setTimeout(()=>finish(new ApiError('REQUEST_TIMEOUT','请求上传超时，请重试。',408)),timeoutMs);
    timer.unref();req.on('data',data);req.once('end',end);req.once('aborted',abort);req.once('error',abort);
    if(req.aborted||req.destroyed)abort();
  });
}
