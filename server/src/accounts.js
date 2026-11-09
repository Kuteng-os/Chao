import {randomBytes,randomUUID} from 'node:crypto';
import {fields} from './service.js';
import {fail} from './codec.js';
import {checkPassword,passwordHash,passwordMatches} from './passwords.js';
import {isAdmin,audit} from './account_roles.js';
export const ADMIN_NAMES=['Xiangwu','黑色的手套','Kuteng','毛巾长袍','ovo'];
export function usernameKey(value) {
  if(typeof value!=='string')fail('INVALID_REQUEST','请输入账号名称。',400);
  const name=value.normalize('NFKC').trim();
  if(!/^[\p{L}\p{N}_.-]{2,32}$/u.test(name))fail('INVALID_REQUEST','账号名称为 2～32 个中英文、数字、下划线、点或连字符。',400);
  return name.toLocaleLowerCase('en-US');
}
export class Accounts {
  constructor(auth,options={}){this.auth=auth;this.store=auth.store;this.registrationMode=options.registrationMode??process.env.ACCOUNT_REGISTRATION??'open';this.attempts=new Map();this.hashing=0;}
  options(){return {registration:this.registrationMode,password_min_length:10};}
  rate(address,key){const now=Date.now();for(const [id,list] of this.attempts){const recent=list.filter(t=>now-t<900000);if(recent.length)this.attempts.set(id,recent);else this.attempts.delete(id);}if(this.attempts.size>10000)fail('RATE_LIMITED','请求过多，请稍后重试。',429);for(const [id,max] of [[`ip:${address}`,60],[`login:${address}:${key}`,10]]){const list=this.attempts.get(id)||[];if(list.length>=max)fail('RATE_LIMITED','登录或注册过于频繁，请稍后重试。',429);list.push(now);this.attempts.set(id,list);}}
  async hashOperation(fn){if(this.hashing>=4)fail('RATE_LIMITED','登录服务繁忙，请稍后重试。',429);this.hashing++;try{return await fn();}finally{this.hashing--;}}
  revoke(state,owner){state.identities[owner].session_version=(state.identities[owner].session_version??0)+1;for(const session of Object.values(state.sessions))if(session.owner_id===owner)session.revoked_at=new Date().toISOString();for(const [key,item] of this.auth.browserCodes)if(item.owner===owner)this.auth.browserCodes.delete(key);}
  async register(body,address,linkOwner=null){
    fields(body,['username','password'],['invite_code']);const key=usernameKey(body.username);checkPassword(body.password);this.rate(address,key);
    if(['__proto__','constructor','prototype'].includes(key))fail('INVALID_REQUEST','请使用其他账号名称。',400);
    if(ADMIN_NAMES.some(n=>usernameKey(n)===key))fail('REVISION_CONFLICT','此账号名称已保留。',409);
    if(!linkOwner&&this.registrationMode==='invite'&&!this.auth.validInvite(body.invite_code))fail('UNAUTHORIZED','邀请码无效。',401);
    if(!linkOwner&&!['open','invite'].includes(this.registrationMode))fail('FORBIDDEN','注册暂未开放。',403);
    if(Object.hasOwn(this.store.state.accounts,key))fail('REVISION_CONFLICT','账号名称已被使用。',409);
    const password=await this.hashOperation(()=>passwordHash(body.password));
    return this.store.transaction(state=>{
      if(Object.hasOwn(state.accounts,key))fail('REVISION_CONFLICT','账号名称已被使用。',409);
      const owner=linkOwner??randomUUID(),existing=state.identities[owner];
      if(linkOwner&&(!existing||existing.account_key))fail('REVISION_CONFLICT','当前玩家已经绑定账号。',409);
      const username=body.username.normalize('NFKC').trim(),created_at=new Date().toISOString();
      state.accounts[key]={username,owner_id:owner,password,role:'player',must_change_password:false,created_at};
      state.identities[owner]={...(existing??{owner_id:owner,created_at}),display_name:username,account_key:key};
      if(linkOwner)this.revoke(state,owner);
      audit(state,owner,linkOwner?'account_link':'account_register',owner);
      return this.auth.session(state,owner,true);
    });
  }
  async login(body,address){fields(body,['username','password']);const key=usernameKey(body.username);this.rate(address,key);const account=Object.hasOwn(this.store.state.accounts,key)?this.store.state.accounts[key]:null;
    const checkedHash=account?.password?.hash;
    const matches=await this.hashOperation(()=>passwordMatches(body.password,account?.password));
    if(!matches)fail('UNAUTHORIZED','账号或密码不正确。',401);
    return this.store.transaction(state=>{const current=state.accounts[key];if(!current||current.password.hash!==checkedHash)fail('UNAUTHORIZED','密码已更改，请重新登录。',401);return this.auth.session(state,current.owner_id,true);});
  }
  async changePassword(owner,body){fields(body,['current_password','new_password']);checkPassword(body.new_password);const identity=this.store.state.identities[owner],account=this.store.state.accounts[identity?.account_key];if(!account)fail('INVALID_REQUEST','请先绑定账号。',400);const previousHash=account.password.hash;
    this.rate('password:'+owner,owner);
    const password=await this.hashOperation(async()=>{if(body.current_password===body.new_password)fail('INVALID_REQUEST','新密码不能与当前密码相同。',400);if(!await passwordMatches(body.current_password,account.password))fail('UNAUTHORIZED','当前密码不正确。',401);return passwordHash(body.new_password);});
    return this.store.transaction(state=>{const current=state.accounts[identity.account_key];if(current.password.hash!==previousHash)fail('REVISION_CONFLICT','密码已改变，请重新登录。',409);current.password=password;current.must_change_password=false;this.revoke(state,owner);audit(state,owner,'password_change',owner);return this.auth.session(state,owner,true);});
  }
  list(actor){if(!isAdmin(this.store.state,actor))fail('FORBIDDEN','需要管理员权限。',403);return {accounts:Object.values(this.store.state.accounts).map(a=>({owner_id:a.owner_id,username:a.username,role:a.role,must_change_password:a.must_change_password,created_at:a.created_at}))};}
  async resetPassword(actor,body){
    fields(body,['owner_id']);
    if(!isAdmin(this.store.state,actor))fail('FORBIDDEN','需要管理员权限。',403);
    if(typeof body.owner_id!=='string'||!Object.hasOwn(this.store.state.identities,body.owner_id))fail('NOT_FOUND','账号不存在。',404);
    const key=this.store.state.identities[body.owner_id].account_key;
    if(!key||!Object.hasOwn(this.store.state.accounts,key))fail('NOT_FOUND','该玩家尚未绑定账号。',404);
    if(body.owner_id===actor)fail('INVALID_REQUEST','请使用修改密码功能。',400);
    this.rate('reset:'+actor,actor);
    const temporary_password=randomBytes(18).toString('base64url');
    const password=await this.hashOperation(()=>passwordHash(temporary_password));
    return this.store.transaction(state=>{
      if(!isAdmin(state,actor))fail('FORBIDDEN','需要管理员权限。',403);
      const account=state.accounts[key];account.password=password;account.must_change_password=true;
      this.revoke(state,body.owner_id);audit(state,actor,'admin_password_reset',body.owner_id);
      return {username:account.username,temporary_password,must_change_password:true};
    });
  }
  async bootstrap(entries){
    if(!Array.isArray(entries)||entries.length!==ADMIN_NAMES.length||new Set(entries.map(e=>e.username)).size!==ADMIN_NAMES.length||entries.some(e=>!ADMIN_NAMES.includes(e.username)))throw new Error('Bootstrap must contain exactly the configured administrators.');
    const created=[];
    for(const item of entries){const key=usernameKey(item.username),existing=this.store.state.accounts[key];if(existing){if(existing.role!=='admin')throw new Error('Reserved administrator name belongs to an existing player.');continue;}const password=await passwordHash(item.password);await this.store.transaction(state=>{if(Object.hasOwn(state.accounts,key))fail('REVISION_CONFLICT','管理员账号已存在。',409);const owner=randomUUID(),created_at=new Date().toISOString();state.accounts[key]={username:item.username,owner_id:owner,password,role:'admin',must_change_password:true,created_at};state.identities[owner]={owner_id:owner,display_name:item.username,account_key:key,created_at};audit(state,'bootstrap','admin_create',owner);});created.push(item.username);}
    return {created};
  }
}
