import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {createApp} from '../server/src/index.js';
import {derivedId} from '../server/src/derived_cards.js';
import {freshCard} from '../web/model.mjs';
import {FACTION_ID,seedFactions} from '../server/test/faction_fixture.js';
const require=createRequire(import.meta.url),{PNG}=require('../server/node_modules/pngjs');
const {chromium}=require('C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const dir=await mkdtemp(join(tmpdir(),'chao-art839-')),origin='http://127.0.0.1:38139';
const app=await createApp({dataDir:dir,host:'127.0.0.1',port:38139,centralMode:true,inviteToken:"art839-fixture-only-123456789012",matches:false,browserOrigins:[origin],provider:{configured:false,model:'test'}});
let browser;
try{
 await seedFactions(app.service.store);await app.listen(38139);
 const owner=await app.auth.accounts.register({username:'ArtTester',password:'test-art-12345678'},'local');
 const p={...freshCard(),name:'卡图母卡',faction_id:FACTION_ID,tokens:[{token_id:'child',name:'独立卡图衍生兵',unit_class:'infantry',attack:2,health:3,keywords:[]},{token_id:'other',name:'另一个衍生兵',unit_class:'tank',attack:3,health:4,keywords:[]}]};
 const draft=await app.service.manualDraft(owner.owner_id,{request_id:randomUUID(),definition:p});
 const saved=await app.service.confirmCard(owner.owner_id,{request_id:randomUUID(),draft_id:draft.result.draft_id,draft_hash:draft.result.draft_hash});
 const childId=derivedId(saved.card_id,'child');
 const fixture=new PNG({width:1000,height:700});for(let y=0;y<700;y++)for(let x=0;x<1000;x++){const i=(y*1000+x)*4;fixture.data[i]=x<500?200:20;fixture.data[i+1]=x<500?50:160;fixture.data[i+2]=80;fixture.data[i+3]=x<60?0:255;}
 const upload={name:'derived.png',mimeType:'image/png',buffer:PNG.sync.write(fixture)};
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:960}}),errors=[];page.on('pageerror',e=>errors.push(e.message));let uploads=0;page.on('request',r=>{if(r.url().endsWith('/v1/card-art')&&r.method()==='POST')uploads++;});
 await page.goto(origin+'/workshop/#login='+app.auth.browserSession(owner.owner_id).code+'&route=edit&card='+childId);
 await page.locator('[data-token="cost"]').fill('2');assert.match(await page.locator('.token-art-preview .archive-cost').innerText(),/^2/);
 await page.locator('[data-token-art-file="child"]').setInputFiles(upload);await page.locator('.card-crop-dialog').waitFor();await page.getByRole('button',{name:'取消',exact:true}).click();assert.equal(uploads,0);
 await page.locator('[data-token-art-file="child"]').setInputFiles(upload);await page.locator('.card-crop-dialog').waitFor();
 await page.screenshot({path:'D:/工程/Chao/.runtime/art839-crop.png'});
 await page.getByRole('button',{name:'使用此卡面'}).click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('卡面已上传'));
 assert.equal(uploads,1);assert.equal(await page.locator('.token-art-preview .archive-art-image').count(),1);
 await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));
 let child=app.catalog.card(owner.owner_id,childId);assert(child.art?.id);const imageId=child.art.id;
 assert.equal(app.catalog.card(owner.owner_id,saved.card_id).art,undefined);assert.equal(app.catalog.card(owner.owner_id,derivedId(saved.card_id,'other')).art,null);
 await page.goto(origin+'/workshop/#cards');await page.locator(`[data-action="edit-card"][data-id="${childId}"]`).click();
 assert.equal(await page.locator('.token-art-preview .archive-art-image').getAttribute('src'),'/v1/card-art/'+imageId+'.png');
 await page.setViewportSize({width:360,height:740});await page.locator('[data-action="recrop-art"]').click();await page.locator('.card-crop-dialog').waitFor();await page.getByRole('button',{name:'完整图片',exact:true}).click();
 await page.locator('.card-crop-dialog').evaluate(d=>d.scrollTop=d.scrollHeight);const bounds=await page.getByRole('button',{name:'使用此卡面'}).boundingBox();assert(bounds.y>=0&&bounds.y+bounds.height<=740);
 await page.screenshot({path:'D:/工程/Chao/.runtime/art839-mobile.png'});await page.getByRole('button',{name:'使用此卡面'}).click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('卡面已上传'));
 await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));
 assert.equal(app.catalog.card(owner.owner_id,childId,2).art.id,imageId);
 await page.locator('[data-action="remove-art"]').click();await page.locator('[data-action="save-card"]').click();await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('已保存'));
 assert.equal(app.catalog.card(owner.owner_id,childId).art,null);assert.equal(app.catalog.card(owner.owner_id,childId,2).art.id,imageId);
 assert.deepEqual(errors,[]);console.log('ART839_BROWSER_PASS: independent derived upload, cancel, full-card crop, preview, save, reload, phone, recrop, removal, frozen art and unchanged parent/sibling');
}finally{await browser?.close();await app.close();await rm(dir,{recursive:true,force:true});}

