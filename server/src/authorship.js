import {createHash} from 'node:crypto';
export function authorFor(state, owner) {
  if(!owner)return null;
  const identity=state.identities?.[owner];
  return {id:createHash('sha256').update('frontline-author:'+owner).digest('hex').slice(0,24),name:identity?.display_name??'未署名'};
}
