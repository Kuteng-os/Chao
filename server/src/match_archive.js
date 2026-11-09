import {mkdir,open,readFile,rename,unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {fail} from './codec.js';

const metrics=['opening_draw','draw','search','create','generated_play','generated_deploy','burn','play','deploy','summon','attack','move','damage','hq_damage','unit_damage','overkill','damage_taken','armor_blocked','heal','kill','death','destroy','trigger','effect','counter_reveal','deployment_spent','operation_spent','kredits_gained'];
const empty=()=>Object.fromEntries(metrics.map(k=>[k,0]));
const refKey=r=>`${r.card_id}@${r.revision}`;
const percentage=(n,d)=>d?Math.round(n/d*10000)/100:null;
const interval=(wins,n)=>{if(!n)return null;const z=1.96,p=wins/n,b=1+z*z/n,c=(p+z*z/(2*n))/b,h=z*Math.sqrt(p*(1-p)/n+z*z/(4*n*n))/b;return [Math.max(0,c-h)*100,Math.min(1,c+h)*100].map(x=>Math.round(x*100)/100);};
export function summarizeMatch(record){
 const players=record.players.map((p,seat)=>({...p,seat,headquarters:record.headquarters?.[seat]??null,totals:{...empty(),turns:0,unused_kredits:0,fatigue:0},cards:[]}));
 const lookup=players.map((p,seat)=>{const m=new Map();for(const item of [...record.decks[seat],...(record.headquarters?.[seat]?[record.headquarters[seat]]:[])]){const key=refKey(item);if(!m.has(key)){const row={...item,copies:0,...empty(),effects:{}};m.set(key,row);p.cards.push(row);}m.get(key).copies++;}return m;});
 for(const e of record.events||[]){const p=players[e.owner];if(!p)continue;const row=lookup[e.owner].get(refKey(e.card_ref||{}))||p.cards.find(c=>c.definition_hash===e.definition_hash);const n=e.amount||0;
  if(e.kind==='turn_start')p.totals.turns++;
  const friendlyRemoval=['kill','destroy'].includes(e.kind)&&e.target_owner===e.owner;
  if(!friendlyRemoval&&e.kind in p.totals)p.totals[e.kind]+=n;
  if(!friendlyRemoval&&row&&e.kind in row&&typeof row[e.kind]==='number')row[e.kind]+=n;
  if(e.kind==='effect'&&row)row.effects[e.op]=(row.effects[e.op]||0)+1;
  if(e.kind==='damage'){
   // Enemy effective damage excludes overkill and friendly fire; all damage remains in the timeline.
   if(e.target_owner!==e.owner){const kind=e.hq?'hq_damage':'unit_damage';p.totals[kind]+=n;if(row)row[kind]+=n;}
   const extra=Math.max(0,(e.attempted||0)-n);p.totals.overkill+=extra;if(row)row.overkill+=extra;
  }
 }
 return {match_id:record.match_id,status:record.status,winner:record.winner,reason:record.reason,started_at:record.started_at,ended_at:record.ended_at,duration_seconds:record.duration_seconds,turns:record.turns,first_player:record.first_player,source:'server',ruleset:'frontline-1',telemetry_version:1,telemetry_truncated:!!record.telemetry_truncated,players};
}

export class MatchArchive{
 constructor(store){this.store=store;this.directory=join(store.directory,'matches');}
 async write(record){await mkdir(this.directory,{recursive:true});const file=join(this.directory,record.match_id+'.json'),temp=file+'.'+randomUUID()+'.tmp';try{const handle=await open(temp,'wx',0o600);try{await handle.writeFile(JSON.stringify(record));await handle.sync();}finally{await handle.close();}await rename(temp,file);}finally{await unlink(temp).catch(()=>{});}const summary=summarizeMatch(record);await this.store.transaction(state=>{state.match_index||={};state.match_index[record.match_id]=summary;});return summary;}
 deck(refs){return refs.map(ref=>{const c=this.store.getCard(ref.card_id,ref.revision);return {...ref,name:c.definition.name,kind:c.definition.kind,rarity:c.definition.rarity||'standard',cost:c.definition.cost,sin:c.definition.sin??null,faction_id:c.definition.faction_id||null};});}
 async start(room,refs){const players=room.players.map((owner_id,seat)=>({owner_id,main_sin:room.mainSins?.[seat]??'',display_name:this.store.state.identities[owner_id]?.display_name||'玩家'}));const record={match_id:room.id,players,decks:refs.map(r=>this.deck(r)),headquarters:(room.headquartersRefs??[null,null]).map(ref=>ref?this.deck([ref])[0]:null),events:[],started_at:new Date().toISOString(),ended_at:null,status:'active',winner:-1,first_player:room.views?.[0]?.first_player??0,turns:1,reason:null};room.archive=record;await this.write(record);}
 capture(room,result){if(!room.archive)return;const r=room.archive;r.first_player=result.first_player??r.first_player;r.turns=result.views[0].turn;const elapsed_ms=Math.max(0,Date.now()-Date.parse(r.started_at));r.events.push(...(result.telemetry||[]).map(e=>({...e,elapsed_ms})));r.telemetry_truncated||=result.telemetry_truncated===true;r.winner=result.winner;}
 async finish(room,reason){if(!room.archive)return;const r=room.archive;r.status=room.status;r.winner=room.winner;r.reason=reason||r.reason||((r.events.at(-1)?.kind==='concede')?'CONCEDE':room.status==='aborted'?'SERVER_ERROR':'HQ_DESTROYED');r.ended_at=new Date(room.endedAt||Date.now()).toISOString();r.duration_seconds=Math.max(0,Math.round((Date.parse(r.ended_at)-Date.parse(r.started_at))/1000));await this.write(r);room.archiveSaved=true;}
 entries(){return Object.values(this.store.state.match_index||{});}
 mine(owner,params=new URLSearchParams()){
  const offset=Number(params.get('cursor')||0);if(!Number.isSafeInteger(offset)||offset<0)fail('INVALID_REQUEST','分页位置无效。',400);
  const all=this.entries().filter(r=>r.players.some(p=>p.owner_id===owner)).sort((a,b)=>b.started_at.localeCompare(a.started_at));
  return {matches:all.slice(offset,offset+20).map(r=>{const seat=r.players.findIndex(p=>p.owner_id===owner);return {match_id:r.match_id,status:r.status,started_at:r.started_at,ended_at:r.ended_at,turns:r.turns,duration_seconds:r.duration_seconds||0,result:r.status==='aborted'?'中止':r.status!=='ended'?'进行中':r.winner===2?'平局':r.winner===seat?'胜利':'失败',opponent:r.players[1-seat].display_name,reason:r.reason};}),next_cursor:offset+20<all.length?String(offset+20):null,total:all.length};
 }
 async detail(owner,id){const entry=this.store.state.match_index?.[id];if(!entry||!entry.players.some(p=>p.owner_id===owner))fail('NOT_FOUND','对局记录不存在。',404);if(entry.status==='active')fail('MATCH_IN_PROGRESS','对局结束后可以查看详细记录。',409);let record;try{record=JSON.parse(await readFile(join(this.directory,id+'.json'),'utf8'));}catch{fail('NOT_FOUND','对局详情暂不可用。',404);}const seat=entry.players.findIndex(p=>p.owner_id===owner);return {...entry,players:entry.players.map(({owner_id,...p})=>p),local_player:seat,events:record.events||[]};}
 stats(params=new URLSearchParams(),owner=null){
  const days=Number(params.get('days')||30),minTurns=Number(params.get('min_turns')||0),minGames=Number(params.get('min_games')||1);
  if(![0,7,30,90].includes(days)||!Number.isSafeInteger(minTurns)||minTurns<0||minTurns>10000||!Number.isSafeInteger(minGames)||minGames<1||minGames>100000)fail('INVALID_REQUEST','统计筛选无效。',400);
  const since=days?Date.now()-days*86400000:0,all=this.entries().filter(r=>Date.parse(r.started_at)>=since&&(!owner||r.players.some(p=>p.owner_id===owner))),eligible=all.filter(r=>r.status==='ended'&&!r.telemetry_truncated&&r.turns>=minTurns);
  const rows=new Map(),factions=new Map();let wins=0,losses=0,draws=0,firstGames=0,firstWins=0,duration=0,turns=0;
  const totals={...empty(),turns:0,unused_kredits:0,fatigue:0};
  for(const match of eligible){duration+=match.duration_seconds||0;turns+=match.turns;for(const player of match.players){if(owner&&player.owner_id!==owner)continue;const win=match.winner===player.seat,draw=match.winner===2;if(win)wins++;else if(draw)draws++;else losses++;if(player.seat===match.first_player){firstGames++;if(win)firstWins++;}for(const key in totals)totals[key]+=player.totals[key]||0;
   const usedFactions=new Set();for(const card of player.cards){usedFactions.add(card.faction_id);if(params.get('faction_id')&&card.faction_id!==params.get('faction_id')||params.get('card_id')&&card.card_id!==params.get('card_id')||params.get('revision')&&String(card.revision)!==params.get('revision')||params.get('kind')&&card.kind!==params.get('kind'))continue;
    const key=refKey(card);if(!rows.has(key))rows.set(key,{card_id:card.card_id,revision:card.revision,definition_hash:card.definition_hash,name:card.name,kind:card.kind,rarity:card.rarity,cost:card.cost,faction_id:card.faction_id,games:0,wins:0,drawn_games:0,drawn_wins:0,played_games:0,played_wins:0,opening_games:0,opening_wins:0,copies:0,...empty(),effects:{}});const row=rows.get(key);row.games++;row.wins+=Number(win);row.copies+=card.copies;for(const m of metrics)row[m]+=card[m]||0;for(const [k,v] of Object.entries(card.effects))row.effects[k]=(row.effects[k]||0)+v;
    for(const [key,present] of [['drawn',card.draw+card.opening_draw+(card.search||0)>0],['played',card.play>0],['opening',card.opening_draw>0]])if(present){row[key+'_games']++;row[key+'_wins']+=Number(win);}
   }
   for(const id of usedFactions){if(!factions.has(id))factions.set(id,{faction_id:id,name:this.store.state.factions[id]?.name||'旧阵营',games:0,wins:0});const f=factions.get(id);f.games++;f.wins+=Number(win);}
  }}
  const cards=[...rows.values()].filter(r=>r.games>=minGames).map(r=>({...r,win_rate:percentage(r.wins,r.games),win_rate_ci95:interval(r.wins,r.games),drawn_win_rate:percentage(r.drawn_wins,r.drawn_games),played_win_rate:percentage(r.played_wins,r.played_games),opening_win_rate:percentage(r.opening_wins,r.opening_games),play_rate:percentage(r.play,r.draw+r.opening_draw+r.search),damage_per_play:r.play?Math.round((r.hq_damage+r.unit_damage)/r.play*100)/100:null})).sort((a,b)=>b.games-a.games||b.win_rate-a.win_rate);
  return {scope:owner?'personal':'public',days,matches:eligible.length,excluded:all.length-eligible.length,wins,losses,draws,win_rate:percentage(wins,wins+losses+draws),first_player_win_rate:percentage(firstWins,firstGames),average_turns:eligible.length?Math.round(turns/eligible.length*10)/10:0,average_duration_seconds:eligible.length?Math.round(duration/eligible.length):0,totals,cards,factions:[...factions.values()].map(f=>({...f,win_rate:percentage(f.wins,f.games)})),notes:['仅统计已结束的服务器对战；演练、局域网及异常中止不计入。','每张牌按 UUID 和版本分别统计；携带样本按玩家局数计算。','打出后胜率是相关性指标，存在费用、牌组和存活时间偏差。','伤害按实际扣除生命计算；衍生单位的贡献归属于生成它的卡牌。']};
 }
}
