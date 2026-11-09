import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {createApp} from '../server/src/index.js';
import {ADMIN_NAMES} from '../server/src/accounts.js';
const root=fileURLToPath(new URL('../',import.meta.url)),dir=await mkdtemp(join(tmpdir(),'frontline-account-game-'));
const app=await createApp({dataDir:join(dir,'server'),host:'127.0.0.1',port:0,matches:false,centralMode:true,inviteToken:'isolated-invite-not-production-123',registrationMode:'open',provider:{configured:false,model:'test',async generate(){throw Error('No model calls');}}});
try{
 const addr=await app.listen();await app.auth.accounts.bootstrap(ADMIN_NAMES.map(username=>({username,password:'isolated-test-password-123'})));
 const child=spawn(process.env.GODOT_BIN??'D:/工程/GT/Godot_v4.7-stable_win64.exe',['--headless','--path',root,'--script','tests/test_accounts.gd'],{windowsHide:true,stdio:'inherit',env:{...process.env,FRONTLINE_PROFILE_PATH:join(dir,'profile.json'),FRONTLINE_TEST_SERVER_URL:`http://127.0.0.1:${addr.port}`}});
 const timeout=setTimeout(()=>child.kill(),60000);try{process.exitCode=(await new Promise((resolve,reject)=>{child.once('exit',resolve);child.once('error',reject);}))===0?0:1;}finally{clearTimeout(timeout);}
}finally{await app.close();await rm(dir,{recursive:true,force:true});}
