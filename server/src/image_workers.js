import {Worker} from 'node:worker_threads';
import {ApiError,fail} from './codec.js';

export class ImageWorkers {
  constructor(){this.tasks=new Map();this.closed=false;}
  decode(script,input,code){
    if(this.closed||this.tasks.size>=2)fail('RATE_LIMITED','正在处理其他图片，请稍后上传。',429);
    return new Promise((resolve,reject)=>{
      const worker=new Worker(new URL(script,import.meta.url),{workerData:input,resourceLimits:{maxOldGenerationSizeMb:128,maxYoungGenerationSizeMb:32}});
      let done=false;
      const finish=(error,value)=>{if(done)return;done=true;clearTimeout(timer);this.tasks.delete(worker);void worker.terminate();if(error)reject(error);else resolve(value);};
      const invalid=message=>new ApiError(code,message,422);
      const timer=setTimeout(()=>finish(invalid('图片处理超时，请缩小或更换图片。')),10000);
      this.tasks.set(worker,()=>finish(invalid('图片处理已停止，请重新上传。')));
      worker.once('message',m=>m.ok?finish(null,m):finish(invalid('图片损坏或格式不支持，请更换图片。')));
      worker.once('error',()=>finish(invalid('图片无法读取，请更换图片。')));
      worker.once('exit',()=>{if(!done)finish(invalid('图片处理失败。'));});
    });
  }
  close(){this.closed=true;for(const cancel of this.tasks.values())cancel();}
}
