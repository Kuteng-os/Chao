import {parentPort,workerData} from 'node:worker_threads';
import {PNG} from 'pngjs';
import {inspectPNG} from './png_guard.js';

try{
  const input=Buffer.from(workerData),{width,height}=inspectPNG(input);
  const decoded=PNG.sync.read(input,{checkCRC:true});
  const png=PNG.sync.write({width,height,data:decoded.data},{colorType:6,bitDepth:8});
  parentPort.postMessage({ok:true,png});
}catch{parentPort.postMessage({ok:false});}
