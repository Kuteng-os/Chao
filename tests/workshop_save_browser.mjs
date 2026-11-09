import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {randomUUID} from 'node:crypto';
import {createApp} from '../server/src/index.js';
import {FACTION_ID,seedFactions} from '../server/test/faction_fixture.js';
const {default:puppeteer}=await import(pathToFileURL('C:/Users/ASUS/Desktop/桌面/Project Sun/Web/card-submission/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js'));
const dataDir=await mkdtemp(join(tmpdir(),'frontline-save-'));
const app=await createApp({dataDir,host:'127.0.0.1',port:0,centralMode:true,inviteToken:'local-save-test-only-123456789',matches:false,browserOrigins:['http://127.0.0.1:38113'],provider:{configured:false}});
let browser;
try{
 await seedFactions(app.service.store);await app.listen(38113);
 const a=await app.auth.accounts.register({username:'OriginalAuthor',password:'test-password-12345'},'local');
 const b=await app.auth.accounts.register({username:'SaveTester',password:'test-password-12345'},'local');
 await app.service.store.transaction(s=>{s.accounts[Object.keys(s.accounts).find(k=>s.accounts[k].owner_id===b.owner_id)].role='admin';});
 const def={schema_version:'1.0.0',ruleset_version:'frontline-1',name:'他人上次的卡牌',faction_id:FACTION_ID,flavor_text:'不要带入新卡',kind:'unit',unit_class:'tank',cost:6,operation_cost:2,attack:5,health:4,keywords:[{id:'core.guard',version:1,params:{}}],play_target:null,tokens:[],abilities:[],appearance:{emblem:'tank'}};
 const d=(await app.service.manualDraft(a.owner_id,{request_id:randomUUID(),definition:def})).result;
 const original=await app.service.confirmCard(a.owner_id,{request_id:randomUUID(),draft_id:d.draft_id,draft_hash:d.draft_hash});
 browser=await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-first-run']});
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.setViewport({width:1440,height:1050});
 const code=app.auth.browserSession(b.owner_id).code;
 await page.goto(`http://127.0.0.1:38113/workshop/#login=${code}&route=edit&card=${original.card_id}`,{waitUntil:'networkidle0'});
 const click=selector=>page.locator(selector).click();
 const val=selector=>page.$eval(selector,n=>n.value);
 const fill=async(selector,value)=>page.$eval(selector,(n,v)=>{n.value=v;n.dispatchEvent(new Event('input',{bubbles:true}));},value);
 const blank=async()=>{assert.equal(await val('[data-base="name"]'),'');assert.equal(await val('[data-base="cost"]'),'3');assert.equal(await page.$('.version-note'),null);assert.equal(await page.$('.keyword-chip'),null);assert.equal(await val('#source'),'');assert.equal(await page.$$eval('[data-action="save-card"]',n=>n.length),1);assert.equal(await page.$('[data-action="preview"],[data-action="publish"]'),null);};
 assert.equal(await val('[data-base="name"]'),def.name);
 for(const selector of ['.hero-actions [data-action="new-card"]','.nav-link[data-action="new-card"]','button[data-action="new-card"]']){
  await click(selector);await page.waitForFunction(()=>document.querySelector('[data-base="name"]')?.value==='');await blank();
  await fill('[data-base="name"]','临时内容');await fill('#source','登场抽三张');
 }
 await click('button[data-action="new-card"]');await blank();
 await click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('阵营'));assert.equal(app.catalog.cards(b.owner_id).cards.length,1);
 await fill('[data-base="name"]','独立的新卡');await page.select('[data-base="faction_id"]',FACTION_ID);
 await click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存 · v1'));
 let all=app.catalog.cards(b.owner_id).cards;assert.equal(all.length,2);
 const created=all.find(x=>x.definition.name==='独立的新卡');assert.notEqual(created.card_id,original.card_id);assert.equal(created.author.name,'SaveTester');assert.equal(app.catalog.card(a.owner_id,original.card_id,1).definition.name,def.name);
 await click('[data-action="save-card"]');assert.equal(app.catalog.cards(b.owner_id).cards.find(x=>x.card_id===created.card_id).revision,1);
 await fill('[data-base="attack"]','7');await click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存 · v2'));
 assert.equal(app.catalog.card(b.owner_id,created.card_id,1).definition.attack,2);assert.equal(app.catalog.card(b.owner_id,created.card_id,2).definition.attack,7);
 // An old local revision must not reappear when opening the creation page again.
 await page.reload({waitUntil:'networkidle0'});await blank();
 await click('a[href="#cards"]');await page.waitForSelector(`[data-action="edit-card"][data-id="${original.card_id}"]`);
 await click(`[data-action="edit-card"][data-id="${original.card_id}"]`);await page.waitForFunction(()=>document.querySelector('[data-base="name"]')?.value==='他人上次的卡牌');
 await fill('[data-base="name"]','明确修改的旧卡');await click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存 · v2'));
 assert.equal(app.catalog.card(b.owner_id,original.card_id,2).author.name,'OriginalAuthor');
 // Delay validation, then start a new editor. A stale reply cannot publish or populate it.
 await click('button[data-action="new-card"]');await fill('[data-base="name"]','已放弃的校验');await page.select('[data-base="faction_id"]',FACTION_ID);
 let held,intercepted;const seen=new Promise(resolve=>intercepted=resolve);
 await page.setRequestInterception(true);page.on('request',r=>{if(r.url().endsWith('/v1/card-drafts')){held=r;intercepted();}else r.continue();});
 await click('[data-action="save-card"]');await seen;
 await click('.hero-actions [data-action="new-card"]');await held.continue();
 await page.waitForFunction(()=>document.querySelector('[data-action="save-card"]')?.disabled===false);await blank();assert.equal(app.catalog.cards(b.owner_id).cards.length,2);
 await page.setViewport({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.screenshot({path:'.runtime/fix082-web-mobile.png',fullPage:true});assert.deepEqual(errors,[]);
 console.log('WORKSHOP_SAVE_PASS: fresh entries, explicit edit, one save, validation, authors/revisions, no duplicate saves, stale request isolation, reload, mobile');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
