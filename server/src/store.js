import {initializeCardSeries} from './card_series.js';
import {resolveCard} from './derived_cards.js';
import {collectJobDiagnostic,initializeReports} from './diagnostics.js';
import {mkdir, readFile, open, rename, unlink} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {validateKeyword, registryHash, registryEntries, docsURL, builtinDefinitions} from './validation.js';

export class Store {
  constructor(directory) { this.directory = resolve(directory); this.file = join(this.directory, 'store.json'); this.queue = Promise.resolve(); }
  async init() {
    await mkdir(this.directory, {recursive: true});
    // Only one process may mutate this local store. Never reclaim a lock from a live process.
    const lockfile = join(this.directory, 'service.lock');
    try { this.lock = await open(lockfile, 'wx', 0o600); }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const old = Number(await readFile(lockfile, 'utf8').catch(() => '0'));
      let alive = false;
      if (old > 0) try { process.kill(old, 0); alive = true; } catch (e) { alive = e.code !== 'ESRCH'; }
      if (alive) throw new Error('Data directory is already locked by another process.');
      await unlink(lockfile); this.lock = await open(lockfile, 'wx', 0o600);
    }
    await this.lock.writeFile(String(process.pid)); this.lockfile = lockfile;
    try { this.state = JSON.parse(await readFile(this.file, 'utf8')); }
    catch (error) {
      if (error.code !== 'ENOENT') { await this.close(); throw new Error('Persistent store cannot be read. Refusing to replace it.'); }
      this.state = {version: 1, cards: {}, keywords: {}, catalogs: {}, drafts: {}, generations: {}, proposals: {}, idempotency: {}, limits: {}, editors: {}, identities: {}, sessions: {}, registration_limits: {}, sync_limits: {}};
      for (const name of ['core_blitz', 'core_guard']) {
        const definition = JSON.parse(await readFile(new URL(`examples/keywords/${name}.json`, docsURL), 'utf8'));
        const entry = {...validateKeyword(definition, {allowBuiltin: true}), registry_status: 'approved', approval_source: 'engine_builtin'};
        this.state.keywords[`${definition.id}@${definition.version}`] = entry;
      }
      this.state.catalogs[registryHash(this.state.keywords)] = registryEntries(this.state.keywords);
    }
    const armorDefinition = JSON.parse(await readFile(new URL('examples/keywords/standard_heavy_armor.json', docsURL), 'utf8'));
    const armorEntry = {...validateKeyword(armorDefinition), registry_status:'approved', approval_source:'engine_template'};
    const armorV2 = JSON.parse(await readFile(new URL('examples/keywords/standard_heavy_armor_v2.json', docsURL), 'utf8'));
    const armorV2Entry = {...validateKeyword(armorV2), registry_status:'approved', approval_source:'engine_template'};
    await this.transaction(state => {
      let newBuiltins=false;
      for(const definition of builtinDefinitions) {
        const key=`${definition.id}@${definition.version}`;
        if(!state.keywords[key]) {
          state.keywords[key]={...validateKeyword(definition,{allowBuiltin:true}),registry_status:'approved',approval_source:'engine_builtin'};
          newBuiltins=true;
        }
      }
      if(newBuiltins)state.catalogs[registryHash(state.keywords)]=registryEntries(state.keywords);
      if(!state.keywords['standard.heavy_armor@1']) {
        state.keywords['standard.heavy_armor@1']=armorEntry;
        state.catalogs[registryHash(state.keywords)]=registryEntries(state.keywords);
      }
      if(!state.keywords['standard.heavy_armor@2']) {
        state.keywords['standard.heavy_armor@2']=armorV2Entry;
        state.catalogs[registryHash(state.keywords)]=registryEntries(state.keywords);
      }
      initializeCardSeries(state);
      // Additive migration keeps pre-cloud local libraries and immutable definitions intact.
      state.identities ||= {}; state.sessions ||= {}; state.registration_limits ||= {}; state.sync_limits ||= {};
      state.accounts ||= {}; state.account_audit ||= [];
      state.shared_decks ||= {};
      state.emotes ||= {}; state.emote_loadouts ||= {};
      state.content_lifecycle ||= {cards:{},keywords:{},factions:{}};
      if(!state.diagnostics){state.diagnostics={};for(const job of Object.values(state.generations).slice(-1000))collectJobDiagnostic(state,job);}
      initializeReports(state);
      state.mechanism_components ||= {};
      state.card_art ||= {}; state.sound_assets ||= {};
      state.factions ||= {};
      state.match_index ||= {};
      for(const record of Object.values(state.match_index)) if(record.status==='active'){
        record.status='aborted';record.winner=3;record.reason='SERVER_RESTART';record.ended_at=new Date().toISOString();
      }
      for (const job of Object.values(state.generations)) if (['queued', 'running'].includes(job.status)) {
        job.status = 'failed'; job.error = {code: 'PROVIDER_UNAVAILABLE', message: '服务重启，未自动重发可能已计费的任务。', retryable: true};
      }
      for (const p of Object.values(state.proposals)) if (p.status === 'proposed') { p.status = 'rejected'; p.review_message = '服务重启，请新建提案；未自动重发模型调用。'; }
    });
    return this;
  }
  getCard(id, revision = null) {
    const card = resolveCard(this.state,id,revision);
    return card ? structuredClone(card) : null;
  }
  listKeywords() { return structuredClone(registryEntries(this.state.keywords)); }
  transaction(operation) {
    const result = this.queue.then(async () => {
      const next = structuredClone(this.state), value = await operation(next);
      const temp = join(this.directory, `store.${randomUUID()}.tmp`);
      let handle;
      try {
        handle = await open(temp, 'wx', 0o600); await handle.writeFile(JSON.stringify(next), 'utf8'); await handle.sync(); await handle.close(); handle = null;
        await rename(temp, this.file); this.state = next;
      } catch (error) { if (handle) await handle.close(); await unlink(temp).catch(() => {}); throw error; }
      return structuredClone(value);
    });
    this.queue = result.catch(() => {}); return result;
  }
  async close() { await this.queue; if (this.lock) { await this.lock.close(); this.lock = null; await unlink(this.lockfile).catch(() => {}); } }
}
