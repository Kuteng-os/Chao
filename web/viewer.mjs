// Read-only catalog browser for GitHub Pages. All data comes from the public repository; nothing is written back.
import {cleanFilters,filterDefaults,filterCards,filterError,filtersUI,cardFace,paintCardFaces} from './catalog.mjs';
import {createLifecycle} from './lifecycle.mjs';
import {seriesName} from './series.mjs';
import {boldText} from './card_text.mjs';
import {esc,label,rarityLimits} from './model.mjs';

const GITHUB='https://raw.githubusercontent.com/xiangwu738-design/Chao/main/';
const MIRROR='https://cdn.jsdelivr.net/gh/xiangwu738-design/Chao@main/';
const CATALOG_FORMAT='chao-bundled-catalog-v1',FILTER_KEY='chao.catalog.filters';
const PRIMARY_TIMEOUT=10000,MIRROR_TIMEOUT=30000,MEDIA_TIMEOUT=30000,MAX_DOWNLOADS=6;
const TITLES={cards:'卡牌总览',factions:'阵营档案',keywords:'词条档案',emotes:'表情库'};

const $=selector=>document.querySelector(selector);
const content=createLifecycle({});
let route='cards',search='',loaded=false,sources=[GITHUB,MIRROR];
let cards=[],keywords=[],factions=[],emotes=null,seriesCatalog={};
let cardFilters=readFilters();

function readFilters(){try{return cleanFilters(JSON.parse(localStorage.getItem(FILTER_KEY)));}catch{return {...filterDefaults};}}
function saveFilters(){try{localStorage.setItem(FILTER_KEY,JSON.stringify(cardFilters));}catch{}}
function notify(text,error=false){const box=$('#notice');box.textContent=text;box.hidden=!text;box.classList.toggle('error',error);}
const routeFromHash=()=>Object.hasOwn(TITLES,location.hash.slice(1))?location.hash.slice(1):'cards';

async function get(root,path,timeout,cache){
 const response=await fetch(root+path,{cache,signal:AbortSignal.timeout(timeout)});
 if(!response.ok)throw new Error(`HTTP ${response.status}`);
 return response;
}

/** Applies the catalog's lifecycle table the same way the client does; derived cards follow their parent. */
function applyCatalog(data){
 const life=data.lifecycle??{},cardStatus=r=>life.cards?.[r.card_id]??(r.derived_from?life.cards?.[r.derived_from.card_id]:null)??{};
 const live=(items,kind,id)=>items.filter(item=>!life[kind]?.[id(item)]?.deleted).map(item=>({...item,archived:Boolean(item.archived||life[kind]?.[id(item)]?.archived)}));
 cards=data.cards.filter(r=>!cardStatus(r).deleted).map(r=>({...r,archived:Boolean(r.archived||cardStatus(r).archived)}));
 keywords=live(data.keywords??[],'keywords',k=>k.definition.id);
 factions=live(data.factions??[],'factions',f=>f.faction_id);
 seriesCatalog=data.health?.card_series??{};
}

async function fetchCatalog(){
 let failure;
 for(const root of [GITHUB,MIRROR]){
  try{
   const data=await (await get(root,'data/catalog.json',root===GITHUB?PRIMARY_TIMEOUT:MIRROR_TIMEOUT,'no-cache')).json();
   if(data.format!==CATALOG_FORMAT||!Array.isArray(data.cards))throw new Error('卡库格式不符');
   return {data,root};
  }catch(error){failure=error;}
 }
 throw failure;
}

