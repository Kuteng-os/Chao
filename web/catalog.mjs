import {seriesName,seriesEntries} from './series.mjs';
import {referenceAbilities} from './model.mjs';
import {sins,sinInfo} from './sins.mjs';
import {boldText} from './card_text.mjs';
import {esc,label,rarityLimits,titleText,titleLayout,isLatin,textFont} from './model.mjs';
export const unitGroups={air:['fighter','bomber'],ground:['infantry','tank','artillery']};
export const seriesNumber=r=>Number.isSafeInteger(r?.series)&&r.series>=1&&r.series<=9999?r.series:1;
export const seriesLabel=seriesName;
export const filterDefaults={series:'',q:'',kind:'',sin:'',faction:'',rarity:'',cost:'',keyword:'',author:'',attackMin:'',attackMax:'',healthMin:'',healthMax:'',operationMin:'',operationMax:'',own:false,sort:'recent'};
export function cleanFilters(value){const out={...filterDefaults};if(!value||typeof value!=='object')return out;for(const k of Object.keys(out))if(k==='own')out[k]=value[k]===true;else if(typeof value[k]==='string')out[k]=value[k].slice(0,k==='q'?200:80);return out;}
export function filterError(f){for(const k of ['attack','health','operation']){const a=f[k+'Min'],b=f[k+'Max'];if([a,b].some(v=>v!==''&&(!/^\d+$/.test(v)||Number(v)>(k==='health'?100:30))))return '数值范围须为 0—30。';if(a!==''&&b!==''&&Number(a)>Number(b))return '最低值不能高于最高值。';}return '';}
export function filterCards(records,f,{factions=[],keywords=[],series={}}={}){
 if(filterError(f))return [];
 const fm=new Map(factions.map(x=>[x.faction_id,x])),km=new Map(keywords.map(x=>[x.definition.id,x.definition.name]));
 const terms=f.q.trim().toLocaleLowerCase().split(/\s+/u).filter(Boolean);
 const out=records.filter(r=>{const d=r.definition,refs=d.keywords??[],unit=d.kind==='unit';
  if(f.own&&!r.owned_by_me)return false;
  if(f.series&&seriesNumber(r)!==Number(f.series))return false;
  const classes=[d.unit_class];
  const abilities=[...(d.abilities??[]),...refs.flatMap(ref=>referenceAbilities(ref,keywords))];
  for(const a of abilities)if(a.trigger==='on_play'&&!a.premise)for(const e of a.effects)if(e.op==='grant_unit_class'&&e.target==='self'&&['battle','match'].includes(e.duration))classes.push(e.unit_class);
  if(f.kind&&!(classes.some(c=>unitGroups[f.kind]?.includes(c))||d.kind===f.kind||classes.includes(f.kind)))return false;
  if(f.sin&&(f.sin==='none'?!!d.sin:d.sin!==f.sin))return false;
  if(f.faction&&(f.faction==='none'?!!d.faction_id:d.faction_id!==f.faction))return false;
  if(f.rarity&&(d.rarity??'standard')!==f.rarity)return false;
  if(f.cost&&(f.cost==='8+'?d.cost<8:d.cost!==Number(f.cost)))return false;
  if(f.keyword&&!refs.some(x=>x.id===f.keyword))return false;
  if(f.author&&r.author?.id!==f.author)return false;
  for(const [k,prop] of [['attack','attack'],['health','health'],['operation','operation_cost']]){if((f[k+'Min']!==''||f[k+'Max']!=='')&&!(unit||k==='health'&&d.kind==='hq'))return false;if(f[k+'Min']!==''&&d[prop]<Number(f[k+'Min']))return false;if(f[k+'Max']!==''&&d[prop]>Number(f[k+'Max']))return false;}
  const text=[seriesLabel(seriesNumber(r),series),sinInfo(d.sin).name,d.name,r.rules_text,d.flavor_text,r.author?.name,fm.get(d.faction_id)?.name,label(d.kind),label(d.unit_class),label(d.rarity??'standard'),...refs.map(x=>km.get(x.id)??label(x.id))].join(' ').toLocaleLowerCase();return terms.every(t=>text.includes(t));
 });
 const textSort=(a,b)=>a.definition.name.localeCompare(b.definition.name,'zh');
 return out.sort((a,b)=>f.sort==='name'?textSort(a,b):f.sort==='costAsc'?a.definition.cost-b.definition.cost||textSort(a,b):f.sort==='costDesc'?b.definition.cost-a.definition.cost||textSort(a,b):String(b.created_at??'').localeCompare(String(a.created_at??''))||textSort(a,b));
}
const option=(key,title,items,f)=>`<label class="catalog-select"><span class="sr-only">${title}</span><select aria-label="${title}" data-catalog-filter="${key}">${items.map(([v,n])=>`<option value="${esc(v)}" ${f[key]===v?'selected':''}>${esc(n)}</option>`).join('')}</select></label>`;
export function filtersUI(f,records,factions,keywords,archive,currentSeries=2,seriesTools=""){
 const authors=[...new Map(records.filter(r=>r.author).map(r=>[r.author.id,r.author])).values()].sort((a,b)=>a.name.localeCompare(b.name,'zh'));
 const refs=[...new Map(keywords.map(k=>[k.definition.id,k.definition])).values()].sort((a,b)=>a.name.localeCompare(b.name,'zh'));
 const range=(key,name)=>`<fieldset class="catalog-range"><legend>${name}</legend><input aria-label="最低${name}" data-catalog-filter="${key}Min" value="${esc(f[key+'Min'])}" type="number" min="0" max="${key==='health'?100:30}" placeholder="最低"><span>—</span><input aria-label="最高${name}" data-catalog-filter="${key}Max" value="${esc(f[key+'Max'])}" type="number" min="0" max="${key==='health'?100:30}" placeholder="最高"></fieldset>`;
 return `<section class="catalog-tools"><div class="catalog-primary"><input type="search" aria-label="搜索卡牌" data-catalog-filter="q" value="${esc(f.q)}" placeholder="搜索名称、效果、作者…">${option('kind','类型',[['','全部类型'],...['unit','infantry','tank','artillery','fighter','bomber','air','ground','order','counter','field','hq'].map(k=>[k,label(k)])],f)}${option('sin','罪孽',[['','全部罪孽'],['none','未选择罪孽'],...sins.map(s=>[s.id,s.name])],f)}${option('faction','阵营',[['','全部阵营'],['none','无阵营'],...factions.map(x=>[x.faction_id,x.name])],f)}${option('rarity','稀有度',[['','全部稀有度'],...Object.keys(rarityLimits).map(k=>[k,label(k)])],f)}<div class="catalog-series">${option('series','卡包',[['','全部卡包'],...seriesEntries(currentSeries,records).map(e=>[String(e.id),e.name])],f)}<span id="catalog-series-actions" class="actions">${seriesTools}</span></div>${option('cost','费用',[['','全部费用'],...Array.from({length:8},(_,n)=>[String(n),n+' 费']),['8+','8 费以上']],f)}</div><details class="catalog-advanced"><summary>详细筛选</summary><div class="catalog-secondary">${option('keyword','词条',[['','全部词条'],...refs.map(x=>[x.id,x.name])],f)}${option('author','作者',[['','全部作者'],...authors.map(x=>[x.id,x.name])],f)}${option('sort','排序',[['recent','最近登记'],['name','名称'],['costAsc','费用从低到高'],['costDesc','费用从高到低']],f)}${archive}<label class="catalog-own"><input type="checkbox" data-catalog-filter="own" ${f.own?'checked':''}>仅我创作</label></div><div class="catalog-ranges">${range('attack','攻击')}${range('health','防御')}${range('operation','行动费')}</div></details><div class="catalog-results"><span id="catalog-count" role="status"></span><span id="catalog-filter-error" role="alert"></span><button type="button" class="ghost-button small" data-action="clear-card-filters">清除筛选</button></div></section>`;
}
const artURL=id=>typeof id==='string'&&/^[a-f0-9]{64}$/.test(id)?'/v1/card-art/'+id+'.png':'';
export function cardFace(r,factions){
 const custom=r.definition.display_text?.trim();if(custom)r={...r,rules_text:custom};
 const d=r.definition,f=factions.find(f=>f.faction_id===d.faction_id),color=sinInfo(d.sin).color,icon=artURL(f?.icon_id),factionIcon=artURL(f?.icon_id),art=artURL(r.art?.id),background=artURL(f?.background_id),unit=d.kind==='unit',rarity=d.rarity??'standard';
 const title=titleText(d).split('\n').map(esc).join('<br>'),font=22;
 return `<div class="archive-face" data-faction-color="${color}" data-rarity="${esc(rarity)}"><div class="archive-title"><span class="archive-cost">${d.kind==='hq'?'总部':d.cost}<small>${unit?'K '+d.operation_cost:''}</small></span><h3 data-card-name="${esc(d.name)}" data-name-break="${d.appearance?.name_break??0}" data-title-size="${font}" title="${esc(d.name)}">${title}</h3><span class="archive-faction" title="${esc(f?.name??'未选择阵营')}">${icon?`<img src="${icon}" alt="${esc(f?.name??'未选择阵营')}">`:esc(f?.name?.slice(0,1)??'')}</span></div><div class="archive-art">${art||background?`<img class="archive-art-image" src="${art||background}" alt="${esc(d.name)}卡面" loading="lazy" decoding="async">`:''}${!art&&!background&&factionIcon?`<img class="faction-watermark" src="${factionIcon}" alt="">`:''}<div class="archive-stats">${unit?`<span class="archive-attack">${d.attack}</span><span class="archive-class">${esc(label(d.unit_class))}</span><span class="archive-health">${d.health}</span>`:`<span class="archive-kind" aria-label="${label(d.kind)}">${d.kind==='hq'?d.health:d.kind==='order'?'!':d.kind==='counter'?'?':'△'}</span>`}</div></div><div data-latin="${isLatin(r.rules_text??'')}" class="archive-rules ${!isLatin(r.rules_text??'')&&String(r.rules_text??'').length>120?'long-rules':''}"><p>${boldText(r.rules_text??'无额外能力',r.keyword_names??[])}</p></div><div class="archive-rarity rarity-${esc(rarity)}" aria-label="${label(rarity)}，最多 ${rarityLimits[rarity]} 张" title="${label(rarity)} · 最多 ${rarityLimits[rarity]} 张">${'◆'.repeat(d.kind==='hq'?1:rarityLimits[rarity])}</div></div>`;
}

