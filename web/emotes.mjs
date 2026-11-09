import {esc} from './model.mjs';
import {createBattlePreview,DEFAULT_SCALE} from './emote_preview.mjs';

// Atlas frames use exactly the same timing and transparent pixels as the client.
export function animateEmote(canvas,e){
  const image=new Image();let frame=0,elapsed=0,last=0,raf=0;
  canvas.width=e.frame_width;canvas.height=e.frame_height;
  const context=canvas.getContext('2d');
  const draw=()=>{context.clearRect(0,0,canvas.width,canvas.height);context.drawImage(image,(frame%e.columns)*e.frame_width,Math.floor(frame/e.columns)*e.frame_height,e.frame_width,e.frame_height,0,0,canvas.width,canvas.height);};
  const tick=t=>{if(!canvas.isConnected)return;elapsed+=last?Math.min(t-last,200):0;last=t;while(elapsed>=e.durations[frame]){elapsed-=e.durations[frame];frame=(frame+1)%e.durations.length;}draw();raf=requestAnimationFrame(tick);};
  image.onload=()=>{if(canvas.isConnected){draw();if(e.durations.length>1)raf=requestAnimationFrame(tick);}};
  image.src='/v1/emotes/assets/'+e.asset_id+'.png';
  return ()=>{cancelAnimationFrame(raf);image.onload=null;};
}

