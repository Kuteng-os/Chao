import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {createApp} from '../server/src/index.js';
import {freshCard} from '../web/model.mjs';
import {sins} from '../web/sins.mjs';
import {FACTION_ID,factionFixture} from '../server/test/faction_fixture.js';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const dataDir=await mkdtemp(join(tmpdir(),'chao-sin840-')),origin='http://127.0.0.1:38140';
const app=await createApp({dataDir,host:'127.0.0.1',centralMode:true,inviteToken:'sin840-only-test-123456789012',matches:false,browserOrigins:[origin],provider:{configured:false,model:'test'}});let browser;
try{
 await app.listen(38140);const owner=await app.auth.accounts.register({username:'SinTester',password:'test-sin-12345678'},'local');
 app.service.store.state.factions[FACTION_ID]={...factionFixture(),icon_id:'e'.repeat(64)};
 for(const sin of sins){const draft=await app.service.manualDraft(owner.owner_id,{request_id:randomUUID(),definition:{...freshCard(),name:sin.name+'试验兵',sin:sin.id,faction_id:FACTION_ID}});await app.service.confirmCard(owner.owner_id,{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash});}
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/v1/card-art/'+ 'e'.repeat(64)+'.png',async r=>r.fulfill({contentType:'image/png',body:await readFile(new URL('../web/sins/gluttony.png',import.meta.url))}));
 await page.goto(origin+'/workshop/#login='+app.auth.browserSession(owner.owner_id).code+'&route=edit');
 assert.equal(await page.locator('[data-base="sin"]').inputValue(),'');assert.equal(await page.locator('[data-base="faction_id"]').inputValue(),'');
 await page.locator('[data-base="name"]').fill('中性试验兵');assert.equal(await page.locator('#preview-body .archive-face').getAttribute('data-faction-color'),'#303538');
 await page.locator('[data-base="faction_id"]').selectOption(FACTION_ID);
 await page.locator('[data-base="sin"]').selectOption('wrath');assert.equal(await page.locator('#preview-body .archive-faction img').getAttribute('src'),'/v1/card-art/'+'e'.repeat(64)+'.png');
 await page.locator('[data-base="sin"]').selectOption('');assert.equal(await page.locator('#preview-body .archive-faction img').count(),1);
 await page.locator('[data-base="faction_id"]').selectOption('');assert.equal(await page.locator('#preview-body .archive-faction img').count(),0);
 await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'),null,{timeout:10000}).catch(async e=>{throw new Error(await page.locator('#notice').innerText());});
 assert.equal(app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='中性试验兵').definition.sin,null);
 await page.goto(origin+'/workshop/#cards');await page.locator('[data-catalog-filter="sin"]').waitFor();assert.equal(await page.locator('.catalog-entry').count(),8);
 for(const img of await page.locator('.archive-faction img').all()){await img.scrollIntoViewIfNeeded();await img.evaluate(i=>i.decode());}
 await page.screenshot({path:'D:/工程/Chao/.runtime/sins840-web.png',fullPage:true});
 await page.locator('[data-catalog-filter="sin"]').selectOption('envy');assert.equal(await page.locator('.catalog-entry').count(),1);assert.match(await page.locator('.archive-title h3').innerText(),/嫉妒/);
 await page.locator('[data-catalog-filter="sin"]').selectOption('none');assert.equal(await page.locator('.catalog-entry').count(),1);
 await page.locator('[data-action="edit-card"]').click();await page.locator('[data-base="sin"]').selectOption('gloom');await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));
 const c=app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='中性试验兵');assert.equal(c.definition.sin,'gloom');assert.equal(app.catalog.card(owner.owner_id,c.card_id,1).definition.sin,null);
 await page.setViewportSize({width:390,height:844});await page.locator('[data-base="sin"]').scrollIntoViewIfNeeded();await page.screenshot({path:'D:/工程/Chao/.runtime/sins840-mobile.png'});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 assert.deepEqual(errors,[]);console.log('SINS840_BROWSER_PASS: faction icons retained with seven sin colors, dark/neutral colors, independent optional selectors, save/revise/frozen blank, search intersection, phone');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
