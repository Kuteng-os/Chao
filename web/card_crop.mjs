import {cardFace,paintCardFaces} from './catalog.mjs';

// The printed Godot face uses a 228 × 156 artwork aperture (19:13).
export const ART_RATIO=19/13;
export function cropCard(bitmap,record,factions){
 return new Promise(resolve=>{
  const dialog=document.createElement('dialog');dialog.className='card-crop-dialog';
  dialog.setAttribute('aria-label','框选卡面');
  dialog.innerHTML='<h3>框选卡面</h3><p class="hint">拖动框选；框内拖动可移动，右下角可缩放。</p><div class="card-crop-body"><div class="card-crop-source"></div><div class="card-live-preview"></div></div><div class="card-crop-actions"></div>';
  const canvas=document.createElement('canvas');canvas.className='icon-crop-canvas';canvas.tabIndex=0;canvas.setAttribute('aria-label','卡面裁剪区域');
  const scale=Math.min(1,640/bitmap.width,480/bitmap.height);canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
  canvas.style.width=`min(100%, calc(var(--crop-height) * ${bitmap.width/bitmap.height}))`;
  const context=canvas.getContext('2d'),source=dialog.querySelector('.card-crop-source'),live=dialog.querySelector('.card-live-preview');
  live.innerHTML=cardFace(record,factions);paintCardFaces(live);
  const preview=document.createElement('canvas');preview.width=760;preview.height=520;preview.className='archive-art-image';preview.setAttribute('aria-label','卡面实景预览');
  const aperture=live.querySelector('.archive-art');aperture.querySelectorAll('img').forEach(x=>x.remove());aperture.prepend(preview);
  const range=document.createElement('input');range.type='range';range.min='1';range.step='any';range.setAttribute('aria-label','卡面选框大小');
  const maxW=Math.min(bitmap.width,bitmap.height*ART_RATIO);range.max=String(maxW);
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
  let box={x:(bitmap.width-maxW)/2,y:(bitmap.height-maxW/ART_RATIO)/2,w:maxW},drag=null,closed=false,full=false;
  function render(target){const c=target.getContext('2d');c.clearRect(0,0,target.width,target.height);c.imageSmoothingEnabled=true;c.imageSmoothingQuality='high';if(full){const s=Math.min(target.width/bitmap.width,target.height/bitmap.height),w=bitmap.width*s,h=bitmap.height*s;c.drawImage(bitmap,(target.width-w)/2,(target.height-h)/2,w,h);}else c.drawImage(bitmap,box.x,box.y,box.w,box.w/ART_RATIO,0,0,target.width,target.height);}
  function paint(){const sx=canvas.width/bitmap.width,sy=canvas.height/bitmap.height;context.clearRect(0,0,canvas.width,canvas.height);context.drawImage(bitmap,0,0,canvas.width,canvas.height);if(!full){context.fillStyle='#0009';context.beginPath();context.rect(0,0,canvas.width,canvas.height);context.rect(box.x*sx,box.y*sy,box.w*sx,box.w/ART_RATIO*sy);context.fill('evenodd');context.strokeStyle='#fff';context.lineWidth=2;context.strokeRect(box.x*sx,box.y*sy,box.w*sx,box.w/ART_RATIO*sy);context.fillStyle='#d1ae74';context.fillRect((box.x+box.w)*sx-6,(box.y+box.w/ART_RATIO)*sy-6,12,12);}range.value=String(box.w);render(preview);}
  function finish(accepted){if(closed)return;closed=true;const result=accepted?preview.toDataURL('image/png'):null;dialog.close();dialog.remove();resolve(result);}
  const actions=dialog.querySelector('.card-crop-actions');
  function button(text,run,primary=false){const b=document.createElement('button');b.type='button';b.className=primary?'primary-button':'secondary-button';b.textContent=text;b.onclick=run;actions.append(b);return b;}
  button('取消',()=>finish(false));
  const contain=button('完整图片',()=>{full=!full;contain.textContent=full?'恢复框选':'完整图片';paint();});
  button('使用此卡面',()=>finish(true),true);
  const point=e=>{const r=canvas.getBoundingClientRect();return{x:clamp((e.clientX-r.left)/r.width*bitmap.width,0,bitmap.width),y:clamp((e.clientY-r.top)/r.height*bitmap.height,0,bitmap.height)};};
  canvas.addEventListener('pointerdown',e=>{if(e.button!==0)return;e.preventDefault();full=false;contain.textContent='完整图片';const p=point(e),r=canvas.getBoundingClientRect(),tx=20*bitmap.width/r.width,ty=20*bitmap.height/r.height;const inside=p.x>=box.x&&p.x<=box.x+box.w&&p.y>=box.y&&p.y<=box.y+box.w/ART_RATIO,corner=Math.abs(p.x-box.x-box.w)<tx&&Math.abs(p.y-box.y-box.w/ART_RATIO)<ty;drag={id:e.pointerId,start:p,box:{...box},mode:corner?'resize':inside?'move':'new'};canvas.setPointerCapture(e.pointerId);paint();});
  canvas.addEventListener('pointermove',e=>{if(drag?.id!==e.pointerId)return;const p=point(e),d=drag,b=d.box;if(d.mode==='move'){box.x=clamp(b.x+p.x-d.start.x,0,bitmap.width-box.w);box.y=clamp(b.y+p.y-d.start.y,0,bitmap.height-box.w/ART_RATIO);}else if(d.mode==='resize'){box.w=clamp(Math.max(p.x-b.x,(p.y-b.y)*ART_RATIO),1,Math.min(bitmap.width-b.x,(bitmap.height-b.y)*ART_RATIO));}else{const dx=p.x-d.start.x,dy=p.y-d.start.y,max=Math.min(dx<0?d.start.x:bitmap.width-d.start.x,(dy<0?d.start.y:bitmap.height-d.start.y)*ART_RATIO);box.w=clamp(Math.max(Math.abs(dx),Math.abs(dy)*ART_RATIO),1,Math.max(1,max));box.x=clamp(dx<0?d.start.x-box.w:d.start.x,0,bitmap.width-box.w);box.y=clamp(dy<0?d.start.y-box.w/ART_RATIO:d.start.y,0,bitmap.height-box.w/ART_RATIO);}paint();});
  for(const event of ['pointerup','pointercancel','lostpointercapture'])canvas.addEventListener(event,e=>{if(drag?.id===e.pointerId)drag=null;});
  canvas.addEventListener('keydown',e=>{const delta={ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]}[e.key];if(!delta)return;e.preventDefault();full=false;contain.textContent='完整图片';const step=e.shiftKey?10:1;box.x=clamp(box.x+delta[0]*step,0,bitmap.width-box.w);box.y=clamp(box.y+delta[1]*step,0,bitmap.height-box.w/ART_RATIO);paint();});
  range.oninput=()=>{full=false;contain.textContent='完整图片';const w=clamp(Number(range.value),1,maxW);box={x:clamp(box.x+(box.w-w)/2,0,bitmap.width-w),y:clamp(box.y+(box.w-w)/ART_RATIO/2,0,bitmap.height-w/ART_RATIO),w};paint();};
  dialog.addEventListener('cancel',e=>{e.preventDefault();finish(false);});
  source.append(canvas,range);document.body.append(dialog);paint();dialog.showModal();
 });
}
