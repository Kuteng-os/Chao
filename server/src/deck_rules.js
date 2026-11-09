export const DECK_SIZE = 40;
export const SIN_QUOTAS = {main:30,ally:10};
const SIN_IDS = ['wrath','lust','sloth','gluttony','gloom','pride','envy'];
export const FACTION_CATEGORIES = ['large','normal','small'];
export function deckComposition(cards, factions, main, ally, complete=true) {
  const result={error:'',main_count:0,ally_count:0,neutral_count:0};
  if(!SIN_IDS.includes(main)||!SIN_IDS.includes(ally)||main===ally)return {...result,error:'请选择两种不同的主罪孽与副罪孽。'};
  for(const card of cards){
    const d=card.source??card.definition??card;
    if(d.kind==='hq')return {...result,error:'总部应单独选择，不计入40张牌组。'};
    if(d.sin===undefined||d.sin===null||d.sin===''){result.neutral_count++;continue;}
    const slot=d.sin===main?'main':d.sin===ally?'ally':null;
    if(!slot)return {...result,error:`“${d.name}”的罪孽不属于所选主、副罪孽。`};
    const faction=d.faction_id?factions?.[d.faction_id]:null;
    if(d.faction_id&&!faction)return {...result,error:`“${d.name}”的阵营不存在，请刷新卡库。`};
    const category=faction?.category??'normal';
    if(!FACTION_CATEGORIES.includes(category))return {...result,error:'阵营类别无效，请刷新卡库。'};
    if(category==='large'&&slot==='ally')return {...result,error:`“${d.name}”属于大阵营，不能计入副罪孽。`};
    if(category==='small'&&slot==='main')return {...result,error:`“${d.name}”属于小阵营，不能计入主罪孽。`};
    result[slot+'_count']++;
  }
  if(cards.length>40||result.main_count>30||result.ally_count>10||(complete&&cards.length!==40))result.error=`牌组需要30张主罪孽、10张副罪孽（无罪孽牌可补足）；当前主${result.main_count}张、副${result.ally_count}张、通用${result.neutral_count}张。`;
  return result;
}
export const RARITIES = {standard:{name:'普通',limit:4},limited:{name:'限定',limit:3},special:{name:'特殊',limit:2},elite:{name:'精英',limit:1}};
export const rarityOf = definition => definition.rarity ?? 'standard';
export const copyLimit = definition => RARITIES[rarityOf(definition)]?.limit ?? 0;
export const cardNameKey = definition => definition.name.normalize('NFC').trim().toLowerCase();
export function checkDeckCopies(cards) {
  const groups=new Map();
  for(const card of cards){
    const d=card.definition??card,limit=copyLimit(d);
    if(d.kind==='hq')return '总部应单独选择，不计入40张牌组。';
    if(d.deck_building==='generated_only')return `“${d.name}”是衍生卡，尚未获准加入牌组。`;
    if(!limit)return '卡牌稀有度无效。';
    const keys=['name:'+cardNameKey(d),...(card.card_id?['id:'+card.card_id]:[])];
    for(const key of keys){const group=groups.get(key)??{count:0,limit:4};group.count++;group.limit=Math.min(group.limit,limit);groups.set(key,group);if(group.count>group.limit)return `“${d.name}”最多携带 ${group.limit} 张。`;}
  }
  return '';
}

export function deckFactions(cards, factions, mainId=null, allyId=null) {
  if((mainId!==null&&typeof mainId!=='string')||(allyId!==null&&typeof allyId!=='string'))return {error:'阵营选择无效。'};
  const counts=new Map();
  for(const record of cards){
    const d=record.source??record.definition??record,id=d.faction_id;
    if(id===undefined||id===null||id==='')continue;
    if(typeof id!=='string'||!factions?.[id])return {error:`“${d.name}”尚未指定已登记阵营。`};
    counts.set(id,(counts.get(id)||0)+1);
  }
  // Legacy requests without a nominal main remain compatible. Explicit choices
  // are never changed because of faction proportions or card rarity.
  if(!mainId)mainId=[...counts.keys()].sort((a,b)=>counts.get(b)-counts.get(a)||(a<b?-1:a>b?1:0))[0];
  mainId??='';
  if(mainId&&!factions?.[mainId])return {error:'请选择已登记的主国。'};
  return {error:'',main_faction_id:mainId,ally_faction_id:'',ally_count:cards.length-(counts.get(mainId)||0)};
}
