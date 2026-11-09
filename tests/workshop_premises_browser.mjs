import {createServer} from 'node:net';
const reservation=createServer();await new Promise(r=>reservation.listen(0,'127.0.0.1',r));const port=reservation.address().port;await new Promise(r=>reservation.close(r));
import assert from 'node:assert/strict';
import {mkdtemp,rm,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createApp} from '../server/src/index.js';
import {FACTION_ID,seedFactions} from '../server/test/faction_fixture.js';
const {default:puppeteer}=await import(pathToFileURL('C:/Users/ASUS/Desktop/桌面/Project Sun/Web/card-submission/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js'));
let rounds=0;
const provider={configured:true,model:'browser-fixture',async generate({kind,context,onAttempt}){await onAttempt();if(kind==='mechanism-review'){rounds++;return {result:{status:'review',formal_text:rounds===1?'敌方单位数多于友方时，己方抽2张牌；触发时机待确认。':'登场时，若敌方在场单位数多于友方，己方抽2张牌。',questions:rounds===1?[{id:'when',question:'在什么时机判断？',options:['登场时','回合开始']}]:[],missing_capabilities:[]},metadata:{}};}
 return {result:{status:'ok',card:{schema_version:'1.0.0',ruleset_version:'frontline-1',...Object.fromEntries(Object.entries(context.card_blueprint).filter(([k])=>k!=="effect_mode")),flavor_text:'',appearance:{emblem:'infantry'},abilities:[{trigger:'on_play',premise:{test:'compare',left:{stat:'enemy_unit_count'},cmp:'gt',right:{stat:'friendly_unit_count'}},effects:[{op:'draw',player:'owner',amount:2}]}]},explanation:'若敌方单位更多，抽2张牌',assumptions:[]},metadata:{}};}};
const dir=await mkdtemp(join(tmpdir(),'chao-ui-premises-'));const app=await createApp({dataDir:dir,centralMode:true,matches:false,provider,inviteToken:'browser-review-test-only',browserOrigins:[`http://127.0.0.1:${port}`]});let browser;
try{
 await seedFactions(app.service.store);await app.listen(port);const owner=await app.auth.register({invite_code:'browser-review-test-only',display_name:'测试员'},'local');
 browser=await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-first-run']});
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.setViewport({width:412,height:915,isMobile:true,hasTouch:true});
 const code=app.auth.browserSession(owner.owner_id).code;await page.goto(`http://127.0.0.1:${port}/workshop/#login=${code}&route=edit`,{waitUntil:'networkidle0'});await page.waitForSelector('[data-base="name"]');
 await page.type('[data-base="name"]','以寡敌众');await page.select('[data-base="faction_id"]',FACTION_ID);await page.type('#source','敌方单位比友方多，抽2张牌');await page.click('[data-action="generate"]');
 await page.waitForSelector('[data-answer]');assert.equal(await page.$('[data-action="confirm-interpretation"]'),null);assert.equal(await page.$('.mechanism-pass'),null);
 await page.click('[data-action="answer-option"]');await page.click('[data-action="revise-interpretation"]');await page.waitForSelector('[data-action="confirm-interpretation"]');assert.equal(await page.$('.mechanism-pass'),null);
 await page.click('[data-action="confirm-interpretation"]');await page.waitForSelector('.mechanism-pass',{timeout:15000});assert.match(await page.$eval('.mechanism-pass',e=>e.textContent),/通过/);assert.match(await page.$eval('.premise-summary',e=>e.textContent),/敌方单位数大于友方单位数/);
 assert.equal(Object.keys(app.service.store.state.cards).length,0);assert.equal(Object.keys(app.service.store.state.mechanism_components).length,0);
 assert(await page.$$eval('.mechanism-turn',els=>els.length)>=5);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.$eval('#ai-panel',n=>n.scrollIntoView({block:'start'}));await mkdir('.runtime',{recursive:true});await page.screenshot({path:'.runtime/0823-workshop-pass-mobile.png'});
 await page.reload({waitUntil:'networkidle0'});await page.waitForSelector('.mechanism-pass');
 await page.click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));assert.equal(Object.keys(app.service.store.state.cards).length,1);assert.equal(Object.keys(app.service.store.state.mechanism_components).length,2);
 await page.$eval('[data-base="attack"]',n=>{n.value='3';n.dispatchEvent(new Event('input',{bubbles:true}));});assert.equal(await page.$('.mechanism-pass'),null);
 assert.deepEqual(errors,[]);console.log('WORKSHOP_PREMISE_DIALOGUE_PASS');
}finally{await browser?.close();await app.close();await rm(dir,{recursive:true,force:true});}