// CSP keeps inline markup styles disabled. Apply only validated display values through CSSOM.
export function paintCardFaces(root=document){
 for(const item of root.querySelectorAll('[data-faction-background]')){
  const color=item.dataset.factionBackground;if(/^#[a-f0-9]{6}$/i.test(color))item.style.backgroundColor=color;
 }
 for(const face of root.querySelectorAll('.archive-face[data-faction-color]')){
  const color=face.dataset.factionColor;if(/^#[a-f0-9]{6}$/i.test(color))face.style.setProperty('--faction-color',color);
  const title=face.querySelector('[data-title-size]'),size=Number(title?.dataset.titleSize);
  if(title){
   const name=title.dataset.cardName??title.textContent,ctx=document.createElement('canvas').getContext('2d'),family=textFont(name);
   const measure=(text,fs)=>{ctx.font=`${fs}px ${family}`;return ctx.measureText(text).width;};
   const layout=titleLayout({name,appearance:{name_break:Number(title.dataset.nameBreak)}},measure,false,{width:title.clientWidth||145,height:54});
   title.style.fontFamily=family;title.style.fontSize=layout.size+'px';title.style.whiteSpace='pre';title.textContent=layout.lines.join('\n');
  }
  const rules=face.querySelector('.archive-rules[data-latin="true"]'),paragraph=rules?.querySelector('p');
  if(paragraph){
   const style=getComputedStyle(rules),height=rules.clientHeight-parseFloat(style.paddingTop)-parseFloat(style.paddingBottom);
   paragraph.style.webkitLineClamp='unset';let fs=16;paragraph.style.fontSize=fs+'px';
   while(fs>13&&paragraph.scrollHeight>height){fs--;paragraph.style.fontSize=fs+'px';}
   paragraph.style.webkitLineClamp=String(Math.max(1,Math.floor(height/(fs*1.25))));
  }
 }
}

if(typeof window!=="undefined")window.addEventListener("resize",()=>paintCardFaces());
