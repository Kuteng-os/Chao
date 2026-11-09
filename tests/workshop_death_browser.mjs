import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createApp} from '../server/src/index.js';
import {FACTION_ID,seedFactions} from '../server/test/faction_fixture.js';
import {makePrompt,DeepSeekProvider} from '../server/src/provider.js';
import {validateKeyword,docsURL} from '../server/src/validation.js';
const {default:puppeteer}=await import(pathToFileURL('C:/Users/ASUS/Desktop/桌面/Project Sun/Web/card-submission/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js'));
const dataDir=await mkdtemp(join(tmpdir(),'frontline-death-'));
const example=JSON.parse(await readFile(new URL('examples/keywords/example_last_salvo.json',docsURL),'utf8'));
const provider=new DeepSeekProvider({apiKey:'local-fixture-only',fetch:async(url,options)=>{
 const body=JSON.parse(options.body),context=JSON.parse(body.messages[1].content);
 assert.match(body.messages[0].content,/source_base_health/);assert.match(body.messages[0].content,/已完整支持/);
 if(context.target_kind){return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify({status:'review',formal_text:context.source_text,questions:[],missing_capabilities:[]})}}]}));}
 const definition={...structuredClone(example),id:context.assigned_id,version:context.assigned_version};
 return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify({status:'candidate',definition})}}]}),{headers:{'Content-Type':'application/json'}});
}});
assert.match(makePrompt('keyword',[]),/on_death.*target/);
const app=await createApp({dataDir,host:'127.0.0.1',port:0,centralMode:true,inviteToken:'local-death-test-only-123456789',matches:false,browserOrigins:['http://127.0.0.1:38115'],provider});
let browser;
try{
 await seedFactions(app.service.store);await app.listen(38115);
 const owner=await app.auth.accounts.register({username:'DeathTester',password:'test-password-12345'},'local');
 browser=await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-first-run']});
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.setViewport({width:1440,height:1050});
 const code=app.auth.browserSession(owner.owner_id).code;
 await page.goto(`http://127.0.0.1:38115/workshop/#login=${code}&route=edit`,{waitUntil:'networkidle0'});
 const fill=async(selector,value)=>page.$eval(selector,(n,v)=>{n.value=v;n.dispatchEvent(new Event('input',{bubbles:true}));},value);
 await fill('[data-base="name"]','动态阵亡测试');await page.select('[data-base="faction_id"]',FACTION_ID);
 await page.click('[data-action="add-ability"]');await page.select('[data-trigger]','on_death');await page.select('[data-effect="op"]','damage');
 await page.select('[data-effect="target"]','chosen');await page.select('[data-amount-kind]','source_base_health');
 assert.equal(await page.$eval('[data-death-target="side"]',n=>n.value),'enemy');assert.equal(await page.$('[data-target="side"]'),null);
 await page.click('[data-action="save-card"]');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存 · v1'));
 const saved=app.catalog.cards(owner.owner_id).cards[0];assert.equal(saved.definition.play_target,null);assert.deepEqual(saved.definition.abilities,example.implementation.abilities);assert.match(saved.rules_text,/初始防御力/);
 await page.waitForNetworkIdle({idleTime:150});
 // A changed trigger removes only the death selector; changing back restores it.
 await page.select('[data-trigger]','on_play');assert.equal(await page.$('[data-death-target]'),null);await page.select('[data-trigger]','on_death');
 await page.click('a[href="#keyword"]');await page.waitForSelector('#keyword-source');
 await fill('[data-keyword="name"]','最后一击');
 await fill('#keyword-source','阵亡时对敌方一个单位造成等同于这张卡初始防御力数值的伤害');
 await page.locator('[data-action="generate-keyword"]').click();
 await page.waitForSelector('[data-action="confirm-interpretation"]');
 await page.locator('[data-action="confirm-interpretation"]').click();
 await page.waitForFunction(()=>document.querySelector('[data-action="confirm-keyword"]')!==null,{timeout:10000}).catch(async e=>{throw new Error(e.message+' '+await page.$eval('#notice',n=>n.textContent)+' '+JSON.stringify(Object.values(app.service.store.state.generations).map(j=>({status:j.status,error:j.error}))));});
 await page.click('[data-action="confirm-keyword"]');
 await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('登记'));
 const registered=app.service.keywords().definitions.find(e=>e.definition.name==='最后一击');assert(registered);validateKeyword(registered.definition);
 assert.deepEqual(registered.definition.implementation.abilities,example.implementation.abilities);
 await page.setViewport({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.screenshot({path:'.runtime/death083-web-mobile.png',fullPage:true});assert.deepEqual(errors,[]);
 console.log('WORKSHOP_DEATH_PASS: dynamic editor, save, target scope, official adapter contract, generation, confirmation, registration, mobile');
}finally{await browser?.close();await app.close();await rm(dataDir,{recursive:true,force:true});}
