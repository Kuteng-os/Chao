import {walkEffects} from './validation.js';
import {hash,fail} from './codec.js';
import {premiseText} from './premises.js';

// Immutable, content-addressed components. Cards always store expanded bodies,
// so changing the catalog never changes an existing card or replay.
export function registerComponents(state,owner,definition){
  const entries=state.mechanism_components||={};const ids=[];
  const put=(kind,body,name)=>{
    const digest=hash({kind,body}),id=kind+'.'+digest.slice(0,32);
    if(!entries[id])entries[id]={id,version:1,kind,name,body:structuredClone(body),definition_hash:digest,owner_id:owner,created_at:new Date().toISOString(),uses:0};
    if(!ids.includes(id)){entries[id].uses++;ids.push(id);}
  };
  const premise=p=>{put('premise',p,premiseText(p));for(const child of p.items??[])premise(child);if(p.item)premise(p.item);};
  for(const card of [definition,...definition.tokens??[]])for(const a of card.abilities??[]){
    if(a.premise)premise(a.premise);
    // Token identifiers belong to their card and cannot form a global result.
    if(!walkEffects(a.effects).some(e=>e.token_id||e.on_kill_summon||e.token_ids?.length))put('result',a.effects,a.effects.map(e=>e.op).join(' + '));
  }
  return ids;
}
export function componentCatalog(state){return Object.values(state.mechanism_components??{}).sort((a,b)=>b.uses-a.uses||a.id.localeCompare(b.id)).map(({owner_id,...entry})=>structuredClone(entry));}
export function expandComponents(input,catalog){
  const def=structuredClone(input),entries=Array.isArray(catalog)?Object.fromEntries(catalog.map(e=>[e.id,e])):catalog??{};
  const lookup=(ref,kind)=>{
    if(!ref||typeof ref!=='object'||Object.keys(ref).sort().join()!=='id,version'||typeof ref.id!=='string'||ref.version!==1)fail('INVALID_COMPONENT_REF','前提或结果引用格式无效。',422);
    const entry=entries[ref.id];
    if(!entry||entry.kind!==kind||entry.version!==ref.version||hash({kind,body:entry.body})!==entry.definition_hash)fail('MISSING_COMPONENT','引用的前提或结果不存在，请重新选择。',422);
    return structuredClone(entry.body);
  };
  const expandPremise=(p,depth=1)=>{
    if(depth>4)fail('INVALID_PREMISE','条件最多嵌套4层。',422);
    if(p?.test==='ref'){
      if(Object.keys(p).sort().join()!=='id,test,version')fail('INVALID_COMPONENT_REF','条件引用包含未知字段。',422);
      return lookup({id:p.id,version:p.version},'premise');
    }
    if(p?.items)p.items=p.items.map(x=>expandPremise(x,depth+1));
    if(p?.item)p.item=expandPremise(p.item,depth+1);
    return p;
  };
  for(const card of [def,...def.tokens??[]])for(const ability of card.abilities??[]){
    if(ability.premise)ability.premise=expandPremise(ability.premise);
    if(ability.effects)ability.effects=ability.effects.flatMap(e=>{
      if(e.op!=='use_component')return [e];
      if(Object.keys(e).sort().join()!=='id,op,version')fail('INVALID_COMPONENT_REF','结果引用包含未知字段。',422);
      return lookup({id:e.id,version:e.version},'result');
    });
  }
  return def;
}
