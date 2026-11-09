import {createHash, randomBytes, randomUUID, timingSafeEqual} from 'node:crypto';
import {fail} from './codec.js';
import {fields} from './service.js';
import {Accounts} from './accounts.js';

const digest = value => createHash('sha256').update(value, 'utf8').digest('hex');
const invalidName = /[\u0000-\u001f\u007f-\u009f]/u;

/** Central API identities are application identities, never operating-system users. */
export class CloudAuth {
  constructor(store, inviteToken, options = {}) {
    if (typeof inviteToken !== 'string' || inviteToken.length < 24) throw new Error('CENTRAL_MODE requires REGISTRATION_INVITE_TOKEN with at least 24 characters.');
    this.store = store;
    this.inviteDigest = Buffer.from(digest(inviteToken), 'hex');
    this.registrationLimit = options.registrationLimit ?? 10;
    this.registrationGlobalLimit = options.registrationGlobalLimit ?? 1000;
    this.registrationWindowMs = options.registrationWindowMs ?? 900000;
    this.browserCodes = new Map();
    this.accounts = new Accounts(this,options);
  }

  validInvite(value){return typeof value==='string'&&value.length<=1024&&timingSafeEqual(Buffer.from(digest(value),'hex'),this.inviteDigest);}
  identity(state, owner){const identity=state.identities[owner],account=state.accounts?.[identity?.account_key];return {owner_id:owner,display_name:identity.display_name,avatar:identity.avatar||"commander",avatar_color:identity.avatar_color||"#c5a36b",bio:identity.bio||"",created_at:identity.created_at,...(account?{username:account.username,role:account.role,must_change_password:account.must_change_password}:{})};}
  session(state,owner,expiring=false){const access_token=randomBytes(32).toString('base64url'),token_hash=digest(access_token),created_at=new Date().toISOString();state.sessions[token_hash]={token_hash,owner_id:owner,created_at,...(expiring?{expires_at:new Date(Date.now()+30*86400000).toISOString()}:{})};return {access_token,token_type:'Bearer',...this.identity(state,owner)};}
  async logout(authorization){await this.store.transaction(state=>{const session=state.sessions[digest(authorization.slice(7))];if(session){session.revoked_at=new Date().toISOString();for(const [key,item] of this.browserCodes)if(item.owner===session.owner_id)this.browserCodes.delete(key);}});return {ok:true};}

  browserSession(owner) {
    const now = Date.now();
    for (const [key, item] of this.browserCodes) if (item.expires <= now || item.owner === owner) this.browserCodes.delete(key);
    if (this.browserCodes.size >= 1000) fail('RATE_LIMITED', '请稍后再打开网页工坊。', 429);
    const code = randomBytes(32).toString('base64url');
    this.browserCodes.set(digest(code), {owner, expires: now + 120000, session_version:this.store.state.identities[owner]?.session_version??0});
    return {code, expires_in: 120};
  }

  async exchangeBrowserSession(body) {
    fields(body, ['code']);
    if (typeof body.code !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(body.code)) fail('UNAUTHORIZED', '网页登录链接无效，请从游戏重新打开。', 401);
    const key = digest(body.code), item = this.browserCodes.get(key);
    this.browserCodes.delete(key); // Consume before awaiting; concurrent exchanges cannot replay it.
    if (!item || item.expires <= Date.now()) fail('UNAUTHORIZED', '网页登录链接已使用或过期，请从游戏重新打开。', 401);
    return this.store.transaction(state => {
      const identity = state.identities[item.owner];
      if (!identity || (identity.session_version??0)!==item.session_version) fail('UNAUTHORIZED', '登录链接已失效，请重新登录。', 401);
      return this.session(state,item.owner,true);
    });
  }

  authenticate(authorization) {
    if (typeof authorization !== 'string' || !/^Bearer [A-Za-z0-9_-]{43}$/.test(authorization)) fail('UNAUTHORIZED', '请先登录账号。', 401);
    const record = this.store.state.sessions[digest(authorization.slice(7))];
    const identity = record && !record.revoked_at && (!record.expires_at||Date.parse(record.expires_at)>Date.now()) && this.store.state.identities[record.owner_id];
    if (!identity) fail('UNAUTHORIZED', '玩家令牌无效，请重新登录。', 401);
    return this.identity(this.store.state,identity.owner_id);
  }

  async register(body, remoteAddress) {
    fields(body, ['invite_code', 'display_name']);
    if (typeof body.invite_code !== 'string' || body.invite_code.length > 1024) fail('INVALID_REQUEST', '邀请码格式无效。', 400);
    if (typeof body.display_name !== 'string' || [...body.display_name.trim()].length < 1 || [...body.display_name].length > 32 || invalidName.test(body.display_name)) fail('INVALID_REQUEST', '玩家名称需为 1 至 32 个纯文本字符。', 400);
    const accepted = timingSafeEqual(Buffer.from(digest(body.invite_code), 'hex'), this.inviteDigest);
    const addressKey = digest(String(remoteAddress || 'unknown'));
    const result = await this.store.transaction(state => {
      const now = Date.now(), oldest = now - this.registrationWindowMs;
      for (const [key, attempts] of Object.entries(state.registration_limits)) {
        const recent = attempts.filter(time => time > oldest);
        if (recent.length) state.registration_limits[key] = recent;
        else delete state.registration_limits[key];
      }
      const attempts = state.registration_limits[addressKey] ||= [];
      const globalCount = Object.values(state.registration_limits).reduce((total, entries) => total + entries.length, 0);
      if (attempts.length >= this.registrationLimit || globalCount >= this.registrationGlobalLimit) fail('RATE_LIMITED', '登录尝试过于频繁，请稍后再试。', 429);
      attempts.push(now);
      if (!accepted) return null;
      const owner_id = randomUUID(), access_token = randomBytes(32).toString('base64url');
      const token_hash = digest(access_token), created_at = new Date(now).toISOString();
      const identity = {owner_id, display_name: body.display_name.trim(), created_at};
      state.identities[owner_id] = identity;
      state.sessions[token_hash] = {token_hash, owner_id, created_at};
      // The cleartext token is returned once and is never included in persistent state.
      return {access_token, token_type: 'Bearer', owner_id, display_name: identity.display_name};
    });
    if (!result) fail('UNAUTHORIZED', '邀请码无效。', 401);
    return result;
  }
}
