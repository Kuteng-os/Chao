import {createHash,randomUUID} from 'node:crypto';
import {mkdir,readFile,writeFile,rename,unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {fail} from './codec.js';
import {selectArt} from './card_art.js';

const LIMIT=16*1024*1024;
export function inspectWav(bytes){
  // Only canonical PCM is accepted. The web editor decodes other formats first.
  if(bytes.length<46||bytes.length>LIMIT||bytes.toString('ascii',0,4)!=='RIFF'||bytes.readUInt32LE(4)!==bytes.length-8||bytes.toString('ascii',8,12)!=='WAVE'||bytes.toString('ascii',12,16)!=='fmt '||bytes.readUInt32LE(16)!==16||bytes.readUInt16LE(20)!==1||bytes.readUInt16LE(22)!==1||bytes.readUInt32LE(24)!==22050||bytes.readUInt32LE(28)!==44100||bytes.readUInt16LE(32)!==2||bytes.readUInt16LE(34)!==16||bytes.toString('ascii',36,40)!=='data'||bytes.readUInt32LE(40)!==bytes.length-44||bytes.length%2)fail('INVALID_MEDIA','音频无效，请通过网页重新上传。',422);
  return (bytes.length-44)/44100;
}
function published(state,id){return Object.values(state.cards).some(v=>v.some(c=>[c.definition,...c.definition.tokens].some(d=>d.media?.music===id||Object.values(d.media?.sounds??{}).includes(id))));}
export function validateMedia(state,owner,definition){
  for(const token of definition.tokens??[])validateMedia(state,owner,token);
  const media=definition.media;if(!media)return;
  if(media.background)selectArt(state,owner,media.background);
  for(const [slot,id] of [...Object.entries(media.sounds??{}),...(media.music?[['music',media.music]]:[])]){
    const asset=state.sound_assets?.[id];
    if(!asset||(!asset.owners.includes(owner)&&!published(state,id)))fail('INVALID_MEDIA','音频不存在，请重新上传。',422);
    if(asset.duration>(slot==='music'?300:12))fail('INVALID_MEDIA','卡牌音效最多 12 秒，场地音乐最多 300 秒。',422);
  }
}
export class CardMedia{
  constructor(store){this.store=store;this.rates=new Map();}
  async upload(owner,body){
    if(!body||Object.keys(body).some(k=>!['wav_base64','kind'].includes(k))||!['sound','music'].includes(body.kind)||typeof body.wav_base64!=='string'||body.wav_base64.length>Math.ceil(LIMIT/3)*4||!/^[A-Za-z0-9+/]+={0,2}$/.test(body.wav_base64))fail('INVALID_MEDIA','音频上传内容无效。',422);
    const recent=(this.rates.get(owner)||[]).filter(t=>Date.now()-t<60000);
    if(recent.length>=12)fail('RATE_LIMITED','音频上传过于频繁，请稍后重试。',429);
    this.rates.set(owner,[...recent,Date.now()]);
    const bytes=Buffer.from(body.wav_base64,'base64'),duration=inspectWav(bytes);
    if(duration>(body.kind==='music'?300:12))fail('INVALID_MEDIA','卡牌音效最多 12 秒，场地音乐最多 300 秒。',422);
    const id=createHash('sha256').update(bytes).digest('hex');
    await this.store.transaction(async state=>{
      state.sound_assets??={};const owned=Object.values(state.sound_assets).filter(a=>a.owners.includes(owner));
      if(!state.sound_assets[id]?.owners.includes(owner)&&(owned.length>=512||owned.reduce((n,a)=>n+a.bytes,0)+bytes.length>256*1024*1024))fail('RATE_LIMITED','当前账号音频存储空间已满。',429);
      const folder=join(this.store.directory,'sounds');await mkdir(folder,{recursive:true});const temp=join(folder,randomUUID()+'.tmp');
      try{await writeFile(temp,bytes,{mode:0o600,flag:'wx'});await rename(temp,join(folder,id+'.wav'));}finally{await unlink(temp).catch(()=>{});}
      state.sound_assets[id]??={bytes:bytes.length,duration,owners:[]};if(!state.sound_assets[id].owners.includes(owner))state.sound_assets[id].owners.push(owner);
    });return {asset:{id,duration,bytes:bytes.length}};
  }
  async audio(id){if(!/^[0-9a-f]{64}$/.test(id)||!this.store.state.sound_assets?.[id])fail('NOT_FOUND','音频不存在。',404);try{return await readFile(join(this.store.directory,'sounds',id+'.wav'));}catch{fail('NOT_FOUND','音频暂不可用。',404);}}
}