export function createEmotes({api,session,requireLogin,notify}){
  let host=null,entries=[],libraryPage=0,epoch=0,cleanups=[];
  const stop=()=>{for(const fn of cleanups)fn();cleanups=[];};
  const scopeNow=()=>session()?.owner_id??'';
  function previewEntry(entry){
    const owner=scopeNow(),editable=Boolean(owner&&(entry.owner_id===owner||session()?.role==='admin'));
    const dialog=document.createElement('dialog');dialog.className='emote-size-dialog';
    dialog.innerHTML=`<div class="emote-dialog-heading"><h3>${esc(entry.name)}</h3><button type="button" class="secondary-button small" data-preview-close>关闭</button></div><div data-battle-preview></div><p class="emote-preview-error" role="alert"></p>${editable?'<button type="button" class="primary-button" data-preview-save>保存倍率</button>':''}`;
    host.append(dialog);const preview=createBattlePreview(dialog.querySelector('[data-battle-preview]'),{entry,animate:animateEmote,editable});
    const dispose=()=>{preview.dispose();dialog.remove();};cleanups.push(dispose);dialog.addEventListener('close',dispose,{once:true});dialog.querySelector('[data-preview-close]').onclick=()=>dialog.close();dialog.showModal();preview.play();
    const save=dialog.querySelector('[data-preview-save]');if(save)save.onclick=async()=>{
      try{requireLogin();save.disabled=true;await api('/v1/emotes/'+entry.emote_id,{scale_percent:Math.round(preview.scale*100)},'PATCH');if(owner!==scopeNow())return;entry.scale_percent=Math.round(preview.scale*100);dialog.close();notify('表情倍率已保存');paint();}
      catch(e){dialog.querySelector('.emote-preview-error').textContent=e.message;save.disabled=false;}
    };
  }
  const paint=()=>{
    if(!host?.isConnected)return;stop();libraryPage=Math.min(libraryPage,Math.max(0,Math.ceil(entries.length/12)-1));
    const owner=scopeNow(),admin=session()?.role==='admin';
    host.innerHTML=`<section class="editor-panel emote-editor"><form class="emote-upload"><h3>上传表情</h3><label class="form-field"><span>名称</span><input name="name" maxlength="24" required></label><label class="form-field"><span>GIF / PNG</span><input type="file" name="image" accept="image/gif,image/png" required></label><p class="muted">支持透明背景。最大 4 MiB、1024 × 1024、120 帧。</p><div data-upload-preview></div><button class="primary-button" type="submit">上传</button></form></section><section class="emote-library">${entries.length?entries.slice(libraryPage*12,(libraryPage+1)*12).map(e=>`<article class="emote-item"><div class="emote-preview"><canvas data-emote="${esc(e.emote_id)}"></canvas><strong>${esc(e.name)}</strong></div><small>作者 · ${esc(e.author)}</small><button type="button" class="text-button emote-size-button" data-emote-size="${esc(e.emote_id)}">战场预览 · ${((e.scale_percent??DEFAULT_SCALE*100)/100).toFixed(2)}×</button>${owner&&(admin||e.owner_id===owner)?`<div class="emote-manage"><button class="text-button" data-emote-rename="${esc(e.emote_id)}">改名</button><button class="text-button" data-emote-delete="${esc(e.emote_id)}">删除</button></div>`:''}</article>`).join(''):'<p class="empty-state">暂无表情</p>'}</section><div class="form-actions emote-pagination"><button class="secondary-button" data-emote-previous ${libraryPage===0?'disabled':''}>上一页</button><span>${libraryPage+1} / ${Math.max(1,Math.ceil(entries.length/12))}</span><button class="secondary-button" data-emote-next ${(libraryPage+1)*12>=entries.length?'disabled':''}>下一页</button></div>`;
    host.querySelector('[data-emote-previous]').onclick=()=>{libraryPage=Math.max(0,libraryPage-1);paint();};
    host.querySelector('[data-emote-next]').onclick=()=>{libraryPage++;paint();};
    for(const canvas of host.querySelectorAll('canvas[data-emote]')){const e=entries.find(e=>e.emote_id===canvas.dataset.emote);if(e)cleanups.push(animateEmote(canvas,e));}
    let uploadURL='';const uploadPreview=createBattlePreview(host.querySelector('[data-upload-preview]'),{animate:animateEmote});
    cleanups.push(()=>{uploadPreview.dispose();if(uploadURL)URL.revokeObjectURL(uploadURL);});
    host.querySelector('input[name=image]').onchange=event=>{if(uploadURL)URL.revokeObjectURL(uploadURL);const file=event.target.files[0];uploadURL=file?URL.createObjectURL(file):'';uploadPreview.setImageURL(uploadURL);};
    for(const b of host.querySelectorAll('[data-emote-size]'))b.onclick=()=>previewEntry(entries.find(e=>e.emote_id===b.dataset.emoteSize));
    host.querySelector('form').onsubmit=async event=>{
      event.preventDefault();const form=event.currentTarget,button=form.querySelector('button[type="submit"]'),owner=scopeNow();
      try{requireLogin();const file=form.image.files[0];if(!file||file.size>4*1024*1024)throw Error('请选择小于 4 MiB 的 GIF 或 PNG。');button.disabled=true;button.textContent='正在处理…';
        const bytes=new Uint8Array(await file.arrayBuffer());let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));
        await api('/v1/emotes',{name:form.elements.name.value.trim(),image_base64:btoa(binary),scale_percent:Math.round(uploadPreview.scale*100)});if(owner!==scopeNow())return;entries=(await api('/v1/public/emotes')).emotes;notify('表情已上传');paint();
      }catch(e){notify(e.message,true);button.disabled=false;button.textContent='上传';}
    };
    for(const b of host.querySelectorAll('[data-emote-rename],[data-emote-delete]'))b.onclick=async()=>{
      const id=b.dataset.emoteRename??b.dataset.emoteDelete,e=entries.find(e=>e.emote_id===id),remove=Boolean(b.dataset.emoteDelete);
      const name=remove?null:prompt('表情名称',e.name);if(remove?!confirm('删除这个表情？已配置的位置会清空。'):name===null)return;
      try{requireLogin();b.disabled=true;await api('/v1/emotes/'+id+(remove?'/delete':''),remove?{}:{name},remove?'POST':'PATCH');entries=(await api('/v1/public/emotes')).emotes;paint();}catch(e){notify(e.message,true);b.disabled=false;}
    };
  };
  return {dispose(){epoch++;stop();host=null;},async render(root){
    stop();host=root;const current=++epoch,owner=scopeNow();
    host.innerHTML='<section class="empty-state">正在加载表情…</section>';
    try{const catalog=await api('/v1/public/emotes');if(current!==epoch||owner!==scopeNow()||!host?.isConnected)return;entries=catalog.emotes;paint();}
    catch(e){if(current!==epoch||!host?.isConnected)return;host.innerHTML='<section class="empty-state">表情加载失败，请刷新重试。</section>';notify(e.message,true);}
  }};
}
