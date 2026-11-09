// Apply only after validation, with service stopped and a fresh store backup.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const directory=process.argv[2]??'/var/lib/frontline/data';
const original=JSON.parse(readFileSync(join(directory,'store.json'),'utf8'));
const store=new Store(directory);await store.init();
const notes={
127:'已支持攻击前事件与本次攻击目标的攻防读取。请继续原会话确认结算时点、持续时间及读取当前还是初始数值。',
128:'已支持按本牌本次实际消灭数量判断后续效果，不计其他来源的击杀。',
129:'阵亡可按击杀来源的陆军或空军兵种分支判断，包含双方同时阵亡时的来源快照。',
130:'已支持本回合每次友方单位攻击敌方总部后抽牌；回合结束监听失效。',
131:'已支持本回合每次友方单位攻击敌方总部后抽牌；回合结束监听失效。',
132:'已支持本回合每次友方单位入场时抽牌，包含部署、召唤及控制权转入。',
133:'已支持本回合每次友方单位入场时抽牌，包含部署、召唤及控制权转入。',
134:'已支持给指定单位附加攻击后效果，并可选择在场、本回合或永久持续。请在原会话确认总部恢复还是增加当前防御及上限。',
135:'已支持事件能力的每回合次数上限，可组合敌方阵亡、召唤和守护。请继续确认尚未填写的次数或持续规则。',
136:'已支持按目标当前攻击力奇偶筛选。',137:'已支持按目标当前攻击力奇偶筛选。',
138:'已支持临时控制，保留单位实例与伤害，到期归还原控制者。请继续确认一回合的截止时点。',
140:'已验证指定同一敌方单位、压制与抉择分支可组合，分支继续使用原先选择的目标。',
141:'已修复空白修改意见触发无效请求的问题；填写修改意见或澄清答案后才会提交。',
142:'已支持按阵线筛选双方单位并撤退。',
143:'已修复取消后立即重新生成时的请求竞态，现在会等待上次取消完成再提交。',
144:'已支持按当前位置查询相邻守护单位，总部会隔开相邻关系。',
145:'已支持查询友方场上是否存在守护单位。',
146:'已支持按友方在场单位当前防御数值判断前提。',
147:'已支持先增加防御，再将目标攻击设为增加后的当前防御，一次性锁定。',
148:'已支持先增加防御，再将目标攻击设为增加后的当前防御，一次性锁定。',
149:'已修复选择一张手牌移回牌库后的数量结算，并支持一次抽5张牌。',
150:'已支持按双方单位当前防御低于指定数值筛选并施加效果。',
151:'已支持按双方单位当前防御低于指定数值筛选并施加效果。',
152:'已支持筛选敌方前线单位并撤退。',
153:'攻击后可将本次被攻击单位的攻击设为其当前防御；目标已离场时跳过。',
154:'攻击后可将本次被攻击单位的攻击设为其当前防御；目标已离场时跳过。'
};
try{const reports=await store.transaction(s=>{for(const k of Object.keys(s))delete s[k];Object.assign(s,structuredClone(original));const done=[];for(const d of Object.values(s.diagnostics??{})){const text=notes[Number(d.number.slice(3))];if(text&&d.status!=='resolved'){markResolved(s,d,{resolution:text+' 原卡与对话保留，可继续原会话生成。',version:'0.8.50'});done.push(d.number);}}return done;});console.log(JSON.stringify({reports}));}finally{await store.close();}
