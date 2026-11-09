import {hash,fail} from './codec.js';
import {isAdmin} from './account_roles.js';
const clean=v=>String(v??'').replace(/(?:Bearer\s+)[\w.\-]+/gi,'[令牌已隐藏]').replace(/\bsk-[\w-]+/gi,'[密钥已隐藏]').replace(/(password|api[_-]?key|密码)\s*[:=：]\s*\S+/gi,'$1=[已隐藏]').slice(0,4000);
export function initializeReports(state){
  state.report_sequence=Math.max(state.report_sequence??0,...Object.values(state.diagnostics??{}).map(r=>Number(r.number?.slice(3))||0));state.inbox??={};
  for(const item of Object.values(state.diagnostics??{}).sort((a,b)=>a.first_seen.localeCompare(b.first_seen)||a.id.localeCompare(b.id))){
    if(!item.number)item.number='CZ-'+String(++state.report_sequence).padStart(6,'0');
    else state.report_sequence=Math.max(state.report_sequence,Number(item.number.slice(3))||0);
  }
}
export function recordDiagnostic(state,{stage,code,message,owner='',source='',card_name='',details=[],conversation_id='',generation_id='',definition=null}){
  const items=state.diagnostics||={};
  const safe={stage:clean(stage).slice(0,80),code:clean(code).slice(0,80),message:clean(message),owner_id:owner,source_text:clean(source),card_name:clean(card_name).slice(0,64)};
  const category=code==='NEEDS_CLARIFICATION'?'clarification':['INVALID_SCHEMA','SEMANTIC_VALIDATION_FAILED','REVISION_CONFLICT','INVALID_KEYWORD_PARAMS'].includes(code)?'validation':code==='MISSING_CAPABILITY'?'capability':code?.startsWith('PROVIDER_')||code==='GENERATION_TIMEOUT'?'provider':'fault';
  const id=hash(safe).slice(0,32),now=new Date().toISOString();
  const entry=items[id]||={id,...safe,count:0,first_seen:now};
  initializeReports(state);
  if(entry.status==='resolved'){
    if(entry.resolution)entry.resolution_history=[...(entry.resolution_history??[]),{resolution:entry.resolution,resolution_version:entry.resolution_version,resolved_at:entry.resolved_at}].slice(-20);
    delete entry.resolution;delete entry.resolution_version;delete entry.resolved_at;
  }
  Object.assign(entry,{category,last_seen:now,status:'open',count:entry.count+1,conversation_id,generation_id,details:details.slice(0,8).map(d=>({code:clean(d.code).slice(0,80),path:clean(d.path).slice(0,160),message:clean(d.message)}))});
  // Keep only the submitted card, never headers, credentials or unrelated request data.
  if(definition&&typeof definition==='object'&&!Array.isArray(definition)){
    const allowed=['schema_version','ruleset_version','name','flavor_text','kind','unit_class','cost','operation_cost','attack','health','keywords','play_target','abilities','tokens','appearance','rarity','sin','faction_id','media','veteran','draw_rule','counter_trigger','deck_building','damage_bonuses','cost_reduction','cost_surcharge'];
    const snapshot=Object.fromEntries(allowed.filter(k=>Object.hasOwn(definition,k)).map(k=>[k,definition[k]]));
    const text=JSON.stringify(snapshot,(k,v)=>typeof v==='string'?clean(v):v);
    if(Buffer.byteLength(text)<=32768)entry.card_definition=JSON.parse(text);
  }
  const ordered=Object.values(items).sort((a,b)=>b.last_seen.localeCompare(a.last_seen));
  for(const item of ordered.slice(1000))delete items[item.id];
  return id;
}
export function collectJobDiagnostic(state,job){
  const missing=job.result?.missing_capabilities??job.result?.reasons??[];
  const questions=job.result?.questions??[];
  if(!missing.length&&questions.length&&!job.error)return; // A normal clarification is conversation, not an incident.
  if(job.status==='failed'||job.status==='unsupported'||missing.length||questions.length){
    job.diagnostic_id=recordDiagnostic(state,{stage:job.kind,code:job.error?.code??(missing.length?'MISSING_CAPABILITY':'NEEDS_CLARIFICATION'),message:job.error?.message??[...missing,...questions.map(q=>q.question)].join('\n'),details:job.error?.details??[],owner:job.owner_id,source:job.source_text,card_name:job.card_blueprint?.name,conversation_id:job.conversation_id,generation_id:job.generation_id});
    job.diagnostic_number=state.diagnostics[job.diagnostic_id].number;
  }
}
export function diagnosticList(state,owner){
  if(!isAdmin(state,owner))fail('FORBIDDEN','仅管理员可查看报错记录。',403);
  const items=Object.values(state.diagnostics??{}).sort((a,b)=>b.last_seen.localeCompare(a.last_seen));
  return {items,open:items.filter(x=>x.status==='open').length};
}
export function resolveDiagnostic(state,owner,id,options={}){
  diagnosticList(state,owner);const item=state.diagnostics?.[id];if(!item)fail('NOT_FOUND','报错记录不存在。',404);
  return markResolved(state,item,options);
}
export function markResolved(state,item,{resolution='问题已处理，请继续完善并重新校验。',version=''}={}){
  if(item.status==='resolved')return {ok:true,number:item.number};
  initializeReports(state);
  if(typeof resolution!=='string'||resolution.length>2000||typeof version!=='string'||version.length>32)fail('INVALID_REQUEST','处理说明无效。',400);
  item.status='resolved';item.resolved_at=new Date().toISOString();item.resolution=clean(resolution);item.resolution_version=version;
  if(item.owner_id){
    const id=hash(item.id+':'+item.count+':'+item.resolved_at).slice(0,32);
    state.inbox[id]={id,owner_id:item.owner_id,report_number:item.number,title:`报错 ${item.number} 已解决`,body:item.resolution,version,created_at:item.resolved_at,read_at:null};
  }
  return {ok:true,number:item.number};
}
const publicReport=r=>Object.fromEntries(['number','card_name','stage','code','message','source_text','details','count','status','first_seen','last_seen','resolved_at','resolution','resolution_version','card_definition'].filter(k=>Object.hasOwn(r,k)).map(k=>[k,r[k]]));
export function ownReport(state,owner,number){
  const item=Object.values(state.diagnostics??{}).find(r=>r.number===String(number).trim().toUpperCase()&&r.owner_id===owner);
  if(!item)fail('NOT_FOUND','未找到属于当前账号的报错编号。',404);
  return item;
}
export function authorReports(state,owner,number=''){
  const items=number?[ownReport(state,owner,number)]:Object.values(state.diagnostics??{}).filter(r=>r.owner_id===owner).sort((a,b)=>b.last_seen.localeCompare(a.last_seen));
  return {items:items.map(r=>{const job=state.generations?.[r.generation_id];return {...publicReport(r),can_resume:r.status==='resolved'&&!!(job?.card_blueprint||job?.kind==='mechanism-review'&&job?.target_kind==='keyword'&&job?.suggested_name)};})};
}
export function inbox(state,owner){
  const items=Object.values(state.inbox??{}).filter(m=>m.owner_id===owner).sort((a,b)=>b.created_at.localeCompare(a.created_at)).map(({owner_id,...m})=>m);
  return {items,unread:items.filter(m=>!m.read_at).length};
}
export function readMessage(state,owner,id){
  const m=state.inbox?.[id];if(!m||m.owner_id!==owner)fail('NOT_FOUND','消息不存在。',404);
  m.read_at??=new Date().toISOString();return {ok:true};
}
export function resumeContext(state,owner,number){
  const report=ownReport(state,owner,number);
  if(report.status!=='resolved')fail('NOT_READY','此问题尚未处理完成。',409);
  const old=state.generations?.[report.generation_id];
  if(!old?.card_blueprint&&!(old?.kind==='mechanism-review'&&old?.target_kind==='keyword'&&old?.suggested_name))fail('NOT_FOUND','原制作会话不可恢复，请打开原草稿重新校验。',404);
  // Resume the latest round of this owner's conversation, preserving answers.
  const latest=Object.values(state.generations).filter(j=>j.owner_id===owner&&j.conversation_id===old.conversation_id&&j.kind===old.kind).sort((a,b)=>b.round-a.round)[0]??old;
  return {number:report.number,source_text:latest.source_text,card_blueprint:structuredClone(latest.card_blueprint??null),suggested_name:latest.suggested_name??null,history:structuredClone(latest.history??[]),target_kind:latest.target_kind??'card'};
}
