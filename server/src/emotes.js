import {ImageWorkers} from './image_workers.js';
import {createHash,randomUUID} from 'node:crypto';
import {mkdir,writeFile,readFile,rename,unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {fail} from './codec.js';
import {fields} from './service.js';
import {isAdmin} from './account_roles.js';
export const emoteId=v=>typeof v==='string'&&/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(v);
const validName=v=>typeof v==='string'&&v.trim().length>0&&[...v.trim()].length<=24&&!/[\x00-\x1f\x7f]/.test(v);
export const DEFAULT_EMOTE_SCALE=46;
export function emoteScale(value){if(value===undefined)return DEFAULT_EMOTE_SCALE;if(typeof value!=='number'||!Number.isSafeInteger(value)||value<25||value>200)fail('INVALID_EMOTE','表情倍率需为 0.25～2。',422);return value;}
export class Emotes{
  constructor(store,decoder=new ImageWorkers()){this.store=store;this.rates=new Map();this.decoder=decoder;}
  list(){return {emotes:Object.values(this.store.state.emotes??{}).filter(e=>!e.deleted).map(e=>({...e,author:this.store.state.identities?.[e.owner_id]?.display_name??'作者'}))};}
  loadout(owner){return {slots:(this.store.state.emote_loadouts?.[owner]??Array(8).fill('')).map(id=>this.store.state.emotes?.[id]&&!this.store.state.emotes[id].deleted?id:'')};}
  async save(owner,body){fields(body,['slots']);if(!Array.isArray(body.slots)||body.slots.length!==8||body.slots.some(id=>id!==''&&(!emoteId(id)||!this.store.state.emotes[id]||this.store.state.emotes[id].deleted)))fail('INVALID_EMOTE','请选择八个位置的表情，空位可以留空。',422);await this.store.transaction(s=>{s.emote_loadouts[owner]=body.slots;});return this.loadout(owner);}
  decode(input){return this.decoder.decode('./emote_decode.js',input,'INVALID_EMOTE');}
  async upload(owner,body){
    fields(body,['name','image_base64'],['scale_percent']);const scale_percent=emoteScale(body.scale_percent);
    if(!validName(body.name))fail('INVALID_EMOTE','表情名称需为 1～24 个字。',422);
    if(typeof body.image_base64!=='string'||body.image_base64.length>5592408||! /^[A-Za-z0-9+/]+={0,2}$/.test(body.image_base64))fail('INVALID_EMOTE','请选择小于 4 MiB 的 GIF 或 PNG。',422);
    const recent=(this.rates.get(owner)??[]).filter(t=>Date.now()-t<60000);
    if(recent.length>=5)fail('RATE_LIMITED','上传太快，请稍后重试。',429);this.rates.set(owner,[...recent,Date.now()]);
    const result=await this.decode(Buffer.from(body.image_base64,'base64')),png=Buffer.from(result.png),asset_id=createHash('sha256').update(png).digest('hex');
    const emote={emote_id:randomUUID(),owner_id:owner,name:body.name.trim(),scale_percent,asset_id,frame_width:result.frame_width,frame_height:result.frame_height,columns:result.columns,durations:result.durations,bytes:png.length,created_at:new Date().toISOString()};
    await this.store.transaction(async s=>{
      const owned=Object.values(s.emotes).filter(e=>e.owner_id===owner);
      if(owned.filter(e=>!e.deleted).length>=48||owned.length>=256||owned.reduce((n,e)=>n+e.bytes,0)+png.length>64*1024*1024||Object.keys(s.emotes).length>=4096)fail('RATE_LIMITED','表情库空间已满，请联系管理员。',429);
      const folder=join(this.store.directory,'emotes');await mkdir(folder,{recursive:true});const temp=join(folder,randomUUID()+'.tmp');
      try{await writeFile(temp,png,{flag:'wx',mode:0o600});await rename(temp,join(folder,asset_id+'.png'));}finally{await unlink(temp).catch(()=>{});}
      s.emotes[emote.emote_id]=emote;
    });return {emote};
  }
  async edit(owner,id,body,remove=false){
    fields(body,[],remove?[]:['name','scale_percent']);
    if(!remove&&!Object.keys(body).length)fail('INVALID_EMOTE','请填写要修改的名称或倍率。',422);
    if(Object.hasOwn(body,'name')&&!validName(body.name))fail('INVALID_EMOTE','名称需为 1～24 个字。',422);
    if(Object.hasOwn(body,'scale_percent'))emoteScale(body.scale_percent);
    return this.store.transaction(s=>{const e=s.emotes[id];if(!e||e.deleted)fail('NOT_FOUND','表情不存在。',404);if(e.owner_id!==owner&&!isAdmin(s,owner))fail('FORBIDDEN','只能修改自己上传的表情。',403);if(remove){e.deleted=true;for(const slots of Object.values(s.emote_loadouts))for(let i=0;i<8;i++)if(slots[i]===id)slots[i]='';}else{if(Object.hasOwn(body,'name'))e.name=body.name.trim();if(Object.hasOwn(body,'scale_percent'))e.scale_percent=body.scale_percent;}return {ok:true};});
  }
  async image(id){if(!/^[0-9a-f]{64}$/.test(id)||!Object.values(this.store.state.emotes??{}).some(e=>e.asset_id===id))fail('NOT_FOUND','表情不存在。',404);try{return await readFile(join(this.store.directory,'emotes',id+'.png'));}catch{fail('NOT_FOUND','表情文件暂不可用。',404);}}
}
