// Run with the service stopped and a fresh store backup. Card definitions and conversations are preserved.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
const store=new Store(process.argv[2]??'/var/lib/frontline/data');await store.init();
const evolution='已支持单位在原阵线、原位置进化为衍生单位；可选择不继承或仅继承永久强化，旧单位不触发阵亡，新单位结算召唤效果。请继续原会话确认尚未提供的触发条件与进化目标。';
const jade='已支持玉化：在场单位于入场后的第三个己方回合开始，在原位置进化为指定衍生单位，不继承强化和伤害；原卡进入弃牌堆、不触发阵亡，新卡触发召唤。各张来源卡需配置其进化衍生卡，原澄清答案保留，可继续生成。';
const cancel='已支持登场后使对手下一张指令无效，持续至消耗；指令正常支付费用，不退费，不因本单位离场而消失。请继续原会话生成。';
const resolutions={114:evolution,115:evolution,116:cancel,117:jade,118:cancel,119:jade,120:jade,121:jade,
122:'已支持指令绑定本次选择的单位，在己方每回合开始持续造成伤害；目标离场后停止，不会重新选目标。可继续原会话完善并生成点燃。',
123:'已修复能力触发次数上限过低的问题，现支持1至999次，并保留单次结算预算。原输入和对话保留，可继续校验。',
124:'已支持每累计损失2点防御，延迟到指定回合为原单位增加1层重甲；只在该单位仍在场时结算，不改变阵亡复制的永久强化继承规则。请继续原会话确认下回合指己方还是对方回合。'};
try{const done=await store.transaction(s=>{const done=[];for(const d of Object.values(s.diagnostics??{})){const message=resolutions[Number(d.number.slice(3))];if(message&&d.status!=='resolved'){markResolved(s,d,{resolution:message,version:'0.8.48'});done.push(d.number);}}return done;});console.log(JSON.stringify({reports:done}));}finally{await store.close();}
