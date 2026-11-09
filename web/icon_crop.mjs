// Local square selection. The transparent canvas is never filled when exporting.
export function cropSquare(bitmap) {
 return new Promise(resolve=>{
  const dialog=document.createElement('dialog');dialog.className='icon-crop-dialog';
  const heading=document.createElement('h3');heading.textContent='框选阵营图标';
  const hint=document.createElement('p');hint.className='hint';hint.textContent='拖动框选，框内拖动可移动；拖动右下角可缩放。';
  const canvas=document.createElement('canvas');canvas.className='icon-crop-canvas';canvas.setAttribute('aria-label','图标裁剪区域');canvas.tabIndex=0;
  const scale=Math.min(1,600/bitmap.width,420/bitmap.height);canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
  const ctx=canvas.getContext('2d'),preview=document.createElement('canvas');preview.width=preview.height=96;preview.className='icon-crop-preview';preview.setAttribute('aria-label','裁剪预览');
  const range=document.createElement('input');range.type='range';range.min='1';range.max=String(Math.min(canvas.width,canvas.height));range.setAttribute('aria-label','选框大小');
  const sliderLabel=document.createElement('label');sliderLabel.textContent='选框大小';sliderLabel.append(range);
  const actions=document.createElement('div');actions.className='icon-crop-actions';
  let side=Math.min(canvas.width,canvas.height),box={x:(canvas.width-side)/2,y:(canvas.height-side)/2,s:side},drag=null,closed=false;
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
  const output=(target,full=false)=>{const c=target.getContext('2d');c.clearRect(0,0,target.width,target.height);c.imageSmoothingEnabled=true;c.imageSmoothingQuality='high';if(full){const r=Math.min(target.width/bitmap.width,target.height/bitmap.height),w=bitmap.width*r,h=bitmap.height*r;c.drawImage(bitmap,(target.width-w)/2,(target.height-h)/2,w,h);}else c.drawImage(bitmap,box.x*bitmap.width/canvas.width,box.y*bitmap.height/canvas.height,box.s*bitmap.width/canvas.width,box.s*bitmap.height/canvas.height,0,0,target.width,target.height);};
  const paint=()=>{ctx.clearRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);ctx.fillStyle='#0009';ctx.beginPath();ctx.rect(0,0,canvas.width,canvas.height);ctx.rect(box.x,box.y,box.s,box.s);ctx.fill('evenodd');ctx.strokeStyle='#fff';ctx.lineWidth=2;ctx.strokeRect(box.x,box.y,box.s,box.s);ctx.fillStyle='#d1ae74';ctx.fillRect(box.x+box.s-6,box.y+box.s-6,12,12);range.value=String(box.s);output(preview);};
  const finish=(accepted,full=false)=>{if(closed)return;closed=true;let result=null;if(accepted){const out=document.createElement('canvas');out.width=out.height=256;output(out,full);result=out.toDataURL('image/png');}dialog.close();dialog.remove();resolve(result);};
  const button=(text,fn,primary=false)=>{const b=document.createElement('button');b.type='button';b.className=primary?'primary-button':'secondary-button';b.textContent=text;b.addEventListener('click',fn);actions.append(b);};
  button('取消',()=>finish(false));button('使用完整图片',()=>finish(true,true));button('使用框选',()=>finish(true),true);
  const point=e=>{const r=canvas.getBoundingClientRect();return {x:clamp((e.clientX-r.left)*canvas.width/r.width,0,canvas.width),y:clamp((e.clientY-r.top)*canvas.height/r.height,0,canvas.height)};};
  canvas.addEventListener('pointerdown',e=>{if(e.button!==0)return;e.preventDefault();const p=point(e),r=canvas.getBoundingClientRect(),t=22*canvas.width/r.width;const inside=p.x>=box.x&&p.x<=box.x+box.s&&p.y>=box.y&&p.y<=box.y+box.s,corner=Math.abs(p.x-box.x-box.s)<t&&Math.abs(p.y-box.y-box.s)<t;drag={pointer:e.pointerId,start:p,box:{...box},mode:corner?'resize':inside?'move':'new'};canvas.setPointerCapture(e.pointerId);});
  canvas.addEventListener('pointermove',e=>{if(!drag||drag.pointer!==e.pointerId)return;const p=point(e),d=drag,b=d.box;if(d.mode==='move'){box.x=clamp(b.x+p.x-d.start.x,0,canvas.width-box.s);box.y=clamp(b.y+p.y-d.start.y,0,canvas.height-box.s);}else if(d.mode==='resize'){box.s=clamp(Math.max(p.x-b.x,p.y-b.y),1,Math.min(canvas.width-b.x,canvas.height-b.y));}else{const dx=p.x-d.start.x,dy=p.y-d.start.y,max=Math.min(dx<0?d.start.x:canvas.width-d.start.x,dy<0?d.start.y:canvas.height-d.start.y);box.s=clamp(Math.max(Math.abs(dx),Math.abs(dy)),1,Math.max(1,max));box.x=clamp(dx<0?d.start.x-box.s:d.start.x,0,canvas.width-box.s);box.y=clamp(dy<0?d.start.y-box.s:d.start.y,0,canvas.height-box.s);}paint();});
  for(const event of ['pointerup','pointercancel','lostpointercapture'])canvas.addEventListener(event,e=>{if(drag?.pointer===e.pointerId)drag=null;});
  canvas.addEventListener('keydown',e=>{const delta={ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]}[e.key];if(!delta)return;e.preventDefault();const step=e.shiftKey?10:1;box.x=clamp(box.x+delta[0]*step,0,canvas.width-box.s);box.y=clamp(box.y+delta[1]*step,0,canvas.height-box.s);paint();});
  range.addEventListener('input',()=>{const s=Number(range.value);box={x:clamp(box.x+(box.s-s)/2,0,canvas.width-s),y:clamp(box.y+(box.s-s)/2,0,canvas.height-s),s};paint();});
  dialog.addEventListener('cancel',e=>{e.preventDefault();finish(false);});
  dialog.append(heading,hint,canvas,sliderLabel,preview,actions);document.body.append(dialog);paint();dialog.showModal();
 });
}
