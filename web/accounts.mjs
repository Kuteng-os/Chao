import {esc} from './model.mjs';

export function createAccounts({api, getSession, acceptSession, notify, resumeReport}) {
  let mode='login', registration='open';
  const node=document.querySelector('#account'),modal=document.querySelector('#modal'),body=document.querySelector('#modal-body');
  const button=(title,action,extra='')=>`<button type="button" class="secondary-button small" data-account-action="${action}" ${extra}>${esc(title)}</button>`;
  const field=(title,name,type='text',autocomplete='',extra='')=>`<label class="form-field"><span>${title}</span><input name="${name}" type="${type}" required autocomplete="${autocomplete}" ${extra}></label>`;
  const passwordField=(title,name,autocomplete)=>field(title,name,'password',autocomplete,'minlength="10" maxlength="128"');
  const passwordForm=()=>`<form data-account-form="password">${field('当前密码','current_password','password','current-password','maxlength="128"')}${passwordField('新密码','new_password','new-password')}${passwordField('确认新密码','confirm_password','new-password')}<button class="primary-button">保存密码</button></form>`;
  const show=html=>{body.innerHTML=html;if(!modal.open)modal.showModal();};
  function render() {
    const s=getSession();
    if(s?.must_change_password){node.innerHTML=`<p>${esc(s.username)}</p><h3>修改初始密码</h3>${passwordForm()}${button('退出登录','logout')}`;return;}
    if(s){
      node.innerHTML=`<p>${esc(s.username??s.display_name)}${s.role==='admin'?'<span class="tag account-role">管理员</span>':''}</p>${s.username?`<div class="actions">${button('修改密码','password')}${button('我的报错','my-reports')}${button('站内信','inbox','id="inbox-button"')}${s.role==='admin'?button('账号管理','admin')+button('报错记录','diagnostics'):''}${button('退出登录','logout')}</div>`:`<details><summary>绑定账号</summary><form data-account-form="link">${signupFields()}<button class="primary-button">绑定账号</button></form></details>${button('退出登录','logout')}`}`;
      refreshUnread();return;
    }
    node.innerHTML=`<form data-account-form="${mode}">${mode==='register'?signupFields():field('账号','username','text','username','maxlength="32"')+field('密码','password','password','current-password','maxlength="128"')}<button class="primary-button">${mode==='register'?'注册并登录':'登录'}</button></form>${registration==='open'?button(mode==='login'?'注册账号':'返回登录',mode==='login'?'register':'login'):''}`;
  }
  function signupFields(){return field('账号','username','text','username','minlength="2" maxlength="32"')+passwordField('密码（10～128 字符）','password','new-password')+passwordField('确认密码','confirm_password','new-password');}
  async function logout(){try{await api('/v1/logout',{});}catch(e){if(e.status!==401)throw e;}mode='login';modal.close();body.replaceChildren();await acceptSession(null);notify('已退出登录');}
  let errorRecords=[];
  async function diagnostics(){const result=await api('/v1/admin/diagnostics');errorRecords=result.items;show(`<h2>报错记录</h2><div class="actions">${button('刷新','diagnostics')}${button('下载记录','diagnostics-export')}</div><p>${result.open} 项待处理</p><div class="diagnostic-list">${result.items.map(r=>`<details><summary>${esc(r.number??'')} · ${esc(r.card_name||r.code)} · ${r.count} 次 · ${r.status==='resolved'?'已处理':r.code==='NEEDS_CLARIFICATION'?'待补充规则':'待处理'}</summary><p>${esc(r.last_seen)} · ${esc(r.stage)}</p><p class="rules">${esc(r.source_text)}</p><p class="rules notice-inline">${esc(r.message)}</p>${r.resolution?`<p class="rules">${esc(r.resolution)}</p>`:''}${r.card_definition?`<details><summary>报错时的卡牌 JSON</summary><pre>${esc(JSON.stringify(r.card_definition,null,2))}</pre></details>`:''}${r.details.map(d=>`<p>${esc(d.path)} ${esc(d.message)}</p>`).join('')}${r.status==='open'?button('标记已处理','diagnostic-resolve',`data-id="${r.id}"`):''}</details>`).join('')||'<p>暂无报错</p>'}</div>`);}
  async function refreshUnread(){const identity=getSession()?.owner_id;if(!identity)return;try{const r=await api('/v1/inbox');if(getSession()?.owner_id!==identity)return;const b=document.querySelector('#inbox-button');if(b)b.textContent='站内信'+(r.unread?' · '+r.unread:'');}catch{}}
  async function myReports(number=''){
    const r=await api('/v1/diagnostics'+(number?'?number='+encodeURIComponent(number):''));
    show(`<h2>我的报错</h2><div class="report-search"><input id="report-number" aria-label="报错编号" placeholder="CZ-000001" value="${esc(number)}" maxlength="32">${button('查询','report-query')}${button('全部','my-reports')}</div><div class="diagnostic-list">${r.items.map(x=>`<article class="report-item"><h3>${esc(x.number)} <span class="tag">${x.status==='resolved'?'已解决':'处理中'}</span></h3><p>${esc(x.card_name||x.code)}</p><p class="rules">${esc(x.message)}</p>${x.resolution?`<p class="report-resolution">${esc(x.resolution_version??'')} ${esc(x.resolution)}</p>`:''}${x.card_definition?`<details><summary>报错时的卡牌 JSON</summary><pre>${esc(JSON.stringify(x.card_definition,null,2))}</pre></details>`:''}${x.can_resume?button('继续完善','resume-report',`data-number="${esc(x.number)}"`):x.status==='resolved'?'<p>请返回原草稿，重新校验并保存。</p>':''}</article>`).join('')||'<p>暂无报错</p>'}</div>`);
  }
  async function showInbox(){const r=await api('/v1/inbox');show(`<h2>站内信</h2>${button('刷新','inbox')}<div class="diagnostic-list">${r.items.map(m=>`<article class="report-item"><h3>${m.read_at?'':'● '}${esc(m.title)}</h3><p class="rules">${esc(m.body)}</p><p>${esc(m.version)} · ${esc(new Date(m.created_at).toLocaleString())}</p><div class="actions">${button('查看处理状态','report-open',`data-number="${esc(m.report_number)}"`)}${m.read_at?'':button('标为已读','message-read',`data-id="${esc(m.id)}"`)}</div></article>`).join('')||'<p>暂无消息</p>'}</div>`);await refreshUnread();}
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)refreshUnread();});
  setInterval(()=>{if(!document.hidden)refreshUnread();},60000);
  async function adminList(){const result=await api('/v1/admin/accounts');show(`<h2>账号管理</h2><div class="account-list">${result.accounts.map(a=>`<div class="account-row"><span>${esc(a.username)}${a.role==='admin'?' · 管理员':''}</span>${a.owner_id===getSession().owner_id?'':button('重置密码','reset-confirm',`data-owner="${esc(a.owner_id)}" data-username="${esc(a.username)}"`)}</div>`).join('')}</div>`);}
  document.addEventListener('submit',async event=>{
    const form=event.target,type=form.dataset.accountForm;if(!type)return;
    event.preventDefault();const submit=form.querySelector('button');if(submit.disabled)return;submit.disabled=true;
    try {
      const data=Object.fromEntries(new FormData(form));let result;
      if(type==='password'){
        if(data.new_password!==data.confirm_password)throw new Error('两次输入的新密码不一致。');
        result=await api('/v1/account/password',{current_password:data.current_password,new_password:data.new_password});
      }else{
        if(type!=='login'&&data.password!==data.confirm_password)throw new Error('两次输入的密码不一致。');
        result=await api(type==='link'?'/v1/account/link':`/v1/accounts/${type}`,{username:data.username,password:data.password});
      }
      form.reset();modal.close();body.replaceChildren();await acceptSession(result);
      notify(result.must_change_password?'请修改初始密码':type==='password'?'密码已更新':type==='link'?'账号已绑定':'已登录');
    }catch(e){notify(e.message,true);}finally{submit.disabled=false;}
  });
  document.addEventListener('click',async event=>{
    const el=event.target.closest('[data-account-action]');if(!el||el.disabled)return;el.disabled=true;
    try {
      switch(el.dataset.accountAction){
        case 'login':case 'register':mode=el.dataset.accountAction;render();break;
        case 'logout':await logout();break;
        case 'password':show('<h2>修改密码</h2>'+passwordForm());break;
        case 'my-reports':await myReports();break;
        case 'report-query':await myReports(body.querySelector('#report-number').value);break;
        case 'report-open':await myReports(el.dataset.number);break;
        case 'inbox':await showInbox();break;
        case 'message-read':await api('/v1/inbox/read',{id:el.dataset.id});await showInbox();break;
        case 'resume-report':modal.close();await resumeReport(el.dataset.number);break;
        case 'diagnostics':await diagnostics();break;
        case 'diagnostic-resolve':await api('/v1/admin/diagnostics/resolve',{id:el.dataset.id});await diagnostics();break;
        case 'diagnostics-export':{const u=URL.createObjectURL(new Blob([JSON.stringify(errorRecords,null,2)],{type:'application/json'})),a=document.createElement('a');a.href=u;a.download='巢战-报错记录-'+new Date().toISOString().slice(0,10)+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(u),1000);break;}
        case 'admin':await adminList();break;
        case 'reset-confirm':show(`<h2>重置 ${esc(el.dataset.username)} 的密码</h2><p>此账号将在所有设备退出，重新登录后需修改临时密码。</p>${button('确认重置','reset',`data-owner="${esc(el.dataset.owner)}"`)}`);break;
        case 'reset':{
          const r=await api('/v1/admin/password-reset',{owner_id:el.dataset.owner});
          show(`<h2>${esc(r.username)}</h2><label class="form-field"><span>临时密码（仅显示一次）</span><input id="temporary-password" readonly value="${esc(r.temporary_password)}" autocomplete="off"></label><p>请将密码交给账号本人。</p>`);break;
        }
      }
    }catch(e){if(modal.open){let status=body.querySelector('#account-action-error');if(!status){status=document.createElement('p');status.id='account-action-error';status.setAttribute('role','alert');body.prepend(status);}status.textContent=e.message;}else notify(e.message,true);}finally{el.disabled=false;}
  });
  modal.addEventListener('close',()=>body.replaceChildren());
  return {render,logout,async init(){const o=await api('/v1/account-options');registration=o.registration;render();}};
}