async function refresh(){
 notify('');$('#connection').textContent='正在连接卡库…';
 try{
  const {data,root}=await fetchCatalog();
  sources=root===GITHUB?[GITHUB,MIRROR]:[MIRROR,GITHUB];
  const emoteList=await get(root,'data/emotes.json',MIRROR_TIMEOUT,'no-cache').then(r=>r.json()).catch(()=>null);
  applyCatalog(data);
  emotes=Array.isArray(emoteList?.emotes)?emoteList.emotes:null;
  loaded=true;
  $('#connection').textContent=`${root===GITHUB?'GitHub 卡库':'镜像卡库'} · 版本 ${data.catalog_version} · ${cards.length} 张`;
  if(root!==GITHUB)notify('GitHub 暂时连不上，正在使用镜像，新卡可能晚一些才显示。');
 }catch{
  $('#connection').textContent='无法连接卡库';
  notify(loaded?'刷新失败，当前显示的是上次读取的卡库。':'',true);
 }
 draw();
}

// Art is stored as content-addressed .bin files, so each download is checked against its own name.
const mediaCache=new Map(),waiting=[];
let downloads=0;
async function sha256(bytes){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(b=>b.toString(16).padStart(2,'0')).join('');}
async function download(kind,id){
 for(const root of sources){
  try{
   const bytes=await (await get(root,`data/${kind}/${id}.bin`,MEDIA_TIMEOUT,'default')).arrayBuffer();
   if(await sha256(bytes)===id)return URL.createObjectURL(new Blob([bytes],{type:'image/png'}));
  }catch{}
 }
 throw new Error('图片不可用');
}
function pump(){
 while(downloads<MAX_DOWNLOADS&&waiting.length){
  const {kind,id,resolve,reject}=waiting.pop(); // Newest first: what was just scrolled into view is what the reader is looking at.
  downloads++;
  download(kind,id).then(resolve,reject).finally(()=>{downloads--;pump();});
 }
}
function media(kind,id){
 const key=kind+':'+id;
 if(!mediaCache.has(key)){
  const task=new Promise((resolve,reject)=>{waiting.push({kind,id,resolve,reject});pump();});
  task.catch(()=>mediaCache.delete(key));
  mediaCache.set(key,task);
 }
 return mediaCache.get(key);
}
function showArt(img){media('art',img.dataset.art).then(url=>{img.src=url;},()=>{});}
const imageObserver=new IntersectionObserver(entries=>{for(const entry of entries)if(entry.isIntersecting){imageObserver.unobserve(entry.target);showArt(entry.target);}},{rootMargin:'400px'});
function paint(root){
 paintCardFaces(root);
 imageObserver.disconnect();
 root.querySelectorAll('img[data-art]').forEach(img=>imageObserver.observe(img));
}

const localArt=html=>html.replace(/src="\/v1\/card-art\/([a-f0-9]{64})\.png"/g,'data-art="$1"');
const tag=text=>`<span class="tag">${esc(text)}</span>`;
const button=(text,action,attrs='',kind='ghost-button small')=>`<button type="button" class="${kind}" data-action="${action}" ${attrs}>${esc(text)}</button>`;
function factionBadge(id){
 const f=factions.find(item=>item.faction_id===id);
 if(!f)return '<div class="author-mark">未指定阵营</div>';
 return `<div class="faction-badge"><span data-faction-background="${esc(f.color)}">${f.icon_id?`<img data-art="${esc(f.icon_id)}" alt="">`:esc(f.name.slice(0,1))}</span>${esc(f.name)}</div>`;
}

function cardRows(list){
 if(!list.length)return '<section class="empty-state full-width"><h3>没有匹配的卡牌</h3></section>';
 return list.map(r=>`<article class="catalog-entry">${localArt(cardFace(r,factions))}<div class="catalog-entry-actions">${button('详情','detail',`data-id="${esc(r.card_id)}" data-kind="card"`)}${r.derived_from?tag(`衍生 · ${r.definition.deck_building==='allowed'?'可入组':'不可入组'}`):''}${r.archived?tag('已归档'):''}</div></article>`).join('');
}
const selectedCards=()=>filterCards(cards.filter(r=>content.visible('cards',r)),cardFilters,{factions,keywords,series:seriesCatalog});
function renderCards(){
 const list=selectedCards();
 return filtersUI(cardFilters,cards,factions,keywords,content.filter('cards'),seriesCatalog,'')
  .replace('<span id="catalog-count" role="status"></span>',`<span id="catalog-count" role="status">${list.length} / ${cards.length} 张</span>`)
  .replace('<span id="catalog-filter-error" role="alert"></span>',`<span id="catalog-filter-error" role="alert">${esc(filterError(cardFilters))}</span>`)+`<div id="catalog-grid" class="archive-grid">${cardRows(list)}</div>`;
}
function updateCardResults(){
 const list=selectedCards();
 $('#catalog-count').textContent=`${list.length} / ${cards.length} 张`;
 $('#catalog-filter-error').textContent=filterError(cardFilters);
 $('#catalog-grid').innerHTML=cardRows(list);
 paint($('#catalog-grid'));
}

