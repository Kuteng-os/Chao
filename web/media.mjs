import {esc} from './model.mjs';
export const soundSlots={select:'选中',draw:'抽到手牌',play:'出牌 / 部署',attack:'攻击',move:'移动',damage:'受伤',heal:'受到治疗',death:'阵亡',trigger:'效果触发'};
export function mediaEditor(card,mode='card'){
 const media=card.media??{};
 const audio=(key,name,id)=>`<div class="media-row"><strong>${name}</strong><label class="secondary-button small">${id?'更换':'上传'}<input type="file" data-media-file="${key}" data-media-mode="${mode}" accept="audio/*" hidden></label>${id?`<audio controls preload="none" src="/v1/card-sounds/${esc(id)}.wav"></audio><button type="button" class="ghost-button small" data-action="remove-media" data-mode="${mode}" data-slot="${key}">恢复默认</button>`:'<span class="hint">默认</span>'}</div>`;
 return `<section class="form-panel"><details><summary>卡牌音效</summary><p class="hint">每段最多 12 秒，未上传时使用默认音效。</p>${Object.entries(soundSlots).map(([k,n])=>audio(k,n,media.sounds?.[k])).join('')}</details></section>${card.kind==='field'?`<section class="form-panel"><h3>场地表现</h3><div class="media-row"><strong>战场背景</strong><label class="secondary-button small">${media.background?'更换':'上传'}<input type="file" data-media-background data-media-mode="${mode}" accept="image/png,image/jpeg,image/webp" hidden></label>${media.background?`<button type="button" class="ghost-button small" data-action="remove-media" data-mode="${mode}" data-slot="background">恢复默认</button>`:''}</div>${media.background?`<img class="field-background-preview" src="/v1/card-art/${esc(media.background)}.png" alt="场地背景">`:''}${audio('music','背景音乐',media.music)}<p class="hint">音乐最多 300 秒；场地被替换后切换为新场地的背景与音乐。</p></section>`:''}`;
}
export async function encodeAudio(file,music=false){
 if(!file||file.size>32*1024*1024)throw new Error('请选择 32 MB 以内的音频。');
 const Context=globalThis.AudioContext??globalThis.webkitAudioContext;if(!Context)throw new Error('当前浏览器不支持音频处理，请更换浏览器。');
 const ctx=new Context();let decoded;
 try{decoded=await ctx.decodeAudioData(await file.arrayBuffer());}catch{throw new Error('无法读取音频，请选择 MP3、WAV 或 OGG 文件。');}finally{await ctx.close();}
 if(decoded.duration<=0||decoded.duration>(music?300:12))throw new Error(music?'背景音乐最多 300 秒。':'音效最多 12 秒。');
 const offline=new OfflineAudioContext(1,Math.ceil(decoded.duration*22050),22050),source=offline.createBufferSource();source.buffer=decoded;source.connect(offline.destination);source.start();
 const rendered=await offline.startRendering(),pcm=rendered.getChannelData(0),bytes=new Uint8Array(44+pcm.length*2),v=new DataView(bytes.buffer);
 const tag=(at,s)=>[...s].forEach((c,i)=>v.setUint8(at+i,c.charCodeAt(0)));tag(0,'RIFF');v.setUint32(4,bytes.length-8,true);tag(8,'WAVE');tag(12,'fmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,1,true);v.setUint32(24,22050,true);v.setUint32(28,44100,true);v.setUint16(32,2,true);v.setUint16(34,16,true);tag(36,'data');v.setUint32(40,pcm.length*2,true);
 for(let i=0;i<pcm.length;i++)v.setInt16(44+i*2,Math.round(Math.max(-1,Math.min(1,pcm[i]))*32767),true);
 let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(binary);
}
