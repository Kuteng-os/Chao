export const DEFAULT_SCALE=.46;
const scaleOf=v=>typeof v==='number'&&Number.isFinite(v)&&v>=.25&&v<=2?v:DEFAULT_SCALE;
// The client battlefield uses a 1440 × 900 board and a 156 × 214 headquarters.
export function createBattlePreview(host,{entry=null,imageURL='',animate,editable=true,onChange=()=>{}}={}){
 let scale=scaleOf((entry?.scale_percent??46)/100),point={x:50,y:50},timer=0,stopFrame=null,disposed=false;
 host.innerHTML=`<div class="emote-scale-controls"><label>大小倍率 <output>${scale.toFixed(2)}×</output><input type="range" aria-label="大小倍率" min="0.25" max="2" step="0.01" value="${scale}" ${editable?'':'disabled'}></label><span>1× = 总部宽度（按表情长边）</span></div><div class="emote-battle-preview" role="button" tabindex="0" aria-label="点击战场预览表情"><div class="preview-frontline"></div><div class="preview-hq enemy"><span>对方总部</span><b>20</b></div><div class="preview-hq own"><span>己方总部</span><b>20</b></div><div class="preview-hand"><i></i><i></i><i></i></div></div><div class="emote-preview-actions"><span>点击战场选择显示位置</span><button type="button" class="secondary-button small" data-preview-play>播放</button></div>`;
 const stage=host.querySelector('.emote-battle-preview'),slider=host.querySelector('input'),output=host.querySelector('output');
 const clear=()=>{stopFrame?.();stopFrame=null;stage.querySelector('.emote-battle-sprite')?.remove();};
 function play(){
  if(disposed||!host.isConnected)return;clear();
  if(!entry&&!imageURL)return;
  const sprite=document.createElement('div');sprite.className='emote-battle-sprite';
  const x=point.x+(Math.random()*24-12)/1440*100,y=point.y+(Math.random()*16-8)/900*100;
  sprite.style.cssText=`width:${156*scale/1440*100}%;height:${156*scale/900*100}%;--at-x:${x}%;--at-y:${y}%;--rise:${(24+Math.random()*10)/900*100}%;--tilt:${Math.random()*16-8}deg;`;
  if(entry){const canvas=document.createElement('canvas');sprite.append(canvas);stage.append(sprite);stopFrame=animate(canvas,entry);}
  else{const img=document.createElement('img');img.alt='';img.src=imageURL;sprite.append(img);stage.append(sprite);}
 }
 slider.oninput=()=>{scale=scaleOf(Number(slider.value));output.textContent=scale.toFixed(2)+'×';onChange(scale);play();};
 stage.onclick=event=>{const rect=stage.getBoundingClientRect();point={x:Math.max(12,Math.min(88,(event.clientX-rect.left)/rect.width*100)),y:Math.max(12,Math.min(88,(event.clientY-rect.top)/rect.height*100))};play();};
 stage.onkeydown=event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();play();}};
 host.querySelector('[data-preview-play]').onclick=play;
 timer=setInterval(play,2300);play();
 return {get scale(){return scale;},setImageURL(url){entry=null;imageURL=url;play();},play,dispose(){if(disposed)return;disposed=true;clearInterval(timer);clear();}};
}
