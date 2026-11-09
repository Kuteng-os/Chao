import {parentPort,workerData} from 'node:worker_threads';
import {PNG} from 'pngjs';
import gifuct from 'gifuct-js';
import {inspectPNG} from './png_guard.js';

// Runs outside the HTTP loop. Both compressed input and decoded work are bounded.
export function decodeEmote(input) {
  input=Buffer.from(input);
  if(input.length<10||input.length>4*1024*1024)throw Error('表情需小于 4 MiB。');
  let width,height,frames,gif;
  const isGIF=/^GIF8[79]a$/.test(input.toString('ascii',0,6));
  if(isGIF){width=input.readUInt16LE(6);height=input.readUInt16LE(8);}
  else if(input.subarray(0,8).toString('hex')==='89504e470d0a1a0a'&&input.length>=33){({width,height}=inspectPNG(input));}
  else throw Error('请选择 GIF 或 PNG 图片。');
  if(width<1||height<1||width>1024||height>1024)throw Error('表情尺寸不能超过 1024 × 1024。');
  if(isGIF){
    gif=gifuct.parseGIF(input);frames=gif.frames.filter(f=>f.image);
    if(!frames.length||frames.length>120||frames.length*width*height>32*1024*1024)throw Error('动画最多 120 帧，较大图片请先缩小尺寸。');
    for(const f of frames){const d=f.image.descriptor;if(d.width<1||d.height<1||d.left+d.width>width||d.top+d.height>height)throw Error('GIF 帧区域无效。');}
  }else frames=[null];
  const ratio=Math.min(1,160/Math.max(width,height)),fw=Math.max(1,Math.round(width*ratio)),fh=Math.max(1,Math.round(height*ratio));
  const columns=Math.min(8,frames.length),rows=Math.ceil(frames.length/columns),aw=fw*columns,ah=fh*rows;
  const atlas=Buffer.alloc(aw*ah*4),canvas=Buffer.alloc(width*height*4),durations=[];
  for(let i=0;i<frames.length;i++){
    let saved,frame;
    if(isGIF){
      frame=gifuct.decompressFrame(frames[i],gif.gct,true);
      if(frame.disposalType===3)saved=Buffer.from(canvas);
      const d=frame.dims;
      for(let y=0;y<d.height;y++)for(let x=0;x<d.width;x++){
        const s=(y*d.width+x)*4,t=((y+d.top)*width+x+d.left)*4;
        if(frame.patch[s+3])canvas.set(frame.patch.subarray(s,s+4),t);
      }
      durations.push(Math.max(20,Math.min(10000,frame.delay||100)));
    }else {const png=PNG.sync.read(input,{checkCRC:true});canvas.set(png.data);durations.push(1000);}
    for(let y=0;y<fh;y++)for(let x=0;x<fw;x++){
      const s=(Math.min(height-1,Math.floor((y+.5)/ratio))*width+Math.min(width-1,Math.floor((x+.5)/ratio)))*4;
      const t=((Math.floor(i/columns)*fh+y)*aw+(i%columns)*fw+x)*4;
      canvas.copy(atlas,t,s,s+4);
    }
    if(isGIF&&frame.disposalType===2){const d=frame.dims;for(let y=0;y<d.height;y++)canvas.fill(0,((y+d.top)*width+d.left)*4,((y+d.top)*width+d.left+d.width)*4);}
    if(saved)canvas.set(saved);
  }
  return {png:PNG.sync.write({width:aw,height:ah,data:atlas},{colorType:6}),frame_width:fw,frame_height:fh,columns,durations};
}
if(parentPort){try{parentPort.postMessage({ok:true,...decodeEmote(workerData)});}catch(error){parentPort.postMessage({ok:false,error:error.message});}}
