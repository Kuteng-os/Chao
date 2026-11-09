import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createApp} from '../server/src/index.js';
import {FACTION_ID,seedFactions} from '../server/test/faction_fixture.js';
import {DeepSeekProvider} from '../server/src/provider.js';
const {default:puppeteer}=await import(pathToFileURL('C:/Users/ASUS/Desktop/桌面/Project Sun/Web/card-submission/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js'));
const dataDir=await mkdtemp(join(tmpdir(),'frontline-deck-'));
const effect={op:'summon_from_deck',card_name:'玉石',amount:1};
const provider=new DeepSeekProvider({apiKey:'local-fixture-only',fetch:async(url,options)=>{
 const body=JSON.parse(options.body),context=JSON.parse(body.messages[1].content);assert.equal(body.thinking.type,'enabled');assert.match(body.messages[0].content,/卡名不是词条/);
 const result=context.target_kind?{status:'review',formal_text:'阵亡时，从己方牌组召唤一张名为“玉石”的单位到后援线；无匹配或后援线已满时不生效。',questions:[],missing_capabilities:[]}:{status:'candidate',definition:{schema_version:'1.0.0',ruleset_version:'frontline-1',id:context.assigned_id,version:context.assigned_version,name:context.suggested_name,description:'阵亡时从己方牌组召唤一张玉石单位。',aliases:[],parameters:{},implementation:{kind:'template',abilities:[{trigger:'on_death',effects:[effect]}]}}};
 return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify(result)}}]}));
}});
const app=await createApp({dataDir,host:'127.0.0.1',port:0,centralMode:true,inviteToken:'local-deck-test-only-123456789',matches:false,browserOrigins:['http://127.0.0.1:38117'],provider});let browser;
try{
 await seedFactions(app.service.store);await app.listen(38117);const owner=await app.auth.accounts.register({username:'DeckTester',password:'test-password-12345'},'local');
 browser=await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-first-run']});const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.setViewport({width:1440,height:1050});
 const code=app.auth.browserSession(owner.owner_id).code;await page.goto(`http://127.0.0.1:38117/workshop/#login=${code}&route=edit`,{waitUntil:'networkidle0'});
 const fill=async(selector,value)=>page.$eval(selector,(n,v)=>{n.value=v;n.dispatchEvent(new Event('input',{bubbles:true}));},value),click=selector=>page.locator(selector).click();
 await fill('[data-base="name"]','遗赠测试');await page.select('[data-base="faction_id"]',FACTION_ID);await click('[data-action="add-ability"]');await page.select('[data-trigger]','on_death');await page.select('[data-effect="op"]','summon_from_deck');await fill('[data-effect="card_name"]','玉石');
 await click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存 · v1'));await page.waitForNetworkIdle({idleTime:150});
 const saved=app.catalog.cards(owner.owner_id).cards[0];assert.deepEqual(saved.definition.abilities[0].effects,[effect]);assert.equal(saved.definition.tokens.length,0);assert.match(saved.rules_text,/玉石/);
 await click('a[href="#keyword"]');await page.waitForSelector('#keyword-source');await fill('[data-keyword="name"]','玉石遗赠');await fill('#keyword-source','阵亡时从卡组召唤一张【玉石】单位');await click('[data-action="generate-keyword"]');await page.waitForSelector('[data-action="confirm-interpretation"]');
 assert.match(await page.$eval('.mechanism-review',n=>n.textContent),/玉石/);await click('[data-action="confirm-interpretation"]');await page.waitForSelector('[data-action="confirm-keyword"]');await click('[data-action="confirm-keyword"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('登记'));
 const registered=app.service.keywords().definitions.find(e=>e.definition.name==='玉石遗赠');assert(registered);assert.deepEqual(registered.definition.implementation.abilities[0].effects,[effect]);
 await page.setViewport({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:'.runtime/deck085-web-mobile.png',fullPage:true});assert.deepEqual(errors,[]);
 console.log('WORKSHOP_DECK_PASS: named editor, single save, formal review, confirm, independent keyword registration, mobile');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
