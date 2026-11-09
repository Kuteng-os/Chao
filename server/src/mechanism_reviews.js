import {resumeContext} from './diagnostics.js';
import {randomUUID} from 'node:crypto';
import {fail, hash, canonical} from './codec.js';
import {validateCardBlueprint} from './validation.js';

const own = (state,id,owner) => {
  const job=state.generations[id];
  if(!job || job.kind!=='mechanism-review' || job.owner_id!==owner) fail('NOT_FOUND','未找到机制复述。',404);
  return job;
};
const retryable = job => job && ['failed','unsupported','canceled'].includes(job.status);
const usable = (state,job) => (job.status==='awaiting_confirmation'||job.status==='confirmed'&&retryable(state.generations[job.compilation_id])) && (!job.child_generation_id||retryable(state.generations[job.child_generation_id]));
const string = (value,max) => typeof value==='string' && value.trim().length>0 && [...value].length<=max;
export async function createReview(service,owner,body) {
  const allowed=['report_number','request_id','kind','source_text','card_blueprint','suggested_name','parent_generation_id','review_hash','feedback','answers','editor_revision'];
  if(!body || Object.keys(body).some(k=>!allowed.includes(k)) || !['card','keyword'].includes(body.kind)) fail('INVALID_REQUEST','机制复述请求无效。',400);
  const result=await service.idem(owner,'mechanism-review',body,state=>{
    let source,blueprint=null,name=null,history=[],parent=null,round=1,conversation_id=randomUUID();
    if(body.report_number) {
      if(body.parent_generation_id||body.source_text||body.card_blueprint||body.feedback||body.answers?.length)fail('INVALID_REQUEST','恢复报错时不能覆盖原机制。',400);
      const resumed=resumeContext(state,owner,body.report_number);
      if(body.kind!==resumed.target_kind)fail('INVALID_REQUEST','制作类别不符。',400);
      source=resumed.source_text;blueprint=body.kind==='card'?validateCardBlueprint(resumed.card_blueprint,state.keywords):null;name=resumed.suggested_name;history=resumed.history;round=history.length+1;
    } else if(body.parent_generation_id) {
      parent=own(state,body.parent_generation_id,owner);
      if(!usable(state,parent) || parent.result.result_hash!==body.review_hash || parent.target_kind!==body.kind) fail('STALE_DRAFT','机制复述已变化，请重新加载。',409);
      if(['source_text','card_blueprint','suggested_name'].some(k=>Object.hasOwn(body,k))) fail('INVALID_REQUEST','继续讨论时请保留原始卡牌配置。',400);
      const answers=body.answers??[];
      if(!Array.isArray(answers)||answers.length>3||new Set(answers.map(a=>a?.question_id)).size!==answers.length) fail('INVALID_REQUEST','回答格式无效。',400);
      const feedback=body.feedback??'';
      if(feedback!==''&&!string(feedback,2000)) fail('INVALID_REQUEST','修改要求最多2000字。',400);
      const replies=answers.map(a=>{
        const q=parent.result.questions.find(q=>q.id===a?.question_id);
        if(!q||!string(a.answer,500)||Object.keys(a).some(k=>!['question_id','answer'].includes(k))) fail('INVALID_REQUEST','回答不属于当前复述。',400);
        return {question:q.question,answer:a.answer};
      });
      if(!feedback.trim()&&!replies.length) fail('INVALID_REQUEST','请填写修改要求或回答问题。',400);
      source=parent.source_text;blueprint=parent.card_blueprint;name=parent.suggested_name;
      history=[...parent.history,{formal_text:parent.result.formal_text,feedback,answers:replies,...(parent.compilation_id?{validation_error:state.generations[parent.compilation_id]?.error?.message??''}:{})}];
      round=parent.round+1;conversation_id=parent.conversation_id;
    } else {
      if(!string(body.source_text,2000)||body.review_hash||body.feedback||body.answers?.length) fail('INVALID_REQUEST','请填写机制要求。',400);
      source=body.source_text;
      if(body.kind==='card') blueprint=validateCardBlueprint(body.card_blueprint,state.keywords);
      else {if(!string(body.suggested_name,64)||body.card_blueprint)fail('INVALID_REQUEST','请填写词条名称。',400);name=body.suggested_name;}
    }
    if(Buffer.byteLength(canonical(history))>24576 || round>20)fail('INPUT_TOO_LONG','讨论过长，请整理机制后重新开始。',413);
    service.rate(state,owner);
    const job={generation_id:randomUUID(),conversation_id,round,editor_revision:parent?.editor_revision??body.editor_revision??1,status:'queued',owner_id:owner,kind:'mechanism-review',target_kind:body.kind,source_text:source,card_blueprint:blueprint,suggested_name:name,history,attempts:0,created_at:new Date().toISOString()};
    state.generations[job.generation_id]=job;
    if(parent)parent.child_generation_id=job.generation_id;
    return {generation_id:job.generation_id,status:job.status};
  });
  service.schedule(result.generation_id);return result;
}

// The confirmation binds to the exact visible interpretation and frozen editor fields.
// It is consumed within the same transaction that creates the compilation job.
export function consumeReview(state,owner,body,kind,blueprint=null) {
  if(body.mechanism_review===undefined)return null; // Compatibility for earlier API clients.
  const ref=body.mechanism_review;
  if(!ref||typeof ref!=='object'||Object.keys(ref).sort().join(',')!=='generation_id,result_hash')fail('INVALID_REQUEST','机制确认格式无效。',400);
  const job=own(state,ref.generation_id,owner);
  if(!usable(state,job)||job.target_kind!==kind||job.result.result_hash!==ref.result_hash)fail('STALE_DRAFT','机制复述已失效，请重新确认。',409);
  if(job.result.questions.length||job.result.missing_capabilities.length)fail('MECHANISM_NOT_READY','请先补充待确认细节或修改未支持的机制。',409);
  if(body.source_text!==job.result.formal_text||canonical(blueprint)!==canonical(job.card_blueprint)|| (kind==='keyword'&&body.suggested_name!==job.suggested_name))fail('STALE_DRAFT','机制或基础配置已变化，请重新复述。',409);
  job.status='confirmed';job.confirmed_at=new Date().toISOString();
  return {generation_id:job.generation_id,result_hash:ref.result_hash,formal_text:job.result.formal_text,source_text:job.source_text};
}

export const reviewResult = result => ({formal_text:result.formal_text,questions:result.questions,missing_capabilities:result.missing_capabilities,result_hash:hash(result)});
