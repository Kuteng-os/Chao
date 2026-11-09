import {archived} from './content_lifecycle.js';
import {randomUUID} from 'node:crypto';
import {fail} from './codec.js';
import {fields} from './service.js';
import {selectArt} from './card_art.js';
import {authorFor} from './authorship.js';
import {isAdmin} from './account_roles.js';
import {FACTION_CATEGORIES} from './deck_rules.js';

export function requireCardFaction(definition, factions) {
  if(!definition.faction_id)return null;
  const faction = factions?.[definition.faction_id];
  if (!faction) fail('FACTION_REQUIRED', '请先创建阵营，再为卡牌选择已登记阵营。', 422);
  return faction;
}
export class Factions {
  constructor(service) { this.service=service; this.store=service.store; }
  public(entry, owner, state=this.store.state) {
    return {category:entry.category??'normal',archived:archived(state,"factions",entry.faction_id),faction_id:entry.faction_id, revision:entry.revision, name:entry.name, role:entry.role, color:entry.color, icon_id:entry.icon_id, background_id:entry.background_id??null, author:authorFor(state,entry.owner_id), can_edit:entry.owner_id===owner||isAdmin(state,owner)};
  }
  list(owner=null) { return {factions:Object.values(this.store.state.factions).map(f=>this.public(f,owner)).sort((a,b)=>a.name.localeCompare(b.name,'zh'))}; }
  save(owner, body, id=null) {
    fields(body,['request_id','name','color','icon_id',...(id?['base_revision']:['role'])],['background_id','category']);
    if(Object.hasOwn(body,'category')&&!FACTION_CATEGORIES.includes(body.category))fail('INVALID_REQUEST','请选择大阵营、普通阵营或小阵营。',400);
    if (typeof body.name!=='string'||!body.name.trim()||[...body.name.trim()].length>64||/[\p{Cc}\p{Cf}]/u.test(body.name)) fail('INVALID_REQUEST','阵营名称需为 1 至 64 个字符。',400);
    if (typeof body.color!=='string'||!/^#[0-9a-fA-F]{6}$/.test(body.color)) fail('INVALID_REQUEST','请选择有效的阵营颜色。',400);
    if (!id&&!['major','ally'].includes(body.role)) fail('INVALID_REQUEST','阵营类别无效。',400);
    return this.service.idem(owner,`faction:${id||'new'}`,body,state=>{
      const previous=id?state.factions[id]:null;
      if (id&&(!previous||(previous.owner_id!==owner&&!isAdmin(state,owner)))) fail('NOT_FOUND','只能修改自己的阵营。',404);
      if (previous&&(!Number.isSafeInteger(body.base_revision)||body.base_revision!==previous.revision)) fail('REVISION_CONFLICT','阵营已更新，请刷新后重试。',409);
      const name=body.name.trim();
      if (Object.values(state.factions).some(f=>f.faction_id!==id&&f.name.normalize('NFC').toLowerCase()===name.normalize('NFC').toLowerCase())) fail('FACTION_NAME_CONFLICT','这个阵营名称已经登记。',409);
      if (!previous&&Object.values(state.factions).filter(f=>f.owner_id===owner).length>=100) fail('RATE_LIMITED','每个账号最多创建 100 个阵营。',429);
      const art=selectArt(state,owner,body.icon_id);
      const background=Object.hasOwn(body,'background_id')?selectArt(state,owner,body.background_id):null;
      const entry={faction_id:id||randomUUID(),revision:(previous?.revision||0)+1,name,color:body.color.toLowerCase(),icon_id:art?.id??null,background_id:Object.hasOwn(body,'background_id')?(background?.id??null):(previous?.background_id??null),role:previous?.role??body.role,owner_id:previous?.owner_id??owner};
      state.factions[entry.faction_id]=entry;
      entry.category=body.category??previous?.category??'normal';
      return this.public(entry,owner,state);
    });
  }
}