const latestKeywords=()=>keywords.filter(k=>!keywords.some(other=>other.definition.id===k.definition.id&&other.definition.version>k.definition.version));
function keywordRows(){
 const query=search.trim().toLowerCase();
 const list=latestKeywords().filter(k=>content.visible('keywords',k)&&[k.definition.name,k.definition.description,...(k.definition.aliases??[])].join(' ').toLowerCase().includes(query));
 const rows=list.length?list.map(k=>{const d=k.definition;return `<article class="registry-card"><div class="card-top">${tag(`独立词条 · v${d.version}`)}</div><h3>${esc(d.name)}${k.archived?' '+tag('已归档'):''}</h3><div class="rules">${esc(d.description)}</div><div class="actions">${button('查看','detail',`data-id="${esc(d.id)}" data-kind="keyword"`)}</div></article>`;}).join(''):'<section class="empty-state full-width"><h3>没有找到匹配内容</h3></section>';
 return {rows,count:list.length};
}
function renderKeywords(){
 const {rows,count}=keywordRows();
 return `<div class="toolbar"><input type="search" id="search" value="${esc(search)}" placeholder="搜索名称或效果" aria-label="搜索词条">${content.filter('keywords')}<span class="count" id="keyword-count">${count} 个词条</span></div><div id="keyword-grid" class="cards">${rows}</div>`;
}
function updateKeywordResults(){
 const {rows,count}=keywordRows();
 $('#keyword-count').textContent=`${count} 个词条`;
 $('#keyword-grid').innerHTML=rows;
}

function renderFactions(){
 const list=factions.filter(f=>content.visible('factions',f));
 const count=id=>cards.filter(r=>!r.archived&&r.definition.faction_id===id).length;
 const categories={large:'大阵营',normal:'普通阵营',small:'小阵营'};
 return `<section class="form-panel"><div class="section-heading"><h3>已登记阵营</h3>${content.filter('factions')}</div>${list.length?list.map(f=>`<article class="faction-item">${factionBadge(f.faction_id)}${tag(categories[f.category??'normal'])}${f.archived?tag('已归档'):''}<span class="muted">${count(f.faction_id)} 张卡牌${f.author?.name?` · ${esc(f.author.name)}`:''}</span>${button('查看卡牌','faction-cards',`data-id="${esc(f.faction_id)}"`)}</article>`).join(''):'<p class="muted">暂无阵营</p>'}</section>`;
}

function renderEmotes(){
 if(!emotes)return '<section class="empty-state"><h3>表情库暂时读不到</h3><p>请稍后点“刷新卡库”。</p></section>';
 return `<div class="viewer-emotes">${emotes.map((e,i)=>`<article class="viewer-emote"><canvas data-emote="${i}" aria-label="${esc(e.name)}"></canvas><strong>${esc(e.name)}</strong><small>${esc(e.author??'')}</small></article>`).join('')}</div>`;
}
function animateEmote(canvas,e){
 canvas.width=e.frame_width;canvas.height=e.frame_height;
 const context=canvas.getContext('2d'),image=new Image();
 let frame=0,elapsed=0,last=0;
 const drawFrame=()=>{context.clearRect(0,0,canvas.width,canvas.height);context.drawImage(image,(frame%e.columns)*e.frame_width,Math.floor(frame/e.columns)*e.frame_height,e.frame_width,e.frame_height,0,0,canvas.width,canvas.height);};
 const tick=time=>{if(!canvas.isConnected)return;elapsed+=last?Math.min(time-last,200):0;last=time;while(elapsed>=e.durations[frame]){elapsed-=e.durations[frame];frame=(frame+1)%e.durations.length;}drawFrame();requestAnimationFrame(tick);};
 image.onload=()=>{if(!canvas.isConnected)return;drawFrame();if(e.durations.length>1)requestAnimationFrame(tick);};
 media('emotes',e.asset_id).then(url=>{image.src=url;},()=>{});
}

