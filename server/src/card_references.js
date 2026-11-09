import {hash,fail} from './codec.js';
import {walkEffects} from './validation.js';

// Published cards are snapshotted into the new card's token library. Matches never
// depend on a mutable global catalog or perform a live lookup during resolution.
export function referenceTemplates(state,source,history=[]){
 const text=source+'\n'+JSON.stringify(history),out=[];
 for(const versions of Object.values(state.cards??{})){
  const c=versions.at(-1),d=c?.definition;if(!d||!d.name||d.name.length<2||!text.includes(d.name)||d.kind==='hq'||d.veteran)continue;
  const expanded=c.compiled_program?.expanded_definition??d;
  const prefix='r_'+hash({id:c.card_id,revision:c.revision}).slice(0,12),ids=new Map((expanded.tokens??[]).map((t,i)=>[t.token_id,prefix+'_'+i]));
  const rewrite=body=>{const t=structuredClone(body);delete t.schema_version;delete t.ruleset_version;delete t.tokens;delete t.appearance;delete t.veteran;
   for(const a of t.abilities??[])for(const e of walkEffects(a.effects)){if(e.token_id&&ids.has(e.token_id))e.token_id=ids.get(e.token_id);if(e.on_kill_summon&&ids.has(e.on_kill_summon))e.on_kill_summon=ids.get(e.on_kill_summon);if(e.token_ids)e.token_ids=e.token_ids.map(x=>ids.get(x)??x);}
   return t;
  };
  // Use the already expanded program: no dangling keyword-local token ids.
  const token={...rewrite(expanded),token_id:prefix};
  out.push({card_id:c.card_id,revision:c.revision,name:d.name,token_id:prefix,templates:[token,...(expanded.tokens??[]).map(t=>({...rewrite(t),token_id:ids.get(t.token_id)}))]});
  if(out.length>=8)break;
 }
 return out;
}

export function freezeReferenceTemplates(card,catalog){
 const result=structuredClone(card),references=new Map((catalog??[]).flatMap(c=>c.templates.map(t=>[t.token_id,t])));
 const needed=new Set(),visit=id=>{if(!references.has(id)||needed.has(id))return;needed.add(id);for(const a of references.get(id).abilities??[])for(const e of walkEffects(a.effects)){if(e.token_id)visit(e.token_id);if(e.on_kill_summon)visit(e.on_kill_summon);for(const x of e.token_ids??[])visit(x);}};
 for(const body of [result,...(result.tokens??[])])for(const a of body.abilities??[])for(const e of walkEffects(a.effects)){if(e.token_id)visit(e.token_id);if(e.on_kill_summon)visit(e.on_kill_summon);for(const id of e.token_ids??[])visit(id);}
 result.tokens??=[];
 for(const id of needed){const at=result.tokens.findIndex(t=>t.token_id===id),token=structuredClone(references.get(id));if(at>=0)result.tokens[at]=token;else result.tokens.push(token);}
 if(result.tokens.length>12)fail('RULE_BUDGET_EXCEEDED','引用卡及其衍生形态合计超过12张，请减少引用。');
 return result;
}
