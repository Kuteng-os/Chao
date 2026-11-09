import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createApp} from '../server/src/index.js';
import {FACTION_ID,seedFactions} from '../server/test/faction_fixture.js';
import {DeepSeekProvider} from '../server/src/provider.js';
import {freshCard} from '../web/model.mjs';
const {default:puppeteer}=await import(pathToFileURL('C:/Users/ASUS/Desktop/桌面/Project Sun/Web/card-submission/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js'));
const dataDir=await mkdtemp(join(tmpdir(),'frontline-stacks-')),calls=[];
const provider=new DeepSeekProvider({apiKey:'local-fixture-only',fetch:async(url,options)=>{
 const body=JSON.parse(options.body),context=JSON.parse(body.messages[1].content);calls.push(context);
 assert.equal(body.thinking.type,'enabled');assert.equal(body.reasoning_effort,'high');
 let result;
 if(context.target_kind){const n=context.review_history.length?2:1;result={status:'review',formal_text:`登场时获得重甲${n}，持续本次在场期间。受到攻击或反击时减少${n}点伤害，不消耗层数；技能伤害不受影响。`,questions:[],missing_capabilities:[]};}
 else result={status:'ok',card:{...freshCard(),...context.card_blueprint,abilities:[{trigger:'on_play',effects:[{op:'modify_stacks',target:'self',stack:'heavy_armor',amount:2,duration:'battle'}]}]},explanation:'登场时获得重甲2。',assumptions:[]};
 if(result.card)delete result.card.effect_mode;
 return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify(result)}}]}));
}});
const app=await createApp({dataDir,host:'127.0.0.1',port:0,centralMode:true,inviteToken:"local-stacks-test-only-123456789",matches:false,browserOrigins:['http://127.0.0.1:38116'],provider});let browser;
try{
 await seedFactions(app.service.store);await app.listen(38116);const owner=await app.auth.accounts.register({username:'StackTester',password:'test-password-12345'},'local');
 browser=await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-first-run']});const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.setViewport({width:1440,height:1050});
 const code=app.auth.browserSession(owner.owner_id).code;await page.goto(`http://127.0.0.1:38116/workshop/#login=${code}&route=edit`,{waitUntil:'networkidle0'});
 const fill=async(selector,value)=>page.$eval(selector,(n,v)=>{n.value=v;n.dispatchEvent(new Event('input',{bubbles:true}));},value),click=selector=>page.locator(selector).click();
 await fill('[data-base="name"]','层数机制测试');await page.select('[data-base="faction_id"]',FACTION_ID);
 await fill('#source','登场时获得重甲1');await click('[data-action="generate"]');await page.waitForSelector('[data-action="confirm-interpretation"]');
 assert.equal(Object.keys(app.service.store.state.drafts).length,0);assert.match(await page.$eval('.mechanism-review',n=>n.textContent),/重甲1/);
 await fill('[data-review-feedback]','改为重甲2，其他不变');await click('[data-action="revise-interpretation"]');await page.waitForFunction(()=>document.querySelector('.mechanism-review')?.textContent.includes('重甲2'));
 assert.equal(calls[1].review_history[0].feedback,'改为重甲2，其他不变');assert.equal(Object.keys(app.service.store.state.cards).length,0);
 await page.screenshot({path:'.runtime/stacks084-review-desktop.png',fullPage:true});await page.setViewport({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:'.runtime/stacks084-review-mobile.png',fullPage:true});
 await click('[data-action="confirm-interpretation"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('效果已添加'));
 assert.equal(Object.keys(app.service.store.state.cards).length,0);assert.equal(await page.$eval('[data-effect="amount"]',n=>Number(n.value)),2);assert.equal(await page.$eval('[data-base="attack"]',n=>Number(n.value)),2);
 await click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存 · v1'));await page.waitForNetworkIdle({idleTime:150});
 const saved=app.catalog.cards(owner.owner_id).cards[0];assert.equal(saved.definition.abilities[0].effects[0].amount,2);
 await click('[data-action="new-card"]');await page.select('#add-ref','standard.heavy_armor@1');await fill('[data-param="x"]','3');assert.match(await page.$eval('#card-json',n=>n.value),/"x": 3/);
 assert.deepEqual(errors,[]);console.log('WORKSHOP_STACKS_PASS: high thinking, formal review, multi-round revision, confirmation, append, save, reusable layers, mobile layout');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
