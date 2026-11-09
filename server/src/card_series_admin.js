import {fields} from './service.js';
import {fail} from './codec.js';
import {isAdmin,audit} from './account_roles.js';
import {cardSeries,initializeCardSeries,requireSeries,seriesCatalog} from './card_series.js';

function seriesName(value,catalog,except=0){
 if(typeof value!=='string')fail('INVALID_REQUEST','请填写卡包名称。',400);
 const name=value.trim().normalize('NFC');
 if(!name||[...name].length>32||/[\p{Cc}\p{Cf}]/u.test(name))fail('INVALID_REQUEST','卡包名称须为 1～32 个字符，不能包含换行或控制字符。',400);
 if(catalog.entries.some(e=>e.id!==except&&e.name.toLocaleLowerCase()===name.toLocaleLowerCase()))fail('SERIES_NAME_EXISTS','这个卡包名称已存在。',409);
 return name;
}
export class CardSeriesAdmin {
 constructor(service){this.service=service;this.store=service.store;}
 async manage(owner,body){
  fields(body,['request_id','action','expected_revision'],['series','name']);
  return this.service.idem(owner,'card-series:manage',body,state=>{
   if(!isAdmin(state,owner))fail('FORBIDDEN','只有管理员可以管理卡包。',403);
   initializeCardSeries(state);
   const catalog=seriesCatalog(state);
   if(body.expected_revision!==catalog.revision)fail('REVISION_CONFLICT','卡包已被其他管理员修改，请刷新后重试。',409);
   let id;
   if(body.action==='create'){
    if(body.series!==undefined)fail('INVALID_REQUEST','新增卡包的编号由系统分配。',400);
    id=Math.max(...catalog.available)+1;
    if(id>9999)fail('LIMIT_REACHED','卡包数量已达上限。',409);
    state.card_series.names[id]=seriesName(body.name,catalog);
   }else if(body.action==='rename'){
    id=requireSeries(state,body.series);state.card_series.names[id]=seriesName(body.name,catalog,id);
   }else if(body.action==='set_current'){
    if(body.name!==undefined)fail('INVALID_REQUEST','设置默认卡包不需要名称。',400);
    id=requireSeries(state,body.series);state.card_series.current=id;
   }else fail('INVALID_REQUEST','卡包操作无效。',400);
   state.card_series.revision++;
   audit(state,owner,'card_series_'+body.action,String(id));
   return {card_series:seriesCatalog(state)};
  });
 }
 async assign(owner,id,body){
  fields(body,['request_id','series','expected_series']);
  return this.service.idem(owner,'card-series:assign:'+id,body,state=>{
   const versions=Object.hasOwn(state.cards,id)?state.cards[id]:null;
   if(!versions?.length)fail('NOT_FOUND','未找到原卡；衍生卡的卡包请在来源卡上修改。',404);
   if(versions[0].owner_id!==owner&&!isAdmin(state,owner))fail('FORBIDDEN','只能修改自己卡牌的卡包。',403);
   if(cardSeries(versions[0])!==body.expected_series)fail('REVISION_CONFLICT','卡牌卡包已变化，请刷新后重试。',409);
   const series=requireSeries(state,body.series);
   for(const card of versions)card.series=series;
   audit(state,owner,'card_series_assign',`${id}:${series}`);
   return {card_id:id,series};
  });
 }
}
