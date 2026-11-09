import {emoteId,emoteScale} from './emotes.js';
import {mainSin} from "./sins.js";
import {tokenArtIds} from './card_art.js';
import {headquartersFor,headquartersEnvelope} from './headquarters.js';
import {MatchArchive} from './match_archive.js';
import {ruleCapabilities} from './rule_capabilities.js';
import {DECK_SIZE,checkDeckCopies,deckFactions,deckComposition} from './deck_rules.js';
import {spawn} from 'node:child_process';
import {randomUUID, randomInt} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {ApiError, hash, fail} from './codec.js';

const clientVersion = build => [Math.floor(build/1000),Math.floor(build/100)%10,build%100].join(".");

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[0-9a-f]{64}$/;
const WORKER_LIMIT = 8 * 1024 * 1024;
const fields = (value, names) => {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length !== names.length || names.some(name => !Object.hasOwn(value, name))) fail('INVALID_REQUEST', '请求字段不正确。', 400);
};
const identifier = value => typeof value === 'string' && UUID.test(value);
const terminal = room => ['ended', 'aborted', 'closed'].includes(room.status);

// Supply OS runtime settings only. Provider keys and application credentials stay
// in the supervisor even when more secret environment variables are added later.
export function godotRuntimeEnvironment(source = process.env) {
  return Object.fromEntries(Object.entries(source).filter(([key]) => /^(PATH|HOME|USERPROFILE|APPDATA|LOCALAPPDATA|TEMP|TMP|TMPDIR|SYSTEMROOT|WINDIR|LANG|LC_ALL|XDG_[A-Z0-9_]+)$/i.test(key)));
}

/** A private Godot process is the only rules executor. Never use shell execution. */
export class GodotBattleWorker {
  constructor({godotBin, projectPath, timeoutMs = 12000}) {
    if (!godotBin) throw new ApiError('MATCH_SERVICE_UNAVAILABLE', '权威对局服务尚未配置。', 503);
    this.nextId = 1; this.pending = new Map(); this.buffer = ''; this.failed = null; this.timeoutMs = timeoutMs;
    this.child = spawn(godotBin, ['--headless', '--path', projectPath, '--script', 'res://scripts/server/battle_worker.gd'], {cwd: projectPath, env: godotRuntimeEnvironment(), stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true, shell: false});
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', chunk => this.receive(chunk));
    // Drain engine diagnostics; never expose private definitions or filesystem paths through HTTP.
    this.child.stderr.on('data', () => {});
    this.child.on('error', () => this.failure('权威规则进程无法启动。'));
    this.child.on('exit', () => this.failure('权威规则进程已退出。'));
    this.child.stdin.on('error', () => this.failure('权威规则进程连接已中断。'));
  }
  failure(message) {
    if (this.failed) return;
    this.failed = new ApiError('MATCH_SERVICE_UNAVAILABLE', message, 503);
    for (const item of this.pending.values()) { clearTimeout(item.timer); item.reject(this.failed); }
    this.pending.clear(); this.child.kill();
  }
  receive(chunk) {
    this.buffer += chunk;
    if (Buffer.byteLength(this.buffer) > WORKER_LIMIT) return this.failure('权威局面超过处理预算。');
    while (this.buffer.includes('\n')) {
      const split = this.buffer.indexOf('\n'), line = this.buffer.slice(0, split).trim(); this.buffer = this.buffer.slice(split + 1);
      // Godot prints a version banner before the script starts. Only JSON protocol lines are parsed.
      if (!line.startsWith('{')) continue;
      let message;
      try { message = JSON.parse(line); } catch { return this.failure('权威进程返回了无效结果。'); }
      const item = this.pending.get(message.id);
      if (!item) continue;
      clearTimeout(item.timer); this.pending.delete(message.id);
      if (message.ok !== true) item.reject(new ApiError(typeof message.error === 'string' ? message.error : 'INVALID_RULES', '服务器无法装载此牌组的冻结规则。', 422));
      else item.resolve(message.result);
    }
  }
  request(command) {
    if (this.failed) return Promise.reject(this.failed);
    if (this.pending.size >= 4) return Promise.reject(new ApiError('RATE_LIMITED', '权威进程繁忙。', 429));
    const id = this.nextId++, line = JSON.stringify({...command, id}) + '\n';
    if (Buffer.byteLength(line) > 4 * 1024 * 1024) return Promise.reject(new ApiError('INPUT_TOO_LONG', '冻结规则目录过大。', 413));
    return new Promise((resolveResult, reject) => {
      const timer = setTimeout(() => this.failure('权威进程处理超时。'), this.timeoutMs); timer.unref();
      this.pending.set(id, {resolve: resolveResult, reject, timer});
      // Godot's pipe reader requests a fixed byte block. Pad only with JSON
      // whitespace, preserving newline-delimited commands and UTF-8 boundaries.
      const padding = ' '.repeat((1024 - Buffer.byteLength(line) % 1024) % 1024);
      this.child.stdin.write(line + padding, 'utf8', error => { if (error) this.failure('权威进程连接已中断。'); });
    });
  }
  close() { this.failure('对局进程已关闭。'); }
}

