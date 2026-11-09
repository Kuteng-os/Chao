import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRequire} from 'node:module';
import {createApp} from '../server/src/index.js';
const {chromium}=createRequire(import.meta.url)('C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fixture=JSON.parse(await readFile(new URL('text844-fixtures.json',import.meta.url),'utf8'));
const dataDir=await mkdtemp(join(tmpdir(),'chao-ui844-')),origin='http://127.0.0.1:38144';
const app=await createApp({dataDir,host:'127.0.0.1',centralMode:true,inviteToken:'local-only-844-check-123456789',matches:false,browserOrigins:[origin],provider:{configured:false,model:'test'}});let browser;
try{
 await app.listen(38144);const owner=await app.auth.accounts.register({username:'UITester',password:'local-only-844-test-password'},'local');
 await app.service.store.transaction(s=>{
  s.keywords=fixture.keywords;
  for(const c of fixture.cards)s.cards[c.card_id]=[{...c,owner_id:owner.owner_id,art:null}];
  s.factions['40afae76-e05e-4471-92ce-b48ff89d58a1']={faction_id:'40afae76-e05e-4471-92ce-b48ff89d58a1',name:'R公司',role:'major',color:'#384839',icon_id:null,revision:1,owner_id:owner.owner_id};
 });
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));await page.goto(origin+'/workshop/#login='+app.auth.browserSession(owner.owner_id).code+'&route=cards');await page.locator('.archive-face').first().waitFor();
 assert(await page.locator('.archive-rules strong').count()>0);assert(!await page.locator('.archive-rules').allTextContents().then(xs=>xs.some(x=>x.includes('仅继承'))));
 await page.screenshot({path:'.runtime/844-web-desktop.png'});
 await page.setViewportSize({width:412,height:915});await page.screenshot({path:'.runtime/844-web-mobile.png',fullPage:false});
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1));assert.deepEqual(errors,[]);
 console.log('PRESENTATION844_BROWSER_PASS: compact existing cards, bold keywords, responsive layout, no JS errors');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
