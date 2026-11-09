import {randomBytes, scrypt, timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
import {fail} from './codec.js';
const derive=promisify(scrypt), params={N:32768,r:8,p:1,maxmem:64*1024*1024};
export function checkPassword(password) {
  if (typeof password!=='string' || [...password].length<10 || [...password].length>128 || /[\u0000-\u001f\u007f]/u.test(password)) fail('INVALID_REQUEST','密码需要 10～128 个字符，不能包含控制字符。',400);
}
export async function passwordHash(password) {
  checkPassword(password);
  const salt=randomBytes(16).toString('hex'), value=await derive(password,salt,32,params);
  return {algorithm:'scrypt-32768-8-1',salt,hash:value.toString('hex')};
}
export async function passwordMatches(password, record) {
  if (typeof password!=='string' || password.length>512) return false;
  const valid=record?.algorithm==='scrypt-32768-8-1'&&/^[0-9a-f]{32}$/.test(record.salt)&&/^[0-9a-f]{64}$/.test(record.hash);
  const expected=Buffer.from(valid?record.hash:'0'.repeat(64),'hex');
  const actual=await derive(password,valid?record.salt:'0'.repeat(32),32,params);
  return timingSafeEqual(actual,expected)&&valid;
}
