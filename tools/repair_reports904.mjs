// Service must be stopped; caller makes an exact backup before invoking.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
const messages={
 'CZ-000281':'已新增重甲 v2，支持 1～100 层，实际战斗不会截断到 10。请打开原草稿，移除旧版重甲后重新添加“重甲”（v2），再填写 100。原卡与旧词条版本未改写。',
 'CZ-000282':'固定受伤修正现支持 -100～100。减伤 100 是扣除固定 100 点，超出的伤害仍生效；战斗限定不影响技能伤害。可按原意重新校验，无需拆成十个 -10。',
 'CZ-000283':'已支持交换攻防：选择任意一方场上单位，一次性交换当前攻击力与剩余防御力，持续本次在场期间。不能选择总部；原攻击为 0 时交换后正常阵亡。请继续原会话并重新校验。'
};
const store=new Store(process.argv[2]);await store.init();
try{const result=await store.transaction(s=>Object.values(s.diagnostics??{}).filter(d=>messages[d.number]&&d.status!=='resolved').map(d=>markResolved(s,d,{resolution:messages[d.number],version:'0.9.4'})));console.log('REPORTS_RESOLVED',JSON.stringify(result));}finally{await store.close();}
