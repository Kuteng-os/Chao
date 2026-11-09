import {RequestBudget,readJSONBody,closeUnreadRequest} from './request_limits.js';
import {ImageWorkers} from './image_workers.js';
import {Emotes} from './emotes.js';
import {seriesCatalog} from './card_series.js';
import {CardSeriesAdmin} from './card_series_admin.js';
import {componentCatalog} from './mechanism_components.js';
import {diagnosticList,resolveDiagnostic,recordDiagnostic,authorReports,inbox,readMessage,resumeContext} from './diagnostics.js';
import http from 'node:http';
import https from 'node:https';
import {createSecureContext} from 'node:tls';
import {readFile} from 'node:fs/promises';
import {timingSafeEqual} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {Store} from './store.js';
import {DeepSeekProvider} from './provider.js';
import {CardService} from './service.js';
import {ApiError, fail} from './codec.js';
import {CloudAuth} from './cloud_auth.js';
import {CloudCatalog} from './cloud_catalog.js';
import {catalogUpdates} from './catalog_updates.js';
import {SharedDecks} from './shared_decks.js';
import {CardMedia} from './card_media.js';
import {CardArt} from './card_art.js';
import {ClientReleases} from './client_releases.js';
import {MatchArchive} from './match_archive.js';
import {Profiles} from './profiles.js';
import {ContentLifecycle} from './content_lifecycle.js';
import {Factions} from './factions.js';
import {ruleCapabilities} from './rule_capabilities.js';

