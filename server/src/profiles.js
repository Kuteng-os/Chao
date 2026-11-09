import {fail} from './codec.js';
import {fields} from './service.js';
export const avatars=['commander','armor','wings','artillery','navy','recon'];
export class Profiles{
 constructor(auth,store){this.auth=auth;this.store=store;}
 async save(owner,body){fields(body,['display_name','avatar','avatar_color','bio']);
  if(typeof body.display_name!=='string'||[...body.display_name.trim()].length<1||[...body.display_name].length>32||/[\p{Cc}\p{Cf}]/u.test(body.display_name))fail('INVALID_REQUEST','昵称需为 1～32 个字符。',422);
  if(!avatars.includes(body.avatar)||typeof body.avatar_color!=='string'||!/^#[0-9a-f]{6}$/i.test(body.avatar_color))fail('INVALID_REQUEST','请选择头像与颜色。',422);
  if(typeof body.bio!=='string'||[...body.bio].length>160||/[\p{Cc}\p{Cf}]/u.test(body.bio))fail('INVALID_REQUEST','签名最多 160 个字符。',422);
  return this.store.transaction(state=>{const identity=state.identities[owner];if(!identity)fail('UNAUTHORIZED','请重新登录。',401);Object.assign(identity,{display_name:body.display_name.trim(),avatar:body.avatar,avatar_color:body.avatar_color.toLowerCase(),bio:body.bio.trim()});return this.auth.identity(state,owner);});
 }
}
