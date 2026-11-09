import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {createApp} from '../server/src/index.js';
import {freshCard} from '../web/model.mjs';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const dataDir=await mkdtemp(join(tmpdir(),'chao-report841-')),origin='http://127.0.0.1:38141';
const app=await createApp({dataDir,host:'127.0.0.1',centralMode:true,inviteToken:"report841-local-only-123456789",matches:false,browserOrigins:[origin],provider:{configured:false,model:'test'}});let browser;
try{
 await app.listen(38141);const owner=await app.auth.accounts.register({username:'ReportTester',password:'local-test-12345678'},'local');
 const draft=await app.service.manualDraft(owner.owner_id,{request_id:randomUUID(),definition:{...freshCard(),name:'最后的孵化'}});
 const hatch=await app.service.confirmCard(owner.owner_id,{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash});
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage({viewport:{width:412,height:915}}),errors=[];let generationRequests=0;
 page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(r.method()==='POST'&&/mechanism-reviews|card-generations/.test(r.url()))generationRequests++;});
 await page.goto(origin+'/workshop/#login='+app.auth.browserSession(owner.owner_id).code+'&route=edit');
 await page.locator('[data-action="card-kind"][data-kind="hq"]').click();await page.locator('[data-base="name"]').fill('超限总部');
 await page.locator('[data-base="health"]').fill('101');await page.locator('#source').fill('每回合开始抽一张牌');
 await page.locator('[data-action="generate"]').click();assert.match(await page.locator('#notice').innerText(),/1—100/);assert.equal(generationRequests,0);assert.equal(await page.locator('[data-base="health"]').inputValue(),'101');
 await page.locator('[data-action="save-card"]').click();assert.match(await page.locator('#notice').innerText(),/1—100/);
 await page.locator('[data-base="health"]').fill('100');await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));
 const fixtures=JSON.parse(await readFile(new URL('fixtures841.json',import.meta.url),'utf8')).cards;
 async function load(c){await page.locator('details').filter({has:page.locator('#card-json')}).locator('summary').click();await page.locator('#card-json').fill(JSON.stringify(c));await page.locator('[data-action="load-json"]').click();}
 await load(fixtures[2].definition);await page.locator('[data-damage-mode]').selectOption('gap');await page.locator('[data-damage-gap="reduction"]').fill('2');await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));
 await load(fixtures[1].definition);await page.locator('[data-premise="kind"]').selectOption('enemy_turn');assert.match(await page.locator('.premise-summary').first().innerText(),/对方回合/);
 await load(fixtures[3].definition);await page.locator('[data-inherit-policy]').selectOption('none');await page.locator('[data-inherit-source]').selectOption(hatch.card_id);assert.match(await page.locator('[data-effect-json="inherit_from"]').inputValue(),/最后的孵化/);
 const latest=JSON.parse(await readFile(new URL('latest841.json',import.meta.url),'utf8')).cards;
 await load(latest[2].definition);assert.equal(await page.locator('[data-delay-turns]').inputValue(),'2');await page.locator('[data-delay-turns]').fill('3');
 await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));
 assert.equal(app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='延迟抽牌').definition.abilities[1].after_turns,3);
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:'D:/工程/Chao/.runtime/reports841-mobile.png'});
 assert.deepEqual(errors,[]);console.log('REPORTS841_BROWSER_PASS: preflight no provider call, input retained, HQ100 saves, damage gap, turn condition, copy source picker, delayed turns, phone layout');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
