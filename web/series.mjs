import {esc,uuid} from './model.mjs';
const valid=n=>Number.isSafeInteger(n)&&n>=1&&n<=9999;
const fallback=n=>n===1?'第一期':n===2?'第二期':`第${n}期`;
export function seriesEntries(catalog={},records=[]){
 if(typeof catalog==='number')catalog={current:catalog};
 const ids=[...new Set([1,2,catalog.current,...(catalog.available??[]),...records.map(r=>r.series)].filter(valid))].sort((a,b)=>a-b);
 return ids.map(id=>({id,name:catalog.entries?.find(e=>e.id===id)?.name??fallback(id)}));
}
export const seriesName=(id,catalog={})=>seriesEntries(catalog).find(e=>e.id===id)?.name??fallback(id);
export const seriesOptions=(catalog,value)=>seriesEntries(catalog).map(e=>`<option value="${e.id}" ${e.id===Number(value)?'selected':''}>${esc(e.name)}</option>`).join('');

export function createSeriesUI({api,refresh,notify,getCatalog,getCards,getSession}){
 const $=s=>document.querySelector(s);
 let pending=null,busy=false;
 const batchPending=new Map();
 const editable=()=>getCards().filter(r=>r.can_edit&&!r.derived_from);
 function toolbar(value=''){
  if(!getSession())return '';
  const admin=getSession().role==='admin';
  return `${admin?`<button type="button" class="ghost-button small" data-action="series-manage" data-id="${esc(value)}">${value?'改名':'管理卡包'}</button>`:''}${editable().length?`<button type="button" class="ghost-button small" data-action="series-pick" data-id="${esc(value)}">放入卡牌</button>`:''}`;
 }
 const show=html=>{$('#modal-body').innerHTML=html+'<p id="series-error" role="alert"></p>';if(!$('#modal').open)$('#modal').showModal();};
 function manager(focusId){
  const c=getCatalog();
  show(`<section class="series-manager" data-series-revision="${c.revision}"><h2>管理卡包</h2><p class="hint">卡包仅用于归类与筛选，不出现在卡牌名称或卡面上。修改默认卡包只影响之后创建的新卡。</p><div class="series-list">${seriesEntries(c).map(e=>`<div class="series-row"><label class="form-field"><span>${e.id===c.current?'新卡默认卡包':'卡包名称'}</span><input data-series-name="${e.id}" value="${esc(e.name)}" maxlength="32" aria-label="卡包 ${e.id} 名称"></label><div class="actions"><button data-action="series-rename" data-id="${e.id}" class="secondary-button small">保存名称</button>${e.id===c.current?'<span class="tag">当前默认</span>':`<button data-action="series-current" data-id="${e.id}" class="ghost-button small">设为新卡默认</button>`}</div></div>`).join('')}</div><div class="series-row"><label class="form-field"><span>新增卡包</span><input id="series-new-name" maxlength="32" placeholder="例如：都市序章"></label><button data-action="series-create" class="primary-button">新增卡包</button></div></section>`);
  const name=$(`[data-series-name="${Number(focusId)}"]`);if(name){name.focus();name.select();}
 }
 function picker(id,selected=[]){
  const target=valid(Number(id))?Number(id):getCatalog().current;
  show(`<section class="series-picker"><h2>放入卡牌</h2><label class="form-field"><span>放入卡包</span><select id="series-pick-target">${seriesOptions(getCatalog(),target)}</select></label><p class="hint">选择已有卡牌归入此卡包，其历史版本和衍生卡同步归类。每张牌只属于一个卡包。</p><input type="search" id="series-pick-search" aria-label="搜索待归类卡牌" placeholder="搜索卡名或卡包"><div class="actions"><button class="ghost-button small" data-action="series-pick-all">全选搜索结果</button><button class="ghost-button small" data-action="series-pick-clear">清空选择</button><span id="series-pick-count" role="status"></span></div><div class="series-pick-list">${editable().map(r=>`<label class="series-pick-card" data-pick-name="${esc((r.definition.name+' '+seriesName(r.series??1,getCatalog())).toLocaleLowerCase())}"><input type="checkbox" data-series-pick="${esc(r.card_id)}" data-current-series="${r.series??1}" ${selected.includes(r.card_id)?'checked':''}><span><strong>${esc(r.definition.name)}</strong><small>${esc(seriesName(r.series??1,getCatalog()))}${r.archived?' · 已归档':''}</small></span><small data-pick-existing hidden>已在此卡包</small></label>`).join('')}</div><button class="primary-button" data-action="series-pick-save">放入所选卡牌</button></section>`);
  updatePicker();
 }
 function updatePicker(){
  const target=$('#series-pick-target');if(!target)return;
  const q=$('#series-pick-search').value.trim().toLocaleLowerCase();
  document.querySelectorAll('[data-series-pick]').forEach(input=>{const label=input.closest('label');label.hidden=!label.dataset.pickName.includes(q);input.disabled=input.dataset.currentSeries===target.value;if(input.disabled)input.checked=false;label.querySelector('[data-pick-existing]').hidden=!input.disabled;});
  const n=document.querySelectorAll('[data-series-pick]:checked').length;$('#series-pick-count').textContent=`已选 ${n} 张`; $('[data-action="series-pick-save"]').disabled=!n;
 }
 function update(event){if(event.target.id?.startsWith('series-pick-')||event.target.dataset.seriesPick){updatePicker();return true;}return false;}
 async function savePicked(){
  const target=Number($('#series-pick-target').value),ids=[...document.querySelectorAll('[data-series-pick]:checked')].map(e=>e.dataset.seriesPick);
  if(!ids.length)return;
  busy=true;let success=0;const failed=[];
  const controls=[...$('#modal-body').querySelectorAll('button,input,select')];controls.forEach(e=>e.disabled=true);
  const preventCancel=e=>e.preventDefault();$('#modal').addEventListener('cancel',preventCancel);
  try{
   for(const id of ids){
    const record=getCards().find(r=>r.card_id===id),body={series:target,expected_series:record.series??1},stamp=JSON.stringify({id,body});
    if(!batchPending.has(stamp))batchPending.set(stamp,{...body,request_id:uuid()});
    try{await api(`/v1/cards/${id}/series`,batchPending.get(stamp),'PATCH');batchPending.delete(stamp);success++;}
    catch(error){failed.push({id,message:`${record.definition.name}：${error.message}`});}
    $('#series-pick-count').textContent=`已处理 ${success+failed.length} / ${ids.length} 张`;
   }
   await refresh();
   if(failed.length){picker(target,failed.map(f=>f.id));$('#series-error').textContent=`已放入 ${success} 张，${failed.length} 张未完成。${failed.map(f=>f.message).join('；')}`;}
   else{$('#modal').close();notify(`已将 ${success} 张卡牌放入“${seriesName(target,getCatalog())}”。`);}
  }finally{$('#modal').removeEventListener('cancel',preventCancel);controls.forEach(e=>e.disabled=false);busy=false;}
 }
 function assignment(id){
  const entry=getCards().find(r=>r.card_id===id),record=entry?.derived_from?getCards().find(r=>r.card_id===entry.derived_from.card_id):entry;
  if(!record?.can_edit)throw new Error('只能由作者或管理员修改卡包。');
  show(`<section data-series-card="${esc(record.card_id)}" data-original-series="${record.series??1}"><h2>修改所属卡包</h2><p>${esc(record.definition.name)}</p><label class="form-field"><span>所属卡包</span><select id="series-assignment">${seriesOptions(getCatalog(),record.series??1)}</select></label><p class="hint">所有版本和衍生卡一同归类，不改动卡牌效果或牌组。</p><button data-action="series-assign" class="primary-button">保存卡包</button></section>`);
 }
 async function action(el){
  const a=el.dataset.action;if(!a?.startsWith('series-'))return false;
  if(busy)return true;
  try{
   if(a==='series-manage'){if(getSession()?.role!=='admin')throw new Error('只有管理员可以管理卡包。');manager(el.dataset.id);return true;}
   if(a==='series-card'){assignment(el.dataset.id);return true;}
   if(a==='series-pick'){picker(el.dataset.id);return true;}
   if(a==='series-pick-all'||a==='series-pick-clear'){document.querySelectorAll('[data-series-pick]').forEach(e=>{if(!e.disabled&&(a==='series-pick-clear'||!e.closest('label').hidden))e.checked=a==='series-pick-all';});updatePicker();return true;}
   if(a==='series-pick-save'){await savePicked();return true;}
   busy=true;el.disabled=true;
   let path='/v1/admin/card-series',method='POST',body;
   if(a==='series-assign'){
    const panel=$('[data-series-card]');path=`/v1/cards/${panel.dataset.seriesCard}/series`;method='PATCH';body={series:Number($('#series-assignment').value),expected_series:Number(panel.dataset.originalSeries)};
   }else{
    body={action:({'series-create':'create','series-rename':'rename','series-current':'set_current'})[a],expected_revision:Number($('[data-series-revision]').dataset.seriesRevision)};
    if(a==='series-create')body.name=$('#series-new-name').value;
    else{body.series=Number(el.dataset.id);if(a==='series-rename')body.name=$(`[data-series-name="${body.series}"]`).value;}
   }
   const stamp=JSON.stringify({path,body});if(pending?.stamp!==stamp)pending={stamp,body:{...body,request_id:uuid()}};
   await api(path,pending.body,method);pending=null;
   await refresh();
   if(a==='series-assign'){$('#modal').close();notify('所属卡包已更新，衍生卡同步生效。');}else{manager();notify('卡包已保存。');}
  }catch(error){const target=$('#series-error');if(target)target.textContent=error.message;else notify(error.message,true);}
  finally{busy=false;el.disabled=false;}
  return true;
 }
 return {action,update,toolbar};
}