function draw(){
 $('#title').textContent=TITLES[route];
 document.querySelectorAll('.nav-link').forEach(link=>link.classList.toggle('active',link.hash==='#'+route));
 if(!loaded){$('#view').innerHTML='<section class="empty-state"><h3>暂时读不到卡库</h3><p>GitHub 和镜像都没有响应，请检查网络后点“刷新卡库”。</p></section>';return;}
 $('#view').innerHTML=route==='factions'?renderFactions():route==='keywords'?renderKeywords():route==='emotes'?renderEmotes():renderCards();
 paint($('#view'));
 if(route==='emotes')document.querySelectorAll('[data-emote]').forEach(canvas=>animateEmote(canvas,emotes[Number(canvas.dataset.emote)]));
}

function showDetail(id,kind){
 const isCard=kind==='card',r=isCard?cards.find(c=>c.card_id===id):latestKeywords().find(k=>k.definition.id===id);
 if(!r)return;
 const d=r.definition,rarity=d.rarity??'standard';
 const art=isCard&&/^[0-9a-f]{64}$/.test(r.art?.id??'')?`<img class="card-art" data-art="${r.art.id}" alt="卡面">`:'';
 const facts=isCard?`${factionBadge(d.faction_id)}<p class="rarity-label">${esc(label(rarity))} · 最多 ${rarityLimits[rarity]} 张 · ${esc(seriesName(r.series??1,seriesCatalog))}</p><p class="author-mark">作者 ${esc(r.author?.name??'未署名')} · v${r.revision}</p>`:'';
 const derived=r.derived_from?`<p class="version-note">衍生自 ${esc(r.derived_from.name)} · ${d.deck_building==='allowed'?'允许加入牌组':'不可主动加入牌组'}</p>`:'';
 $('#modal-body').innerHTML=`<h2>${esc(d.name)}</h2>${art}${facts}${derived}<p class="rules">${boldText(r.detailed_text??r.rules_text??d.description??'',r.keyword_names??[])}</p><details><summary>完整定义</summary><pre>${esc(JSON.stringify(d,null,2))}</pre></details>`;
 paintCardFaces($('#modal-body'));
 $('#modal-body').querySelectorAll('img[data-art]').forEach(showArt);
 $('#modal').showModal();
}

document.addEventListener('click',event=>{
 const el=event.target.closest('[data-action]');
 if(!el)return;
 const {action,id,kind}=el.dataset;
 if(action==='refresh')refresh();
 else if(action==='close')$('#modal').close();
 else if(action==='detail')showDetail(id,kind);
 else if(action==='clear-card-filters'){cardFilters={...filterDefaults};saveFilters();draw();}
 else if(action==='faction-cards'){cardFilters={...filterDefaults,faction:id};saveFilters();if(route==='cards')draw();else location.hash='cards';}
});
function onFilterChange(event){
 const el=event.target,key=el.dataset.catalogFilter;
 if(key){cardFilters[key]=el.type==='checkbox'?el.checked:el.value;saveFilters();updateCardResults();}
 else if(el.id==='search'){search=el.value;updateKeywordResults();}
}
document.addEventListener('input',onFilterChange);
document.addEventListener('change',event=>{
 const kind=event.target.dataset.contentFilter;
 if(kind){content.setFilter(kind,event.target.value);draw();}
});
window.addEventListener('hashchange',()=>{route=routeFromHash();search='';draw();});

route=routeFromHash();
refresh();
