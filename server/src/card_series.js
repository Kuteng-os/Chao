// Release metadata stays outside frozen gameplay definitions and their hashes.
import {fail} from './codec.js';
export const CURRENT_CARD_SERIES=2;
const valid=n=>Number.isSafeInteger(n)&&n>=1&&n<=9999;
export const defaultSeriesName=n=>n===1?'第一期':n===2?'第二期':`第${n}期`;
export const cardSeries=card=>valid(card?.series)?card.series:1;
export function currentCardSeries(state){const n=state.card_series?.current;return valid(n)?n:CURRENT_CARD_SERIES;}
export function initializeCardSeries(state){
 const previous=state.card_series??{};
 state.card_series={...previous,current:currentCardSeries(state),revision:Number.isSafeInteger(previous.revision)&&previous.revision>=1?previous.revision:1,names:{...previous.names}};
 for(const versions of Object.values(state.cards??{})){
  const series=cardSeries(versions[0]);
  for(const card of versions)card.series=series;
 }
 for(const id of seriesCatalog(state).available)state.card_series.names[id]??=defaultSeriesName(id);
}
export function seriesCatalog(state){
 const available=[...new Set([1,CURRENT_CARD_SERIES,currentCardSeries(state),...Object.keys(state.card_series?.names??{}).map(Number).filter(valid),...Object.values(state.cards??{}).flat().map(cardSeries)])].sort((a,b)=>a-b);
 return {current:currentCardSeries(state),available,revision:state.card_series?.revision??1,entries:available.map(id=>({id,name:state.card_series?.names?.[id]??defaultSeriesName(id)}))};
}
export function requireSeries(state,value){
 if(!valid(value)||!seriesCatalog(state).available.includes(value))fail('INVALID_SERIES','请选择已登记的卡包。',400);
 return value;
}
