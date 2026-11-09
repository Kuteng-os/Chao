// Run on the trusted server. Publishes through the normal API without editing store.json.
// The private journal holds a dedicated non-admin test identity; never distribute it.
import {readFile,writeFile,rename,mkdir} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {request as httpsRequest} from 'node:https';
import {request as httpRequest} from 'node:http';
import {randomUUID} from 'node:crypto';
import {genericTestDeck,TEST_DECK_NAME} from './generic_test_deck.mjs';

export async function publishTestDeck(request,journal,save,invite) {
  if(!journal.session) {
    // A normal legacy content-author identity, with no administrator privileges.
    journal.session=await request('/v1/sessions',{invite_code:invite,display_name:'测试牌组'});
    await save();
  }
  const call=(path,body)=>request(path,body,journal.session.access_token);
  const idem=async(key,path,body)=>{
    if(!journal.operations[key]) {journal.operations[key]={path,body:{request_id:randomUUID(),...body}};await save();}
    const op=journal.operations[key];
    if(op.path!==path||JSON.stringify({...op.body,request_id:undefined})!==JSON.stringify({...body,request_id:undefined}))throw Error('Test deck changed; use a new journal instead of replacing published content.');
    if(!op.result){op.result=await call(op.path,op.body);await save();}
    return op.result;
  };
  const faction=await idem('faction','/v1/factions',{name:'测试演习',role:'major',color:'#627b69',icon_id:null});
  const specs=genericTestDeck(faction.faction_id),cards=[],refs=[];
  for(const [i,spec] of specs.entries()) {
    const draft=(await idem('draft-'+i,'/v1/card-drafts',{definition:spec.definition})).result;
    const card=await idem('card-'+i,'/v1/cards',{draft_id:draft.draft_id,draft_hash:draft.draft_hash});
    cards.push({name:card.definition.name,card_id:card.card_id,revision:card.revision,count:spec.count});
    for(let n=0;n<spec.count;n++)refs.push({card_id:card.card_id,revision:card.revision,definition_hash:card.definition_hash});
  }
  if(refs.length!==40)throw Error('Expected a 40 card test deck');
  const deck=await idem('deck','/v1/decks',{name:TEST_DECK_NAME,cards:refs,main_faction_id:faction.faction_id,ally_faction_id:'',main_sin:'wrath',ally_sin:'gloom'});
  const published=await request('/v1/public/decks/'+deck.deck_id);
  if(published.deck.cards.length!==40||published.cards.length!==specs.length||published.deck.name!==TEST_DECK_NAME)throw Error('Published deck verification failed');
  return {deck_id:deck.deck_id,name:deck.name,card_count:refs.length,unique_cards:cards.length,main_faction:faction.name,cards};
}

async function main() {
  const [base,caPath,journalPath]=process.argv.slice(2);
  if(!base||!caPath||!journalPath||!process.env.REGISTRATION_INVITE_TOKEN)throw Error('Expected API origin, CA path, private journal path and server invite environment.');
  const origin=new URL(base),ca=await readFile(caPath);
  if(origin.protocol!=='https:'&&!(origin.protocol==='http:'&&origin.hostname==='127.0.0.1'))throw Error('Use trusted HTTPS');
  let journal;
  try{journal=JSON.parse(await readFile(journalPath,'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;journal={schema:1,origin:origin.origin,operations:{}};}
  if(journal.schema!==1||journal.origin!==origin.origin)throw Error('Journal origin mismatch');
  const save=async()=>{await mkdir(dirname(journalPath),{recursive:true,mode:0o700});await writeFile(journalPath+'.tmp',JSON.stringify(journal),{mode:0o600});await rename(journalPath+'.tmp',journalPath);};
  const request=(path,body,token)=>new Promise((accept,reject)=>{
    const payload=body===undefined?null:JSON.stringify(body);
    const req=(origin.protocol==='https:'?httpsRequest:httpRequest)(new URL(path,origin),{ca,autoSelectFamily:false,method:payload?'POST':'GET',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),'X-Frontline-Client-Build':'807'},...(process.env.FRONTLINE_API_CONNECT_ADDRESS?{lookup:(_hostname,_options,callback)=>callback(null,process.env.FRONTLINE_API_CONNECT_ADDRESS,4)}:{})},res=>{
      let text='';res.setEncoding('utf8');res.on('data',chunk=>text+=chunk);res.on('end',()=>{try{const result=JSON.parse(text);if(res.statusCode>=400)throw Error(path+' '+res.statusCode+' '+JSON.stringify(result.error));accept(result);}catch(error){reject(error);}});
    });
    req.setTimeout(30000,()=>req.destroy(Error('API timeout')));req.on('error',reject);req.end(payload);
  });
  console.log(JSON.stringify(await publishTestDeck(request,journal,save,process.env.REGISTRATION_INVITE_TOKEN),null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)await main();