export class CentralMatches {
  constructor({store, godotBin = process.env.GODOT_BIN, projectPath = process.env.GODOT_PROJECT_PATH || fileURLToPath(new URL('../..', import.meta.url)), maxRooms = 16, idleTimeoutMs = 300000, offlineAfterMs = 20000, disconnectGraceMs = 30000, bothOfflineGraceMs = 120000, retentionMs = 120000, openingRedraw = true, workerFactory} = {}) {
    this.openingRedraw = openingRedraw; this.store = store; this.godotBin = godotBin; this.projectPath = resolve(projectPath); this.maxRooms = Math.max(1, Math.min(64, Number(maxRooms) || 16));
    this.idleTimeoutMs = idleTimeoutMs; this.offlineAfterMs = offlineAfterMs; this.disconnectGraceMs = disconnectGraceMs; this.bothOfflineGraceMs = bothOfflineGraceMs; this.retentionMs = retentionMs;
    this.archive = store.directory ? new MatchArchive(store) : null;
    this.rooms = new Map(); this.players = new Map(); this.operations = new Map(); this.rates = new Map(); this.globalQueue = Promise.resolve(); this.globalPending=0; this.closed = false;
    this.workerFactory = workerFactory || (() => new GodotBattleWorker({godotBin: this.godotBin, projectPath: this.projectPath}));
    this.sweepTimer = setInterval(() => { void this.sweep(); }, 1000); this.sweepTimer.unref();
  }
  async handle({method, pathname, owner, body, clientBuild = 0}) {
    if (pathname !== '/v1/rooms' && !pathname.startsWith('/v1/rooms/')) return null;
    if (!owner || typeof owner !== 'string') fail('UNAUTHORIZED', '请先登录中央服务器。', 401);
    if (this.closed) fail('MATCH_SERVICE_UNAVAILABLE', '对局服务正在关闭。', 503);
    this.rate(owner);
    if (pathname === '/v1/rooms') {
      if (method === 'GET') return {status: 200, body: {rooms: [...this.rooms.values()].filter(room => ['waiting','active','suspended'].includes(room.status) || room.players.includes(owner) || room.spectators?.get(owner)?.active).map(room => this.summary(room, owner))}};
      if (method === 'POST') return {status: 201, body: await this.global(() => this.operation(owner, 'create', body, () => this.create(owner, body, clientBuild)))};
    }
    const match = /^\/v1\/rooms\/([0-9a-f-]{36}|\d{6})\/(join|state|actions|leave|emotes|watch|unwatch)$/.exec(pathname);
    if (!match) fail('NOT_FOUND', '房间接口不存在。', 404);
    const room = this.find(match[1]);
    if (match[2] === 'join' && method === 'POST') return {status: 200, body: await this.global(() => this.serial(room, () => this.operation(owner, `join:${room.id}`, body, () => this.join(room, owner, body, clientBuild))))};
    if (match[2] === 'watch' && method === 'POST') return {status:200,body:await this.serial(room,()=>this.watch(room,owner,body,clientBuild))};
    if (match[2] === 'unwatch' && method === 'POST') return {status:200,body:await this.serial(room,async()=>{
      fields(body,[]);
      const viewer=room.spectators?.get(owner);
      if(!viewer)fail('FORBIDDEN','你没有加入这场观战。',403);
      viewer.active=false;
      return {ok:true};
    })};
    const seat = room.players.indexOf(owner);
    if (seat < 0) {
      const viewer=room.spectators?.get(owner);
      if(match[2]!=='state'||method!=='GET'||!viewer?.active)fail('FORBIDDEN','观众只能查看已加入的对局，不能操作玩家。',403);
      return {status:200,body:await this.serial(room,async()=>{
        if(!viewer.active)fail('FORBIDDEN','你已退出观战。',403);
        this.checkSpectatorCapacity(room,viewer);
        viewer.lastSeen=Date.now();
        // Audience polling never updates either player's heartbeat or action clock.
        await this.reconcile(room);
        return this.spectatorSnapshot(room,viewer);
      })};
    }
    if (match[2] === 'state' && method === 'GET') {
      room.lastSeen[seat] = Date.now();
      return {status: 200, body: await this.serial(room, async () => { await this.reconcile(room); return this.snapshot(room, seat); })};
    }
    if(match[2]==='emotes'&&method==='POST')return {status:200,body:await this.serial(room,()=>this.emote(room,seat,body))};
    if (match[2] === 'actions' && method === 'POST') return {status: 200, body: await this.serial(room, () => this.action(room, owner, seat, body))};
    if (match[2] === 'leave' && method === 'POST') return {status: 200, body: await this.serial(room, async () => {
      fields(body, []);
      if (room.status === 'waiting') this.closeWaiting(room);
      else if (!terminal(room)) await this.finish(room, 1 - seat, 'PLAYER_LEFT');
      return this.snapshot(room, seat);
    })};
    fail('NOT_FOUND', '房间接口不存在。', 404);
  }
  rate(owner) {
    const now = Date.now(), previous = this.rates.get(owner);
    const rate = previous && now - previous.since < 1000 ? previous : {since: now, count: 0};
    this.rates.set(owner, rate);
    if (++rate.count > 20) fail('RATE_LIMITED', '房间请求过于频繁。', 429);
  }
  global(operation) {
    if(this.globalPending>=32)return Promise.reject(new ApiError('RATE_LIMITED','房间准备请求繁忙，请稍后重试。',429));
    this.globalPending++;
    const result=this.globalQueue.then(operation).finally(()=>{this.globalPending--;});
    this.globalQueue=result.catch(()=>{});return result;
  }
  serial(room, operation) {
    if((room.pendingOperations??0)>=64)return Promise.reject(new ApiError('RATE_LIMITED','本局请求繁忙，请稍后重试。',429));
    room.pendingOperations=(room.pendingOperations??0)+1;
    const result=room.queue.then(operation).finally(()=>{room.pendingOperations--;});
    room.queue=result.catch(()=>{});return result;
  }
  find(id) { const room = this.rooms.get(id) || [...this.rooms.values()].find(item => item.code === id); if (!room) fail('NOT_FOUND', '房间不存在或已过期。', 404); return room; }
  async operation(owner, route, body, run) {
    fields(body,['request_id','deck',...['main_sin','ally_sin','main_faction_id','headquarters'].filter(k=>body&&Object.hasOwn(body,k))]);
    if(Object.hasOwn(body,'main_faction_id') && (!identifier(body.main_faction_id) || !Object.hasOwn(this.store.state?.factions??{},body.main_faction_id))) fail('INVALID_FACTION','请选择已登记的主国。',422);
    mainSin(body.main_sin);
    mainSin(body.ally_sin);
    if (!identifier(body.request_id)) fail('INVALID_REQUEST', 'request_id 必须是 UUID。', 400);
    const key = `${owner}:${route}:${body.request_id}`, fingerprint = hash(body), previous = this.operations.get(key);
    if (previous) {
      if (previous.hash !== fingerprint) fail('IDEMPOTENCY_CONFLICT', '相同请求标识不能更换牌组。', 409);
      const room = this.rooms.get(previous.room);
      if (!room) fail('ROOM_EXPIRED', '原请求的房间已过期。', 410);
      return this.snapshot(room, room.players.indexOf(owner));
    }
    if (this.operations.size >= 4096) fail('RATE_LIMITED', '房间准备请求达到暂存上限。', 429);
    const result = await run();
    this.operations.set(key, {hash: fingerprint, room: result.room_id, at: Date.now()});
    return result;
  }
  async deck(refs) {
    if (!Array.isArray(refs) || refs.length !== DECK_SIZE) fail('INVALID_DECK', '牌组必须恰有 40 张已发布卡牌，总部不计入。', 422);
    const cards = [], records = [];
    for (const ref of refs) {
      fields(ref, ['card_id', 'revision', 'definition_hash']);
      if (!identifier(ref.card_id) || !Number.isSafeInteger(ref.revision) || ref.revision < 1 || typeof ref.definition_hash !== 'string' || !HASH.test(ref.definition_hash)) fail('INVALID_DECK', '卡牌引用格式无效。', 422);
      const card = await this.store.getCard(ref.card_id, ref.revision);
      if (!card || card.card_id !== ref.card_id || card.revision !== ref.revision) fail('CARD_NOT_FOUND', '牌组包含未发布的卡牌或版本。', 422);
      if (card.definition_hash !== ref.definition_hash || hash(card.definition) !== ref.definition_hash) fail('CARD_HASH_MISMATCH', '卡牌版本哈希不一致。', 422);
      if (typeof card.compiled_program_hash !== 'string' || !HASH.test(card.compiled_program_hash)) fail('COMPILED_PROGRAM_MISMATCH', '已发布卡牌缺少可信编译记录。', 422);
      records.push(card);
      cards.push({telemetry_ref:{card_id:card.card_id,revision:card.revision},token_art_ids:tokenArtIds(card),definition: structuredClone(card.definition), definition_hash: card.definition_hash, compiled_program_hash: card.compiled_program_hash, ...(card.art ? {art_id:card.art.id} : {})});
    }
    const invalid = checkDeckCopies(records);
    if(invalid)fail('INVALID_DECK',invalid,422);
    const factions=deckFactions(records,this.store.state?.factions);
    if(factions.error)fail('INVALID_FACTION',factions.error,422);
    return cards;
  }
  async requiresUpdate(deck) {
    const keywords = (await this.store.listKeywords()).map(e => e.definition);
    const required = abilities => Math.max(0,...(abilities||[]).map(a => Math.max(a.trigger==='on_summon'?806:a.target?803:0,...a.effects.map(e => e.op==='create_card'?806:['search_deck','summon_from_deck'].includes(e.op)?805:['modify_stacks','set_stacks'].includes(e.op)?804:e.amount?.stat?803:0))));
    // Adjacency and insertion change legality even for old cards. Both peers
    // must use the same rules instead of displaying whole-line Guard targets.
    return Math.max(ruleCapabilities.battle_rules.minimum_client_build,...deck.map(c => Math.max(c.definition.appearance?.name_break?809:0,required(c.definition.abilities),...c.definition.tokens.map(t=>Object.keys(t).some(k=>['kind','cost','operation_cost','abilities','play_target','counter_trigger','flavor_text'].includes(k))||t.keywords.some(r=>!['core.blitz','core.guard'].includes(r.id))?806:0),...c.definition.keywords.map(ref => required(keywords.find(k => k.id === ref.id && k.version === ref.version)?.implementation.abilities)))));
  }
  async create(owner, body, clientBuild = 0) {
    if (this.players.has(owner)) fail('ALREADY_IN_ROOM', '你已有一场未结束的对局，请先返回或离开。', 409);
    if (this.rooms.size >= this.maxRooms * 4 || [...this.rooms.values()].filter(room => !terminal(room)).length >= this.maxRooms) fail('ROOM_LIMIT', '服务器房间已满，请稍后重试。', 429);
    const deck = await this.deck(body.deck), now = Date.now();
    const headquarters=headquartersEnvelope(headquartersFor(this.store.state,body.headquarters));
    const needsUpdate = await this.requiresUpdate(deck);
    if (clientBuild < needsUpdate) fail("CLIENT_UPDATE_REQUIRED", `战斗规则已更新，请先更新客户端至 ${clientVersion(needsUpdate)}。`, 409);
    const composition=deckComposition(deck,this.store.state?.factions,body.main_sin,body.ally_sin);
    if(composition.error)fail('INVALID_DECK',composition.error,422);
    let code; do { code = String(randomInt(100000, 1000000)); } while ([...this.rooms.values()].some(room => room.code === code));
    const mainFaction = deckFactions(deck,this.store.state?.factions,body.main_faction_id??null).main_faction_id;
    const room = {allySins:[mainSin(body.ally_sin),''],mainSins:[mainSin(body.main_sin),''],headquarters:[headquarters,null],headquartersRefs:[structuredClone(body.headquarters??null),null],clientBuild, needsUpdate, mainFactions:[mainFaction,null], id: randomUUID(), code, status: 'waiting', players: [owner, null], decks: [deck, null], deckRefs: [structuredClone(body.deck), null], createdAt: now, lastAction: now, lastSeen: [now, now], absent: [], deadline: null, endedAt: null, queue: Promise.resolve(), worker: null, views: null, seq: 0, winner: -1, actions: new Map()};
    this.rooms.set(room.id, room); this.players.set(owner, room.id);
    return this.snapshot(room, 0);
  }
  async join(room, owner, body, clientBuild = 0) {
    const other = await this.deck(body.deck);
    const headquarters=headquartersEnvelope(headquartersFor(this.store.state,body.headquarters));
    const currentSeat = room.players.indexOf(owner);
    if (currentSeat >= 0) { room.lastSeen[currentSeat] = Date.now(); return this.snapshot(room, currentSeat); }
    if (this.players.has(owner)) fail('ALREADY_IN_ROOM', '你已有一场未结束的对局。', 409);
    if (room.status !== 'waiting' || room.players[1]) fail('ROOM_FULL', '房间已开始或已关闭。', 409);
    const requiredBuild = Math.max(room.needsUpdate, await this.requiresUpdate(other));
    if (clientBuild < requiredBuild || room.clientBuild < requiredBuild) fail('CLIENT_UPDATE_REQUIRED', `战斗规则已更新，双方均需更新客户端至 ${clientVersion(requiredBuild)} 后重新建房。`, 409);
    const composition=deckComposition(other,this.store.state?.factions,body.main_sin,body.ally_sin);
    if(composition.error)fail('INVALID_DECK',composition.error,422);
    const keywords = (await this.store.listKeywords()).map(entry => structuredClone(entry.definition));
    const hostDeck = room.decks[0];
    const hostComposition=deckComposition(hostDeck,this.store.state?.factions,room.mainSins[0],room.allySins[0]);
    if(hostComposition.error)fail('INVALID_DECK','房主牌组规则已变化，请重新组牌建房：'+hostComposition.error,422);
    const worker = this.workerFactory();
    room.status = 'starting';
    try {
      const result = await worker.request({command: 'setup', opening_redraw:this.openingRedraw, decks: [room.decks[0], other], headquarters:[room.headquarters[0],headquarters], keywords, seed: randomInt(1, 2147483646)});
      room.players[1] = owner; room.worker = worker; room.decks = null; room.status = 'active';
      room.lastSeen = [Date.now(), Date.now()]; room.lastAction = Date.now(); this.players.set(owner, room.id);
      room.deckRefs[1] = structuredClone(body.deck);
      room.headquarters[1]=headquarters;room.headquartersRefs[1]=structuredClone(body.headquarters??null);
      room.mainSins[1] = mainSin(body.main_sin);
      room.allySins[1] = mainSin(body.ally_sin);
      room.mainFactions[1] = deckFactions(other,this.store.state?.factions,body.main_faction_id??null).main_faction_id;
      if(this.archive) await this.archive.start(room,room.deckRefs);
      await this.acceptResult(room, result);
      return this.snapshot(room, 1);
    } catch (error) {
      worker.close(); room.status = 'waiting'; room.players[1] = null; room.decks = [hostDeck, null]; room.worker = null; room.views = null;
      if (this.players.get(owner) === room.id) this.players.delete(owner);
      throw error;
    }
  }
  watch(room,owner,body,clientBuild) {
    fields(body,['seat']);
    if(!Number.isInteger(body.seat)||![0,1].includes(body.seat))fail('INVALID_REQUEST','请选择要跟随的玩家。',400);
    if(this.players.has(owner)||room.players.includes(owner))fail('ALREADY_IN_ROOM','请先结束或离开自己的对局。',409);
    const requiredBuild=Math.max(859,room.needsUpdate);
    if(clientBuild<requiredBuild)fail('CLIENT_UPDATE_REQUIRED',`观战需要更新客户端至 ${clientVersion(requiredBuild)} 或更新版本。`,409);
    if(!['active','suspended'].includes(room.status)||!room.views)fail('MATCH_NOT_STARTED','只能观战正在进行的对局。',409);
    room.spectators??=new Map();
    const old=room.spectators.get(owner);
    // Keep the binding after leaving/reconnecting; never grant both private views.
    if(old&&old.seat!==body.seat)fail('SPECTATOR_PERSPECTIVE_LOCKED','本局已固定跟随的玩家，不能切换另一方手牌。',409);
    if(!old&&room.spectators.size>=256)fail('SPECTATOR_LIMIT','本局观众已满，请稍后再试。',429);
    this.checkSpectatorCapacity(room,old);
    const viewer=old??{seat:body.seat};viewer.active=true;viewer.lastSeen=Date.now();room.spectators.set(owner,viewer);
    return this.spectatorSnapshot(room,viewer);
  }
  spectatorCount(room) { return [...(room.spectators?.values()??[])].filter(v=>v.active&&Date.now()-v.lastSeen<this.offlineAfterMs).length; }
  checkSpectatorCapacity(room,viewer) {
    if((!viewer?.active||Date.now()-viewer.lastSeen>=this.offlineAfterMs)&&this.spectatorCount(room)>=64)fail('SPECTATOR_LIMIT','本局观众已满，请稍后再试。',429);
  }
  spectatorSnapshot(room,viewer) { return {...this.snapshot(room,viewer.seat),spectator:true,followed_player:viewer.seat}; }
  commanderNames(room) { return room.players.map(p=>p?(this.store.state?.identities?.[p]?.display_name??'指挥官'):'等待加入'); }
  summary(room, owner) { return {room_id: room.id, code: room.code, status: room.status, seats: room.players.filter(Boolean).length, mine: room.players.includes(owner), created_at: new Date(room.createdAt).toISOString(),commanders:this.commanderNames(room),spectators:this.spectatorCount(room),watching:!!room.spectators?.get(owner)?.active,followed_player:room.spectators?.get(owner)?.seat??null}; }
  snapshot(room, seat) {
    if (seat < 0 || seat > 1) fail('FORBIDDEN', '不能读取他人的局面。', 403);
    const state = room.views ? structuredClone(room.views[seat]) : null;
    // Public cosmetics only: never inspect or disclose an individual hidden card.
    if(state) state.players.forEach((player,index)=>{player.main_faction_id=room.mainFactions?.[index]??'';player.main_sin=room.mainSins?.[index]??'';player.commander_name=this.store.state?.identities?.[room.players[index]]?.display_name??'指挥官';});
    return {room_id: room.id, code: room.code, status: room.status, local_player: seat, seat, spectator:false,spectators:this.spectatorCount(room),state_seq: room.seq, state, deadline_unix_ms: room.deadline, choice_deadline_unix_ms: room.choiceDeadline ?? null, protocol_version: 'cloud-1', emote_events:(room.emoteEvents??[]).filter(e=>Date.now()-e.sent_at<5000)};
  }
  emote(room,seat,body) {
    fields(body,['request_id','emote_id',...(Object.hasOwn(body??{},'point')?['point']:[])]);
    if(body.point!==undefined&&(!Array.isArray(body.point)||body.point.length!==2||body.point.some(n=>!Number.isSafeInteger(n)||n<0||n>10000)))fail('INVALID_EMOTE','表情位置无效。',422);
    if(!identifier(body.request_id)||!emoteId(body.emote_id))fail('INVALID_EMOTE','表情请求无效。',422);
    const emote=this.store.state.emotes?.[body.emote_id];
    if(!emote||emote.deleted)fail('NOT_FOUND','表情已下架，请重新配置轮盘。',404);
    if(room.status!=='active'||!room.views)fail('INVALID_STATE','对局中才能发送表情。',409);
    room.emoteRequests??=new Map();room.emoteEvents??=[];room.emoteLast??=[0,0];room.emoteSeq??=0;
    const key=seat+':'+body.request_id,previous=room.emoteRequests.get(key),fingerprint=JSON.stringify([body.emote_id,body.point??null]);
    if(previous){if(previous!==fingerprint)fail('IDEMPOTENCY_CONFLICT','请求已用于另一表情。',409);return this.snapshot(room,seat);}
    const now=Date.now();if(now-room.emoteLast[seat]<80)fail('RATE_LIMITED','请稍等片刻再发表情。',429);
    room.emoteLast[seat]=now;room.lastSeen[seat]=now;room.emoteRequests.set(key,fingerprint);
    if(room.emoteRequests.size>64)room.emoteRequests.delete(room.emoteRequests.keys().next().value);
    room.emoteEvents.push({id:++room.emoteSeq,player:seat,emote_id:body.emote_id,scale_percent:emoteScale(emote.scale_percent),point:body.point??null,sent_at:now});room.emoteEvents=room.emoteEvents.slice(-64);
    return this.snapshot(room,seat);
  }
  command(command) {
    if (!command || typeof command !== 'object' || Array.isArray(command)) fail('INVALID_REQUEST', '行动格式无效。', 400);
    if(command.type==='activate'){
      fields(command,['type','uid','ability_index']);
      if(!Number.isSafeInteger(command.uid)||command.uid<1||!Number.isSafeInteger(command.ability_index)||command.ability_index<0||command.ability_index>63)fail('INVALID_REQUEST','主动能力格式无效。',400);
    } else if(command.type==='mulligan'){
      fields(command,['type','hand_ids']);
      if(!Array.isArray(command.hand_ids)||command.hand_ids.length>5||new Set(command.hand_ids).size!==command.hand_ids.length||command.hand_ids.some(id=>typeof id!=='string'||id.length>64||!/^h[1-9]\d*$/.test(id)))fail('INVALID_REQUEST','换牌格式无效。',400);
    } else if (command.type === 'choose_card') {
      fields(command,['type','choice_id','option_index']);
      if(typeof command.choice_id !== 'string'||!/^\d+-\d+$/.test(command.choice_id)||command.choice_id.length>64||!Number.isSafeInteger(command.option_index)||command.option_index<0||command.option_index>=10)fail('INVALID_REQUEST','选牌格式无效。',400);
    } else if (command.type === 'choose_target') {
      fields(command, ['type', 'choice_id', 'target_uid']);
      if (typeof command.choice_id !== 'string' || !/^\d+-\d+$/.test(command.choice_id) || command.choice_id.length > 64 || !Number.isSafeInteger(command.target_uid) || command.target_uid < 1&&![-101,-102,-1000].includes(command.target_uid)) fail('INVALID_REQUEST', '目标选择格式无效。', 400);
    } else if (command.type === 'play') {
      fields(command, ['type','hand_id',...(Object.hasOwn(command,'target_uid')?['target_uid']:[]),...(Object.hasOwn(command,'position')?['position']:[])]);
      if (typeof command.hand_id !== 'string' || command.hand_id.length > 64 || !/^h[1-9]\d*$/.test(command.hand_id)) fail('INVALID_REQUEST', '手牌标识格式无效。', 400);
      if (command.target_uid !== undefined && (!Number.isSafeInteger(command.target_uid) || command.target_uid < 1)) fail('INVALID_REQUEST', '目标标识无效。', 400);
    } else if (command.type === 'move' || command.type === 'attack') {
      fields(command, command.type === 'move' ? ['type', 'uid',...(Object.hasOwn(command,'position')?['position']:[])] : ['type', 'uid', 'target_uid']);
      if (!Number.isSafeInteger(command.uid) || command.uid < 1) fail('INVALID_REQUEST', '单位标识格式无效。', 400);
      if (command.type === 'attack' && (!Number.isSafeInteger(command.target_uid) || !(command.target_uid > 0 || command.target_uid === -1))) fail('INVALID_REQUEST', '目标标识无效。', 400);
    } else if (['end_turn', 'concede'].includes(command.type)) fields(command, ['type']);
    else fail('INVALID_REQUEST', '不支持此行动。', 400);
    if(Object.hasOwn(command,'position')&&(!Number.isSafeInteger(command.position)||command.position<0||command.position>4)) fail('INVALID_REQUEST','阵线位置无效。',400);
    return command;
  }
  async action(room, owner, seat, body) {
    fields(body, ['action_id', 'expected_state_seq', 'command']);
    if (typeof body.action_id !== 'string' || body.action_id.length < 1 || body.action_id.length > 80 || !/^[a-zA-Z0-9-]+$/.test(body.action_id) || !Number.isSafeInteger(body.expected_state_seq) || body.expected_state_seq < 0) fail('INVALID_REQUEST', '行动标识或序号无效。', 400);
    this.command(body.command);
    const key = `${owner}:${body.action_id}`, fingerprint = hash(body), previous = room.actions.get(key);
    room.lastSeen[seat] = Date.now();
    if (previous) {
      if (previous.hash !== fingerprint) fail('ACTION_ID_CONFLICT', '相同行动标识不能更换内容。', 409);
      await this.reconcile(room);
      return {...this.snapshot(room, seat), action_result: structuredClone(previous.result)};
    }
    if (room.actions.size >= 8192) { await this.finish(room, 3, 'SERVER_ERROR'); fail('RATE_LIMITED', '本局行动请求达到上限。', 429); }
    await this.reconcile(room);
    let code = '', message = '', accepted = false;
    if (room.status === 'waiting' || room.status === 'starting') code = 'MATCH_NOT_STARTED';
    else if (terminal(room)) code = 'MATCH_ENDED';
    else if (room.status === 'suspended') code = 'MATCH_SUSPENDED';
    else if (room.seq !== body.expected_state_seq && !(body.command.type==='mulligan'&&body.expected_state_seq<room.seq&&room.views?.[seat]?.mulligan&&!room.views[seat].mulligan.confirmed[seat])) code = 'STALE_STATE';
    else {
      try {
        const result = await room.worker.request({command: 'action', player: seat, action: body.command});
        await this.acceptResult(room, result); accepted = result.accepted === true;
        if (!accepted) { code = result.error === 'RULE_BUDGET_EXCEEDED' ? result.error : 'ILLEGAL_ACTION'; message = String(result.error || '').slice(0, 200); }
        if (accepted) room.lastAction = Date.now();
      } catch { await this.abort(room); code = 'MATCH_ABORTED'; }
    }
    const result = {action_id: body.action_id, accepted, state_seq: room.seq, code: code || null, message};
    // A bounded match has at most 48 initial cards. Retain every accepted/rejected
    // action until result expiry, with a defensive per-room request ceiling.
    room.actions.set(key, {hash: fingerprint, result});
    return {...this.snapshot(room, seat), action_result: result};
  }
  async acceptResult(room, result) {
    if (!result || !Array.isArray(result.views) || result.views.length !== 2 || !Number.isSafeInteger(result.state_seq) || ![-1, 0, 1, 2, 3].includes(result.winner)) throw new Error('Invalid worker state');
    for (let seat = 0; seat < 2; seat++) {
      const view = result.views[seat];
      if (!view || !Array.isArray(view.players) || view.players.length !== 2 || view.players.some(p => !Array.isArray(p.deck) || p.deck.length) || view.players[1 - seat].hand.length || view.seed !== undefined || view.rng_state !== undefined || view.private_log !== undefined || view._resolution !== undefined) throw new Error('Worker exposed hidden state');
    }
    this.archive?.capture(room,result);
    if(result.views[0].mulligan)room.mulliganDeadline??=Date.now()+45000;else room.mulliganDeadline=null;
    const choice = result.views[0].pending_choice;
    if (choice?.choice_id !== room.views?.[0]?.pending_choice?.choice_id) room.choiceDeadline = choice ? Date.now() + 30000 : null;
    room.views = result.views; room.seq = result.state_seq; room.winner = result.winner;
    if (room.winner !== -1) {
      room.status = room.winner === 3 ? 'aborted' : 'ended'; room.endedAt ??= Date.now(); room.deadline = null;
      this.release(room); room.worker?.close(); room.worker = null;
      await this.persist(room);
    }
  }
  async persist(room) {
    if(!this.archive || !room.archive || room.archiveSaved)return;
    try { await this.archive.finish(room,room.endReason); }
    catch { room.archiveSaved=false; console.error('Match archive pending retry:',room.id); }
  }
  release(room) { for (const player of room.players) if (this.players.get(player) === room.id) this.players.delete(player); }
  closeWaiting(room) { room.status = 'closed'; room.endedAt = Date.now(); room.decks = null; this.release(room); }
  abort(room) {
    room.worker?.close(); room.worker = null; room.status = 'aborted'; room.winner = 3; room.seq++; room.endedAt = Date.now(); room.deadline = null;
    for (const view of room.views || []) { view.winner = 3; view.state_seq = room.seq; view.suspended = false; }
    room.endReason ||= 'SERVER_ERROR';
    this.release(room);
    return this.persist(room);
  }
  async finish(room, winner, reason) {
    if (terminal(room)) return;
    if (!room.worker) return this.closeWaiting(room);
    room.endReason=reason;
    if(['DISCONNECT_TIMEOUT','BOTH_OFFLINE','IDLE_TIMEOUT','SERVER_ERROR'].includes(reason))console.info(JSON.stringify({event:'match_connection_end',room:room.id,reason,heartbeat_age_ms:room.lastSeen.map(t=>Date.now()-t)}));
    try { await this.acceptResult(room, await room.worker.request({command: 'finish', winner, reason})); }
    catch { await this.abort(room); }
  }
  async reconcile(room) {
    if (terminal(room) || room.status === 'waiting' || room.status === 'starting') return;
    const now = Date.now();
    // A late heartbeat cannot erase an already-expired disconnect deadline.
    if (room.deadline && now >= room.deadline) return this.finish(room, room.absent.length === 1 ? 1 - room.absent[0] : 3, room.absent.length === 1 ? 'DISCONNECT_TIMEOUT' : 'BOTH_OFFLINE');
    if (now - room.lastAction >= this.idleTimeoutMs) return this.finish(room, 3, 'IDLE_TIMEOUT');
    const absent = [0, 1].filter(seat => now - room.lastSeen[seat] >= this.offlineAfterMs);
    if (absent.join(',') !== room.absent.join(',')) {
      console.info(JSON.stringify({event:absent.length?'match_connection_paused':'match_connection_resumed',room:room.id,absent,heartbeat_age_ms:room.lastSeen.map(t=>now-t)}));
      room.absent = absent; room.deadline = absent.length ? now + (absent.length === 2 ? this.bothOfflineGraceMs : this.disconnectGraceMs) : null;
      if (absent.length && !room.choicePausedAt) room.choicePausedAt = now;
      if (!absent.length && room.choicePausedAt) { if (room.choiceDeadline) room.choiceDeadline += now - room.choicePausedAt; if(room.mulliganDeadline)room.mulliganDeadline+=now-room.choicePausedAt; room.choicePausedAt = null; }
      room.status = absent.length ? 'suspended' : 'active';
      try { await this.acceptResult(room, await room.worker.request({command: 'pause', paused: absent.length > 0})); } catch { return this.abort(room); }
    }
    if(!absent.length&&room.mulliganDeadline&&now>=room.mulliganDeadline){
      for(const seat of [0,1])if(room.views?.[seat]?.mulligan&&!room.views[seat].mulligan.confirmed[seat]){
        try{const result=await room.worker.request({command:'action',player:seat,action:{type:'mulligan',hand_ids:[]}});if(!result.accepted)return this.abort(room);await this.acceptResult(room,result);room.lastAction=now;}
        catch{return this.abort(room);}
      }
    }
    if (!absent.length && room.choiceDeadline && now >= room.choiceDeadline) {
      const choice = room.views[0].pending_choice;
      try {
        const result = await room.worker.request({command:'action', player:choice.owner, action:choice.kind&&choice.kind!=='unit'?{type:'choose_card',choice_id:choice.choice_id,option_index:0}:{type:'choose_target', choice_id:choice.choice_id, target_uid:choice.targets[0]}});
        if (!result.accepted) return this.abort(room);
        await this.acceptResult(room,result); room.lastAction = now;
      } catch { return this.abort(room); }
    }
    if (room.deadline && now >= room.deadline) await this.finish(room, absent.length === 1 ? 1 - absent[0] : 3, absent.length === 1 ? 'DISCONNECT_TIMEOUT' : 'BOTH_OFFLINE');
  }
  async sweep() {
    if (this.closed) return;
    const now = Date.now();
    for (const room of this.rooms.values()) {
      if (terminal(room) && room.archive && !room.archiveSaved) await this.persist(room);
      if (terminal(room) && (!room.archive || room.archiveSaved) && now - room.endedAt >= this.retentionMs) { this.rooms.delete(room.id); continue; }
      if (room.status === 'waiting' && now - room.createdAt >= Math.min(120000, this.idleTimeoutMs)) this.closeWaiting(room);
      else if (!terminal(room) && !room.pendingOperations) void this.serial(room, () => this.reconcile(room)).catch(() => this.abort(room));
    }
    for (const [key, item] of this.operations) if (now - item.at > 600000) this.operations.delete(key);
    for (const [key, item] of this.rates) if (now - item.since > 60000) this.rates.delete(key);
  }
  async close() {
    this.closed = true; clearInterval(this.sweepTimer); await this.globalQueue;
    for (const room of this.rooms.values()) { await room.queue; if(!terminal(room)&&room.worker) await this.finish(room,3,'SERVER_ERROR'); await this.persist(room); room.worker?.close(); }
    this.rooms.clear(); this.players.clear();
  }
}
