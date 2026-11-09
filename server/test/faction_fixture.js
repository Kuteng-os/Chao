// Isolated fixture only. Production starts with an empty player-created registry.
export const FACTION_ID='11111111-1111-4111-8111-111111111111';
export const factionFixture=()=>({faction_id:FACTION_ID,revision:1,name:'测试主阵营',role:'major',color:'#456247',icon_id:null,owner_id:'test-fixture'});
export async function seedFactions(store){await store.transaction(state=>{state.factions[FACTION_ID]??=factionFixture();});}
