import {generateKeyPairSync,sign} from 'node:crypto';
import {writeFileSync} from 'node:fs';
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const files=Object.fromEntries(['pck','exe','apk'].map(ext=>[ext,{path:'/v1/client-files/Frontline-0.8.0.'+ext,bytes:4,sha256:'0'.repeat(64)}]));
function envelope(build,extra={}){const payload=JSON.stringify({schema:1,build,version:'0.8.'+(build-800),minimum_base_build:801,patch_abi:'frontline-4.7-1',files,...extra});return {payload,signature:sign('RSA-SHA256',Buffer.from(payload),privateKey).toString('base64')};}
writeFileSync(new URL('../tests/fixtures/updates853.json',import.meta.url),JSON.stringify({public_key:publicKey.export({format:'pem',type:'spki'}),older:envelope(852),current:envelope(853),newer:envelope(854),invalid_minimum:envelope(854,{minimum_base_build:855}),invalid_build:envelope(799)}));
