import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createApp} from '../server/src/index.js';
import {FACTION_ID,seedFactions} from '../server/test/faction_fixture.js';
const {default:puppeteer}=await import(pathToFileURL('C:/Users/ASUS/Desktop/桌面/Project Sun/Web/card-submission/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js'));
const dataDir=await mkdtemp(join(tmpdir(),'frontline-generated-'));
const app=await createApp({dataDir,host:'127.0.0.1',centralMode:true,inviteToken:'local-generated-test-only-123456789',matches:false,browserOrigins:['http://127.0.0.1:38118']});let browser;
try{
 await seedFactions(app.service.store);await app.listen(38118);const owner=await app.auth.accounts.register({username:'GeneratedTester',password:'test-password-12345'},'local');
 browser=await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-first-run']});const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.setViewport({width:1440,height:1050});
 await page.goto(`http://127.0.0.1:38118/workshop/#login=${app.auth.browserSession(owner.owner_id).code}&route=edit`,{waitUntil:'networkidle0'});
 const fill=async(selector,value)=>page.$eval(selector,(n,v)=>{n.value=v;n.dispatchEvent(new Event('input',{bubbles:true}));},value),click=selector=>page.locator(selector).click();
 await fill('[data-base="name"]','三种衍生卡');await page.select('[data-base="faction_id"]',FACTION_ID);
 await page.evaluate(()=>{for(const d of document.querySelectorAll('details'))d.open=true;});
 for(const [i,kind] of ['unit','order','counter'].entries()){
  await click('[data-action="add-token"]');await fill(`[data-token="name"][data-index="${i}"]`,['装甲援军','紧急补给','伏击'][i]);
  if(kind!=='unit')await page.select(`[data-token="kind"][data-index="${i}"]`,kind);
  await fill(`[data-token="cost"][data-index="${i}"]`,String(i));
  if(kind==='unit'){await page.select('[data-add-token-ref="0"]','standard.heavy_armor@1');await fill('[data-token-param="x"]','3');}
  await click(`[data-action="add-ability"][data-mode="token:${i}"]`);
  if(kind==='counter'){await page.select('[data-token="counter_trigger"][data-index="2"]','enemy_order_played');await page.select('[data-effect="op"][data-mode="token:2"]','cancel_action');}
 }
 const ids=await page.$$eval('[data-token-editor] details code',ns=>ns.map(n=>n.textContent));assert.equal(ids.length,3);
 await click('[data-action="add-ability"][data-mode="card"]');
 for(let i=0;i<3;i++){
  if(i)await click('[data-action="add-effect"][data-mode="card"]');
  await page.select(`[data-effect="op"][data-mode="card"][data-ei="${i}"]`,'create_card');await page.select(`[data-effect="token_id"][data-mode="card"][data-ei="${i}"]`,ids[i]);
 }
 await click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存 · v1'));await page.waitForNetworkIdle({idleTime:150});
 const saved=app.catalog.cards(owner.owner_id).cards[0];assert.deepEqual(saved.definition.tokens.map(t=>t.kind),['unit','order','counter']);assert.deepEqual(saved.definition.tokens.map(t=>t.cost),[0,1,2]);assert.equal(saved.definition.tokens[0].keywords[0].params.x,3);assert.equal(saved.definition.tokens[0].abilities[0].trigger,'on_summon');assert.equal(saved.definition.tokens[1].abilities[0].trigger,'on_play');assert.equal(saved.definition.tokens[2].abilities[0].effects[0].op,'cancel_action');assert(saved.definition.abilities[0].effects.every(e=>e.op==='create_card'));
 await click('[data-action="remove-token"][data-index="0"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('仍被效果引用'));assert.equal(await page.$$eval('[data-token-editor]',ns=>ns.length),3);
 await page.setViewport({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:'.runtime/generated086-web-mobile.png',fullPage:true});assert.deepEqual(errors,[]);
 console.log('WORKSHOP_GENERATED_PASS: three kinds, costs, registered armor, triggers, references, single save, protected deletion, mobile');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
