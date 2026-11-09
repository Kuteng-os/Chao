import {tokenArtIds} from './card_art.js';
import {resolveCard} from './derived_cards.js';
import {compileCard} from './validation.js';
import {fail,hash} from './codec.js';
// A headquarters is a separate frozen public card, never part of the draw pile.
export function headquartersFor(state,ref){
 if(ref==null)return null;
 if(!ref||typeof ref!=='object'||Array.isArray(ref)||Object.keys(ref).sort().join()!=='card_id,definition_hash,revision'||typeof ref.card_id!=='string'||!Number.isInteger(ref.revision)||ref.revision<1||typeof ref.definition_hash!=='string')fail('INVALID_HEADQUARTERS','总部版本引用无效。',422);
 const card=resolveCard(state,ref.card_id,ref.revision);
 if(!card||card.definition.kind!=='hq'||card.definition_hash!==ref.definition_hash||hash(card.definition)!==ref.definition_hash)fail('INVALID_HEADQUARTERS','请选择已登记的总部卡版本。',422);
 if(compileCard(card.definition,state.keywords).compiled_program_hash!==card.compiled_program_hash)fail('INVALID_HEADQUARTERS','总部规则校验失败。',422);
 return card;
}
export function headquartersEnvelope(card){return card?{token_art_ids:tokenArtIds(card),definition:structuredClone(card.definition),definition_hash:card.definition_hash,compiled_program_hash:card.compiled_program_hash,telemetry_ref:{card_id:card.card_id,revision:card.revision},...(card.art?{art_id:card.art.id}:{})}:null;}
