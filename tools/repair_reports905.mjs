// Run only with service stopped and an exact backup.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
const store=new Store(process.argv[2]);await store.init();
try{await store.transaction(s=>{const report=Object.values(s.diagnostics).find(d=>d.number==='CZ-000284');if(!report)throw Error('Report missing');if(report.status!=='resolved')markResolved(s,report,{version:'0.9.5',resolution:'已补齐主动能力：己方回合内手动发动，每回合一次，免费且不占攻击或移动次数。玉黄龙可选择友方玉石兽阵营、尚有自身进化安排的单位，立即完成该次进化。请继续原会话重新校验或生成，将主动能力加在玉黄龙衍生形态上。电脑右键或手机长按单位，在详情中发动。'});});console.log('CZ-000284_RESOLVED');}finally{await store.close();}