const loopback = host => ['127.0.0.1', '::1', 'localhost'].includes(host);
export async function createApp(options = {}) {
  const host = options.host || process.env.HOST || '127.0.0.1';
  const token = options.token ?? process.env.CARD_API_TOKEN ?? '';
  const centralMode = options.centralMode ?? process.env.CENTRAL_MODE === '1';
  const browserOrigins = new Set(options.browserOrigins ?? (process.env.BROWSER_ORIGINS || '').split(',').filter(Boolean));
  const webRoot = options.webRoot || fileURLToPath(new URL('../../web/', import.meta.url));
  const assets = new Map([['emote_preview.mjs','text/javascript'],['emotes.mjs','text/javascript'], ['emotes.css','text/css'], ['index.html', 'text/html'], ['styles.css', 'text/css'], ['workshop.css', 'text/css'], ['stats.html', 'text/html'], ['stats.mjs','text/javascript'], ['stats.css','text/css'], ['accounts.mjs', 'text/javascript'], ['series.mjs','text/javascript; charset=utf-8'],['catalog.mjs','text/javascript; charset=utf-8'],['app.mjs', 'text/javascript'], ['lifecycle.mjs','text/javascript'], ['media.mjs','text/javascript'], ['mechanism.mjs','text/javascript'], ['model.mjs', 'text/javascript'],['icon_crop.mjs','text/javascript'],['card_crop.mjs','text/javascript'], ['contracts.json', 'application/json']]);
  assets.set('sins.mjs','text/javascript');
  assets.set('card_text.mjs','text/javascript; charset=utf-8');
  for(const id of ['wrath','lust','sloth','gluttony','gloom','pride','envy'])assets.set('sins/'+id+'.png','image/png');
  const inviteToken = options.inviteToken ?? process.env.REGISTRATION_INVITE_TOKEN ?? '';
  const certFile = options.tlsCertFile ?? process.env.TLS_CERT_FILE;
  const keyFile = options.tlsKeyFile ?? process.env.TLS_KEY_FILE;
  if (Boolean(certFile) !== Boolean(keyFile)) throw new Error('TLS_CERT_FILE and TLS_KEY_FILE must be configured together.');
  if (centralMode && (typeof inviteToken !== 'string' || inviteToken.length < 24)) throw new Error('CENTRAL_MODE requires REGISTRATION_INVITE_TOKEN with at least 24 characters.');
  if (centralMode && !loopback(host) && !certFile) throw new Error('Non-loopback CENTRAL_MODE requires TLS_CERT_FILE and TLS_KEY_FILE.');
  if (!centralMode && !loopback(host) && token.length < 24) throw new Error('Non-loopback binding requires CARD_API_TOKEN with at least 24 characters.');
  const tls = certFile ? {cert: await readFile(certFile), key: await readFile(keyFile), minVersion: 'TLSv1.2'} : null;
  if (tls) createSecureContext(tls); // Fail invalid/mismatched certificates before locking persistent data.
  const provider = options.provider || new DeepSeekProvider({apiKey: process.env.DEEPSEEK_API_KEY, model: process.env.DEEPSEEK_MODEL, baseURL: process.env.DEEPSEEK_BASE_URL, deadlineMs: Number(process.env.GENERATION_DEADLINE_MS) || 240000});
  const store = await new Store(options.dataDir || process.env.CARD_DATA_DIR || resolve(fileURLToPath(new URL('../data/', import.meta.url)))).init();
  const service = new CardService(store, provider, {...options, requireFactions:centralMode});
  const auth = centralMode ? new CloudAuth(store, inviteToken, options) : null;
  const catalog = centralMode ? new CloudCatalog(service, options) : null;
  const sharedDecks = centralMode ? new SharedDecks(service) : null;
  const imageWorkers=new ImageWorkers();
  const cardArt = new CardArt(store,imageWorkers);
  const emotes = new Emotes(store,imageWorkers);
  const requestBudget=new RequestBudget(options.requestLimits);
  const cardMedia = new CardMedia(store);
  const factions = new Factions(service);
  const lifecycle = new ContentLifecycle(service);
  const cardSeriesAdmin = new CardSeriesAdmin(service);
  const history = new MatchArchive(store);
  const profiles = new Profiles(auth,store);
  const releases = new ClientReleases(options.clientReleaseDir || process.env.CLIENT_RELEASE_DIR || resolve(store.directory,'client-releases'));
  let matches = null;
  try {
    if (centralMode && options.matches !== false) {
      const {CentralMatches} = await import('./central_matches.js');
      matches = options.matches || new CentralMatches({store, godotBin: options.godotBin || process.env.GODOT_BIN, projectPath: options.projectPath || process.env.GODOT_PROJECT_PATH || fileURLToPath(new URL('../../', import.meta.url)), maxRooms: options.maxRooms, idleTimeoutMs: options.idleTimeoutMs});
    }
  } catch (error) { await service.close(); throw error; }
  const health = () => ({...(centralMode ? {ok: true, mode: 'central', configured: provider.configured, model: provider.model} : {...service.health(), mode: 'local'}), card_series:seriesCatalog(store.state), transport: tls ? 'https' : 'http', rules: ruleCapabilities});
  const handler = async (req, res) => {
    let request_id = null; let diagnosticContext=null; let releaseBudget=null;
    const send = (status, data) => { if (!res.destroyed) { res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'}); res.end(JSON.stringify(data)); } };
    try {
      if (req.headers.origin && !browserOrigins.has(req.headers.origin)) fail('UNAUTHORIZED', '此网页来源不被允许。', 403);
      const url = new URL(req.url, 'http://localhost'), path = url.pathname, method = req.method;
      if(await releases.handle(req,res,path))return;
      const emoteAsset=/^\/v1\/emotes\/assets\/([0-9a-f]{64})\.png$/.exec(path);
      if(method==='GET'&&emoteAsset){const bytes=await emotes.image(emoteAsset[1]);res.writeHead(200,{'Content-Type':'image/png','Content-Length':bytes.length,'Cache-Control':'public, max-age=31536000, immutable','X-Content-Type-Options':'nosniff'});return res.end(bytes);}
      if(method==='GET'&&path==='/v1/public/emotes')return send(200,emotes.list());
      const soundPath=/^\/v1\/card-sounds\/([0-9a-f]{64})\.wav$/.exec(path);
      if(method==='GET'&&soundPath){const bytes=await cardMedia.audio(soundPath[1]);res.writeHead(200,{'Content-Type':'audio/wav','Content-Length':bytes.length,'Cache-Control':'public, max-age=31536000, immutable','X-Content-Type-Options':'nosniff'});return res.end(bytes);}
      const artPath = /^\/v1\/card-art\/([0-9a-f]{64})\.png$/.exec(path);
      if (method === 'GET' && artPath) {
        const image = await cardArt.image(artPath[1]);
        res.writeHead(200, {'Content-Type':'image/png','Content-Length':image.length,'Cache-Control':'public, max-age=31536000, immutable','X-Content-Type-Options':'nosniff'});
        return res.end(image);
      }
      if (method === 'GET' && (path === '/' || path === '/workshop')) { res.writeHead(302, {Location: '/workshop/'}); return res.end(); }
      if (method === 'GET' && path.startsWith('/workshop/')) {
        const asset = path.slice('/workshop/'.length) || 'index.html';
        if (!assets.has(asset)) fail('NOT_FOUND', '网页资源不存在。', 404);
        let data;
        try { data = await readFile(resolve(webRoot, asset)); } catch { fail('NOT_FOUND', '网页资源尚未部署。', 404); }
        res.writeHead(200, {'Content-Type': assets.get(asset) + '; charset=utf-8', 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"});
        return res.end(data);
      }
      if(centralMode && method==='GET' && path==='/v1/public/statistics') return send(200,history.stats(url.searchParams));
      if (centralMode && method === 'GET' && path === '/health') return send(200, health());
      if (centralMode && method === 'GET' && path === '/v1/public/cards') return send(200, catalog.cards(null));
      if (centralMode && method === 'GET' && path === '/v1/public/keywords') return send(200, service.keywords());
      if (centralMode && method === 'GET' && path === '/v1/public/factions') return send(200, factions.list());
      if (centralMode && method === 'GET' && path === '/v1/public/decks') return send(200, sharedDecks.list(null, false, url.searchParams.get('cursor') || '0'));
      const publicDeck = /^\/v1\/public\/decks\/([0-9a-f-]{36})$/.exec(path);
      if (centralMode && method === 'GET' && publicDeck) return send(200, sharedDecks.detail(publicDeck[1]));
      if (centralMode && method === 'GET' && path === '/v1/account-options') return send(200, auth.accounts.options());
      const publicAccount = centralMode && method === 'POST' && ['/v1/accounts/register','/v1/accounts/login'].includes(path);
      const creatingSession = centralMode && method === 'POST' && path === '/v1/sessions';
      const exchangingSession = centralMode && method === 'POST' && path === '/v1/browser-sessions/exchange';
      let identity = null, owner = 'local-player';
      if (centralMode) {
        if (!creatingSession && !exchangingSession && !publicAccount) { identity = auth.authenticate(req.headers.authorization); owner = identity.owner_id; }
      } else if (token) {
        const actual = Buffer.from(req.headers.authorization || ''), expected = Buffer.from(`Bearer ${token}`);
        if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) fail('UNAUTHORIZED', '业务令牌缺失或无效。', 401);
      } else if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress)) fail('UNAUTHORIZED', '未配置令牌的服务仅允许本机访问。', 401);
      if(identity?.must_change_password && !['/v1/me','/v1/account/password','/v1/logout','/v1/browser-sessions'].includes(path)) fail('PASSWORD_CHANGE_REQUIRED','请先修改初始密码。',403);
      let body;
      if(method==='DELETE')releaseBudget=requestBudget.acquire(centralMode&&identity?'owner:'+owner:'ip:'+req.socket.remoteAddress,4096);
      if (['POST', 'PUT', 'PATCH'].includes(method)) {
        if (!/^application\/json(?:\s*;|$)/i.test(String(req.headers['content-type'] || ''))) fail('INVALID_REQUEST', '请求必须使用 application/json。', 400);
        const maxBytes = path === '/v1/emotes' ? 6*1024*1024 : path === '/v1/catalog/updates' ? 3*1024*1024 : path === '/v1/card-sounds' ? 23*1024*1024 : path === '/v1/card-art' ? 3*1024*1024 : centralMode && path === '/v1/card-sync' ? 262144 : (creatingSession || publicAccount || path.startsWith('/v1/account') || path.startsWith('/v1/admin/')) ? 4096 : 65536;
        releaseBudget=requestBudget.acquire(centralMode&&identity?'owner:'+owner:'ip:'+req.socket.remoteAddress,maxBytes);
        const parsed=await readJSONBody(req,maxBytes,options.bodyTimeoutMs??15000);
        body=parsed.body;const size=parsed.size;request_id=typeof body.request_id==='string'?body.request_id:null;
        if ((path === '/v1/card-generations' || path === '/v1/keyword-proposals') && size > 16384) fail('INPUT_TOO_LONG', '生成请求超过 16 KiB。', 413);
      }
      if(['/v1/card-drafts','/v1/cards/drafts','/v1/card-generations','/v1/mechanism-reviews','/v1/keyword-proposals'].includes(path))diagnosticContext={stage:path,owner,source:body?.source_text,card_name:body?.definition?.name??body?.card_blueprint?.name,definition:body?.definition??body?.card_blueprint};
      if (publicAccount) return send(path.endsWith('/register')?201:200, await auth.accounts[path.endsWith('/register')?'register':'login'](body,req.socket.remoteAddress));
      if (centralMode && method === 'POST' && path === '/v1/account/link') return send(201,await auth.accounts.register(body,req.socket.remoteAddress,owner));
      if (centralMode && method === 'POST' && path === '/v1/account/password') return send(200,await auth.accounts.changePassword(owner,body));
      if (centralMode && method === 'POST' && path === '/v1/logout') return send(200,await auth.logout(req.headers.authorization));
      if(method==='GET'&&path==='/v1/mechanism-components')return send(200,{components:componentCatalog(store.state)});
      if(method==='GET'&&path==='/v1/diagnostics')return send(200,authorReports(store.state,owner,url.searchParams.get('number')??''));
      if(method==='GET'&&path==='/v1/diagnostics/resume')return send(200,resumeContext(store.state,owner,url.searchParams.get('number')));
      if(method==='GET'&&path==='/v1/inbox')return send(200,inbox(store.state,owner));
      if(method==='POST'&&path==='/v1/inbox/read')return send(200,await store.transaction(state=>readMessage(state,owner,body.id)));
      if(method==='GET'&&path==='/v1/admin/diagnostics')return send(200,diagnosticList(store.state,owner));
      if(method==='POST'&&path==='/v1/admin/card-series')return send(200,await cardSeriesAdmin.manage(owner,body));
      const cardSeriesPath=/^\/v1\/cards\/([0-9a-f-]{36})\/series$/.exec(path);
      if(method==='PATCH'&&cardSeriesPath)return send(200,await cardSeriesAdmin.assign(owner,cardSeriesPath[1],body));
      if(method==='POST'&&path==='/v1/admin/diagnostics/resolve')return send(200,await store.transaction(state=>resolveDiagnostic(state,owner,body.id,{resolution:body.resolution,version:body.version})));
      if (centralMode && method === 'GET' && path === '/v1/admin/accounts') return send(200,auth.accounts.list(owner));
      if (centralMode && method === 'POST' && path === '/v1/admin/password-reset') return send(200,await auth.accounts.resetPassword(owner,body));
      if (creatingSession) return send(201, await auth.register(body, req.socket.remoteAddress));
      if (exchangingSession) return send(201, await auth.exchangeBrowserSession(body));
      if (centralMode && method === 'POST' && path === '/v1/browser-sessions') return send(201, auth.browserSession(owner));
      if (centralMode && method === 'GET' && path === '/v1/me') return send(200, identity);
      if(centralMode && method==='PATCH' && path==='/v1/profile') return send(200,await profiles.save(owner,body));
      if(centralMode && method==='GET' && path==='/v1/me/statistics') return send(200,history.stats(url.searchParams,owner));
      if(centralMode && method==='GET' && path==='/v1/me/matches') return send(200,history.mine(owner,url.searchParams));
      const historyPath=/^\/v1\/me\/matches\/([0-9a-f-]{36})$/.exec(path);
      if(centralMode && method==='GET' && historyPath) return send(200,await history.detail(owner,historyPath[1]));
      const contentPath=/^\/v1\/content\/(cards|keywords|factions)\/([A-Za-z0-9_.-]{1,128})\/(preview|archive|restore|delete)$/.exec(path);
      if(contentPath) {
        if(method==='GET'&&contentPath[3]==='preview')return send(200,lifecycle.preview(owner,contentPath[1],contentPath[2]));
        if(method==='POST'&&contentPath[3]!=='preview')return send(200,await lifecycle.mutate(owner,contentPath[1],contentPath[2],contentPath[3],body));
      }
      if(method==='GET'&&path==='/v1/emote-loadout')return send(200,emotes.loadout(owner));
      if(method==='PUT'&&path==='/v1/emote-loadout')return send(200,await emotes.save(owner,body));
      if(method==='POST'&&path==='/v1/emotes')return send(201,await emotes.upload(owner,body));
      const emotePath=/^\/v1\/emotes\/([0-9a-f-]{36})(\/delete)?$/.exec(path);
      if(emotePath&&((method==='PATCH'&&!emotePath[2])||(method==='POST'&&emotePath[2])))return send(200,await emotes.edit(owner,emotePath[1],body,Boolean(emotePath[2])));
      if(method==='POST'&&path==='/v1/card-sounds')return send(201,await cardMedia.upload(owner,body));
      if (method === 'POST' && path === '/v1/card-art') return send(201, await cardArt.upload(owner, body));
      if (path === '/v1/factions') {
        if (method === 'GET') return send(200, factions.list(owner));
        if (method === 'POST') return send(201, await factions.save(owner,body));
      }
      const factionPath = /^\/v1\/factions\/([0-9a-f-]{36})$/.exec(path);
      if (factionPath && method === 'PATCH') return send(200, await factions.save(owner,body,factionPath[1]));
      if (centralMode && path === '/v1/decks') {
        if (method === 'GET') return send(200, sharedDecks.list(owner, url.searchParams.get('mine') === '1', url.searchParams.get('cursor') || '0'));
        if (method === 'POST') return send(201, await sharedDecks.publish(owner, body));
      }
      const deckPath = /^\/v1\/decks\/([0-9a-f-]{36})$/.exec(path);
      if (centralMode && deckPath) {
        if (method === 'GET') return send(200, sharedDecks.detail(deckPath[1], owner));
        if (method === 'DELETE') return send(200, await sharedDecks.withdraw(owner, deckPath[1]));
      }
      if (centralMode && method === 'POST' && path === '/v1/card-sync') return send(200, await catalog.sync(owner, body));
      if (matches) {
        const routed = await matches.handle({method, pathname: path, owner, body, clientBuild:Number(req.headers["x-frontline-client-build"] || 0)});
        if (routed) return send(routed.status, routed.body);
      }
      if (method === 'GET' && ['/health', '/v1/health'].includes(path)) return send(200, health());
      if (method === 'POST' && path === '/v1/catalog/updates') {
        const library = centralMode ? catalog.cards(owner) : service.cards(owner);
        return send(200, {...catalogUpdates(body, {cards:library.cards, lifecycle:library.lifecycle, keywords:service.keywords(null,owner).definitions, factions:factions.list(owner).factions}), health:health(), identity});
      }
      if (method === 'GET' && path === '/v1/keywords') return send(200, service.keywords(url.searchParams.get('registry_hash'), owner));
      if (method === 'GET' && path === '/v1/cards') return send(200, centralMode ? catalog.cards(owner) : service.cards(owner));
      if (method === 'POST' && path === '/v1/card-drafts') return send(201, await service.manualDraft(owner, body));
      if (method === 'POST' && path === '/v1/card-imports') return send(201, await service.manualDraft(owner, body, true));
      if (method === 'POST' && path === '/v1/cards') return send(201, await service.confirmCard(owner, body));
      if (method === 'POST' && path === '/v1/mechanism-reviews') return send(202, await service.createReview(owner, body));
      if (method === 'POST' && path === '/v1/card-generations') return send(202, await service.createGeneration(owner, body));
      if (method === 'POST' && path === '/v1/keyword-imports') return send(201, await service.keywordImport(owner, body));
      if (method === 'POST' && path === '/v1/keyword-proposals') return send(202, await service.createProposal(owner, body));
      let match;
      if ((match = /^\/v1\/card-generations\/([0-9a-f-]+)$/.exec(path))) {
        if (method === 'GET') return send(200, service.job(owner, match[1]));
        if (method === 'DELETE') return send(200, await service.cancelGeneration(owner, match[1]));
      }
      if ((match = /^\/v1\/cards\/([0-9a-f-]+)(\/revisions)?$/.exec(path))) {
        if (method === 'POST' && match[2]) return send(201, await service.confirmCard(owner, body, match[1]));
        if (method === 'GET' && !match[2]) {
          const revision = url.searchParams.get('revision');
          if (revision !== null && (!/^[1-9]\d*$/.test(revision) || !Number.isSafeInteger(Number(revision)))) fail('INVALID_REQUEST', '修订必须为正整数。', 400);
          return send(200, centralMode ? catalog.card(owner, match[1], revision ? Number(revision) : null) : service.card(owner, match[1], revision ? Number(revision) : null));
        }
      }
      if ((match = /^\/v1\/keyword-proposals\/([0-9a-f-]+)(?:\/(answers|confirm))?$/.exec(path))) {
        if (method === 'GET' && !match[2]) return send(200, service.proposal(owner, match[1]));
        if (method === 'DELETE' && !match[2]) return send(200, await service.withdrawProposal(owner, match[1]));
        if (method === 'POST' && match[2] === 'answers') return send(202, await service.answerProposal(owner, match[1], body));
        if (method === 'POST' && match[2] === 'confirm') return send(201, await service.confirmKeyword(owner, match[1], body));
      }
      fail('NOT_FOUND', '接口不存在。', 404);
    } catch (error) {
      closeUnreadRequest(req,res);
      const known = error instanceof ApiError;
      let diagnostic_number;
      const expectedInput=known&&(error.code==='RATE_LIMITED'&&error.message==='已有生成任务在运行，请等待或取消。'||error.code==='INVALID_REQUEST'&&error.message==='请填写修改要求或回答问题。');
      if(diagnosticContext && !expectedInput && (!known||error.status>=400))diagnostic_number=await store.transaction(state=>{const id=recordDiagnostic(state,{...diagnosticContext,code:known?error.code:'INTERNAL_ERROR',message:known?error.message:'服务内部操作失败',details:known?error.details??[]:[]});return state.diagnostics[id].number;}).catch(()=>undefined);
      send(known ? error.status : 500, {error: {...(diagnostic_number?{diagnostic_number}:{}),code: known ? error.code : 'INTERNAL_ERROR', message: known ? error.message : '服务内部操作失败，请重试。', retryable: known ? error.retryable : true, request_id, ...(known && error.details ? {details: error.details} : {})}});
    } finally { releaseBudget?.(); }
  };
  const server = tls ? https.createServer(tls, handler) : http.createServer(handler);
  const workshopPort = options.workshopPort ?? Number(process.env.WORKSHOP_PORT || 0);
  const workshopServer = workshopPort ? (tls ? https.createServer(tls, handler) : http.createServer(handler)) : null;
  server.requestTimeout = 15000; server.headersTimeout = 10000; server.maxHeadersCount = 30;
  if (workshopServer) { workshopServer.requestTimeout = 15000; workshopServer.headersTimeout = 10000; workshopServer.maxHeadersCount = 30; }
  const start = (s, port) => new Promise((resolve, reject) => { s.once('error', reject); s.listen(port, host, resolve); });
  return {server, workshopServer, service, auth, catalog, matches, host, protocol: tls ? 'https' : 'http', centralMode, async listen(port = options.port ?? Number(process.env.PORT || 8787)) { try { await start(server, port); if (workshopServer) await start(workshopServer, workshopPort); } catch (error) { server.close(); workshopServer?.close(); await service.close(); throw error; } return server.address(); }, async close() { const stopped = [server, workshopServer].filter(Boolean).map(s => { s.closeIdleConnections(); return new Promise(resolve => s.close(resolve)); }); await matches?.close(); imageWorkers.close(); await Promise.all(stopped); await service.close(); }};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const app = await createApp(); const address = await app.listen();
    console.log(`Card service listening on ${app.protocol}://${app.host}:${address.port}; mode ${app.centralMode ? 'central' : 'local'}; DeepSeek ${app.service.provider.configured ? 'configured' : 'not configured'}.`);
    let closing = false; const close = async () => { if (closing) return; closing = true; await app.close(); process.exit(0); };
    process.on('SIGINT', close); process.on('SIGTERM', close);
  } catch (error) { console.error(`Cannot start card service: ${error.message}`); process.exitCode = 1; }
}
