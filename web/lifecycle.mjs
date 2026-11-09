import {esc,uuid} from './model.mjs';

export function createLifecycle({api,refresh,notify,afterDelete}) {
  const filters={cards:'active',keywords:'active',factions:'active'};
  let pending=null;
  const button=(text,action,attrs='',danger=false)=>`<button type="button" class="${danger?'danger-button':'secondary-button'} small" data-action="${action}" ${attrs}>${esc(text)}</button>`;
  const visible=(kind,item)=>filters[kind]==='all'||Boolean(item.archived)===(filters[kind]==='archived');
  function filter(kind) {return `<select data-content-filter="${kind}" aria-label="显示范围">${[['active','未归档'],['archived','已归档'],['all','全部']].map(([v,n])=>`<option value="${v}" ${filters[kind]===v?'selected':''}>${n}</option>`).join('')}</select>`;}
  function manage(kind,id,allowed) {return allowed?button('管理','content-manage',`data-kind="${kind}" data-id="${esc(id)}"`):'';}
  function draw() {
    const p=pending;if(!p)return;
    const linked=[...p.cards.map(c=>`${c.name}（v${c.revisions.join('、v')}）`),...p.decks.map(d=>`牌组：${d.name}`)];
    document.querySelector('#modal-body').innerHTML=`<h2>${esc(p.name)}</h2><p>${p.archived?'已归档':'未归档'} · ${p.versions} 个版本</p>
      <div class="actions">${button(p.archived?'恢复':'归档','content-toggle')}</div>
      <p class="hint">归档后默认隐藏，已有牌组仍可使用。</p>
      <section class="delete-section"><h3>彻底删除</h3><p>删除全部版本，无法恢复。已有对局记录保留。</p>
      ${linked.length?`<details open><summary>关联内容（${linked.length}）</summary><ul>${linked.map(n=>`<li>${esc(n)}</li>`).join('')}</ul></details>`:''}
      ${p.can_delete?`${p.decks.length?'<p>将从关联共享牌组中移除此卡，并撤回这些牌组。客户端同步后也会移除本地牌组中的此卡。</p>':''}<label class="form-field"><span>输入“${esc(p.name)}”确认删除</span><input id="delete-content-name" autocomplete="off" spellcheck="false"></label>${button('彻底删除','content-delete','disabled',true)}`:`<p class="notice-inline">${esc(p.blocked_reason)}</p>`}</section>`;
  }
  async function action(el) {
    if(!el.dataset.action.startsWith('content-'))return false;
    if(el.dataset.action==='content-manage') {
      pending=await api(`/v1/content/${el.dataset.kind}/${encodeURIComponent(el.dataset.id)}/preview`);
      draw();document.querySelector('#modal').showModal();return true;
    }
    if(!pending)return true;
    const p=pending,operation=el.dataset.action==='content-delete'?'delete':p.archived?'restore':'archive';
    if(operation==='delete'&&document.querySelector('#delete-content-name')?.value!==p.name)throw Error('请输入完整名称确认删除。');
    await api(`/v1/content/${p.kind}/${encodeURIComponent(p.id)}/${operation}`,{request_id:uuid(),expected_state:p.expected_state});
    pending=null;document.querySelector('#modal').close();
    if(operation==='delete')afterDelete(p.kind,p.id);
    await refresh();notify(operation==='delete'?'已彻底删除':operation==='restore'?'已恢复':'已归档');return true;
  }
  document.addEventListener('input',event=>{
    if(event.target.id!=='delete-content-name')return;
    const b=document.querySelector('[data-action="content-delete"]');if(b)b.disabled=!pending||event.target.value!==pending.name;
  });
  return {visible,filter,manage,action,setFilter:(kind,value)=>{if(Object.hasOwn(filters,kind)&&['active','archived','all'].includes(value))filters[kind]=value;}};
}
