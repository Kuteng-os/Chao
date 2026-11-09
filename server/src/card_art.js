import {ImageWorkers} from './image_workers.js';
import {createHash, randomUUID} from 'node:crypto';
import {mkdir, readFile, writeFile, rename, unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {fail} from './codec.js';
import {fields} from './service.js';

const LIMIT = 2 * 1024 * 1024;
export const artId = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
export function selectArt(state, owner, id) {
  if (id === null) return null;
  const asset = artId(id) ? state.card_art[id] : null;
  const published = Object.values(state.cards).some(versions => versions.some(c => (c.art?.id === id || Object.values(c.token_art??{}).some(a=>a.id===id) || [c.definition,...(c.definition.tokens??[])].some(d=>d.media?.background===id)))) || Object.values(state.factions||{}).some(f=>f.icon_id===id||f.background_id===id);
  if (!asset || (!asset.owners.includes(owner) && !published)) fail('INVALID_ART', '卡面不存在，请重新上传。', 422);
  return {id, width: asset.width, height: asset.height};
}
// Art is revisioned presentation metadata, separate from executable definitions.
export function selectTokenArt(state, owner, ids, tokens=[], previous={}) {
  const names=new Set(tokens.map(t=>t.token_id));
  if(ids===undefined)return Object.fromEntries(Object.entries(previous??{}).filter(([key])=>names.has(key)).map(([key,value])=>[key,structuredClone(value)]));
  if(!ids||typeof ids!=='object'||Array.isArray(ids)||Object.keys(ids).length>12)fail('INVALID_ART','衍生卡卡面格式无效。',422);
  return Object.fromEntries(Object.entries(ids).map(([key,id])=>{
    if(!names.has(key)||!artId(id))fail('INVALID_ART','衍生卡卡面引用无效，请重新选择卡面。',422);
    return [key,selectArt(state,owner,id)];
  }));
}
export function tokenArtIds(record) {
  return Object.fromEntries(Object.entries(record.token_art??{}).filter(([,a])=>artId(a?.id)).map(([key,a])=>[key,a.id]));
}
export class CardArt {
  constructor(store,decoder=new ImageWorkers()) { this.store = store; this.rates = new Map(); this.decoder=decoder; }
  async upload(owner, body) {
    fields(body, ['png_base64']);
    const recent = (this.rates.get(owner) || []).filter(t => Date.now() - t < 60000);
    if (recent.length >= 10) fail('RATE_LIMITED', '卡面上传过于频繁，请稍后重试。', 429);
    this.rates.set(owner, [...recent, Date.now()]);
    if (typeof body.png_base64 !== 'string' || body.png_base64.length > Math.ceil(LIMIT / 3) * 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(body.png_base64)) fail('INVALID_ART', '卡面文件无效或超过 2 MiB。', 422);
    const input = Buffer.from(body.png_base64, 'base64');
    if (input.length < 33 || input.length > LIMIT || input.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a' || input.toString('ascii',12,16) !== 'IHDR' || input.readUInt32BE(8) !== 13) fail('INVALID_ART', '卡面必须是有效 PNG 图片。', 422);
    const width = input.readUInt32BE(16), height = input.readUInt32BE(20);
    if (width < 1 || height < 1 || width > 1024 || height > 1024 || input[24] !== 8 || input[28] !== 0) fail('INVALID_ART', '卡面尺寸需在 1024 × 1024 以内，请通过网页重新上传。', 422);
    for (let offset = 33; offset < input.length;) {
      if (offset + 12 > input.length) fail('INVALID_ART', 'PNG 数据不完整。', 422);
      const length = input.readUInt32BE(offset), type = input.toString('ascii',offset+4,offset+8);
      if (type === 'IHDR' || length > input.length-offset-12) fail('INVALID_ART', 'PNG 数据无效。', 422);
      offset += length + 12;
      if (type === 'IEND') { if (offset !== input.length) fail('INVALID_ART', 'PNG 包含多余数据。', 422); break; }
    }
    // Decode pixels and re-encode: no metadata, animation or trailing payload survives.
    const png=Buffer.from((await this.decoder.decode('./card_art_decode.js',input,'INVALID_ART')).png);
    const id = createHash('sha256').update(png).digest('hex');
    await this.store.transaction(async state => {
      const owned = Object.values(state.card_art).filter(a => a.owners.includes(owner));
      if (!state.card_art[id]?.owners.includes(owner) && (owned.length >= 256 || owned.reduce((n,a) => n+a.bytes,0)+png.length > 128*1024*1024)) fail('RATE_LIMITED', '当前账号的卡面存储空间已满。', 429);
      const folder = join(this.store.directory, 'art');
      await mkdir(folder, {recursive:true});
      const temporary = join(folder, randomUUID()+'.tmp');
      try { await writeFile(temporary, png, {mode:0o600,flag:'wx'}); await rename(temporary, join(folder,id+'.png')); }
      finally { await unlink(temporary).catch(()=>{}); }
      state.card_art[id] ||= {width, height, bytes:png.length, owners:[]};
      if (!state.card_art[id].owners.includes(owner)) state.card_art[id].owners.push(owner);
    });
    return {art:{id, width, height}};
  }
  async image(id) {
    if (!artId(id) || !this.store.state.card_art[id]) fail('NOT_FOUND', '卡面不存在。', 404);
    try { return await readFile(join(this.store.directory, 'art', id+'.png')); }
    catch { fail('NOT_FOUND', '卡面文件暂不可用。', 404); }
  }
}
