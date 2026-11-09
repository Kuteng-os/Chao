import {fail} from './codec.js';

// Check narrowly unambiguous instructions. General prose still goes through the
// player's review/confirmation; these guards do not invent missing conditions.
export function checkMechanismIntent(source, expanded) {
  const text=String(source??'').replace(/\s+/g,'');
  const abilities=expanded.abilities??[];
  if(/压制(?:并|和|与|及)抑制/.test(text)){
    const effects=abilities.flatMap(a=>a.effects);
    if(!['pin','suppress'].every(op=>effects.some(e=>e.op===op)))
      fail('INTENT_MECHANISM_MISMATCH','压制和抑制是两个独立效果，必须同时保留 pin 与 suppress。',422);
  }
  const direction=text.match(/(?<!不|勿)(?:消灭|摧毁)(?:场上)?(?:单位)?(?:数量)?(?:较|更)(多|少)(?:的)?(?:一)?方/)?.[1]
    ??text.match(/单位(?:数量)?(多|少)的一方(?:所有|全部)?(?:在场)?单位(?:全部)?(?:被)?消灭/)?.[1];
  if(!direction)return;
  for(const [index,a] of abilities.entries()){
    const p=a.premise;
    if(p?.test!=='compare'||!['gt','lt'].includes(p.cmp))continue;
    const left=p.left?.stat,right=p.right?.stat;
    if(!['friendly_unit_count','enemy_unit_count'].includes(left)||!['friendly_unit_count','enemy_unit_count'].includes(right)||left===right)continue;
    const greater=p.cmp==='gt'?left:right;
    const affected=direction==='多'?greater:(greater==='friendly_unit_count'?'enemy_unit_count':'friendly_unit_count');
    const expected=affected==='friendly_unit_count'?'all_friendly_units':'all_enemy_units';
    if(a.effects.some(e=>e.op==='destroy'&&['all_friendly_units','all_enemy_units'].includes(e.target)&&e.target!==expected))
      fail('INTENT_MECHANISM_MISMATCH',`第${index+1}个效果组把较${direction}方写反了；比较条件满足时应消灭${expected==='all_friendly_units'?'己方':'敌方'}单位。`,422,[{code:'INTENT_MECHANISM_MISMATCH',path:`/abilities/${index}`,message:'请按条件左右两方及 gt/lt 重新核对消灭目标和对应总部；不能将较多方改为较少方。'}]);
  }
}
