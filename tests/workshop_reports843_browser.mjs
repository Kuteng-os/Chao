import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {createApp} from '../server/src/index.js';
import {freshCard} from '../web/model.mjs';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const dataDir=await mkdtemp(join(tmpdir(),'chao-report841-')),origin='http://127.0.0.1:38143';
const app=await createApp({dataDir,host:'127.0.0.1',centralMode:true,inviteToken:"report841-local-only-123456789",matches:false,browserOrigins:[origin],provider:{configured:false,model:'test'}});let browser;
try{
 await app.listen(38143);const owner=await app.auth.accounts.register({username:'ReportTester',password:'local-test-12345678'},'local');
 await app.service.store.transaction(state=>{state.factions['408c3c32-19c5-49ce-9a9d-055c38d516ba']={faction_id:'408c3c32-19c5-49ce-9a9d-055c38d516ba',revision:1,name:'剑',role:'major',color:'#30412f',icon_id:null,owner_id:owner.owner_id};});
 const draft=await app.service.manualDraft(owner.owner_id,{request_id:randomUUID(),definition:{...freshCard(),name:'最后的孵化'}});
 const hatch=await app.service.confirmCard(owner.owner_id,{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash});
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage({viewport:{width:412,height:915}}),errors=[];let generationRequests=0;
 page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(r.method()==='POST'&&/mechanism-reviews|card-generations/.test(r.url()))generationRequests++;});
 await page.goto(origin+'/workshop/#login='+app.auth.browserSession(owner.owner_id).code+'&route=edit');

 const fixtures=JSON.parse(await readFile(new URL('reports843.json',import.meta.url),'utf8')).cards;
 async function load(c){await page.locator('details').filter({has:page.locator('#card-json')}).locator('summary').click();await page.locator('#card-json').fill(JSON.stringify(c));await page.locator('[data-action="load-json"]').click();}
 async function save(){await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));}
 await load(fixtures[0].definition);
 await page.locator('[data-effect="overflow"]').selectOption('');await save();
 assert(!app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='阵亡回顶').definition.abilities[0].effects[0].overflow);
 await page.locator('[data-effect="overflow"]').selectOption('deck_top');await save();
 assert.equal(app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='阵亡回顶').definition.abilities[0].effects[0].overflow,'deck_top');
 await load(fixtures[3].definition);await page.locator('[data-effect="per_unit"]').selectOption('false');await save();
 assert.equal(app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='按击杀加防御').definition.abilities[0].effects[1].per_unit,false);
 await page.locator('[data-effect="per_unit"]').selectOption('true');await save();
 assert.equal(app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='按击杀加防御').definition.abilities[0].effects[1].per_unit,true);
 const hand=structuredClone(fixtures[5].definition);hand.abilities[0].effects[0].filter.faction_id='408c3c32-19c5-49ce-9a9d-055c38d516ba';
 await load(hand);await page.locator('[data-card-filter="faction_id"]').selectOption('');await page.locator('[data-card-filter="faction_id"]').selectOption('408c3c32-19c5-49ce-9a9d-055c38d516ba');await save();
 assert.equal(app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='元素灵').definition.abilities[0].effects[0].duration,'hand');
 await load(fixtures[1].definition);await page.locator('details').filter({has:page.locator('[data-card-bonuses]')}).locator('summary').click();
 await page.locator('[data-card-bonuses]').fill('[{"filter":{"keyword_id":"core.guard"},"amount":3}]');await page.locator('[data-card-bonuses]').blur();await save();
 assert.equal(app.catalog.cards(owner.owner_id).cards.find(c=>c.definition.name==='烈焰').definition.damage_bonuses[0].amount,3);
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:'D:/工程/Chao/.runtime/reports843-mobile.png'});
 assert.deepEqual(errors,[]);console.log('REPORTS843_BROWSER_PASS: overflow toggle, kill-count boolean, faction hand cost selection, damage bonus editing, mobile layout');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
