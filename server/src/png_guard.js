import {inflateSync} from 'node:zlib';

// pngjs accepts repeated IHDR chunks and its interlaced path inflates without a
// bound. Inspect the whole container and bound decompression before decoding.
export function inspectPNG(input) {
  const invalid=()=>{throw Error('PNG 数据无效或解压后超过尺寸限制。');};
  if(input.length<33||input.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'||input.readUInt32BE(8)!==13||input.toString('ascii',12,16)!=='IHDR')invalid();
  const width=input.readUInt32BE(16),height=input.readUInt32BE(20);
  if(width<1||height<1||width>1024||height>1024)throw Error('图片尺寸不能超过 1024 × 1024。');
  const depth=input[24],color=input[25],channels=new Map([[0,1],[2,3],[3,1],[4,2],[6,4]]).get(color);
  const validDepth=color===3?[1,2,4,8]:color===0?[1,2,4,8,16]:[8,16];
  if(!channels||!validDepth.includes(depth)||input[26]!==0||input[27]!==0||input[28]>1)invalid();
  const data=[];let ended=false;
  for(let offset=33;offset<input.length;){
    if(offset+12>input.length)invalid();
    const length=input.readUInt32BE(offset),type=input.toString('ascii',offset+4,offset+8);
    if(type==='IHDR'||length>input.length-offset-12)invalid();
    if(type==='IDAT')data.push(input.subarray(offset+8,offset+8+length));
    offset+=length+12;
    if(type==='IEND'){if(length!==0||offset!==input.length)invalid();ended=true;break;}
  }
  if(!ended||!data.length)invalid();
  // Adam7's seven passes have separate packed rows and filter bytes.
  const passes=input[28]===1?[[0,0,8,8],[4,0,8,8],[0,4,4,8],[2,0,4,4],[0,2,2,4],[1,0,2,2],[0,1,1,2]]:[[0,0,1,1]];
  let expected=0;
  for(const [x,y,dx,dy] of passes){const w=Math.max(0,Math.ceil((width-x)/dx)),h=Math.max(0,Math.ceil((height-y)/dy));if(w&&h)expected+=(1+Math.ceil(w*channels*depth/8))*h;}
  let raw;try{raw=inflateSync(Buffer.concat(data),{maxOutputLength:expected});}catch{invalid();}
  if(raw.length!==expected)invalid();
  return {width,height};
}
