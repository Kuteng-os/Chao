// Execute with the service stopped, as its service account, after tests and backup.
import {Store} from '../server/src/store.js';
import {markResolved} from '../server/src/diagnostics.js';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const directory=process.argv[2]??'/var/lib/frontline/data';
const original=JSON.parse(readFileSync(join(directory,'store.json'),'utf8'));
const groups=[
 [[155,156],'已支持暂时移除单位并于回合结束回原位置，保留伤害与已用行动，不触发阵亡。'],
 [[157,158,159],'已支持暂时拘留单位，来源任何方式离场时归还到手牌，并可将归还牌费用设为0。'],
 [[160,161],'已支持按罪孽筛选单位，暴食等七种罪孽可用于群体效果与前提计数。'],
 [[162,163],'已支持按部署费用筛选，并在移除后读取本次选择目标的原归属，决定是否抽牌。'],
 [[164],'已支持每次友方单位攻击后的监听及次数上限，包含监听者自身的攻击。'],
 [[165],'已支持随机敌方目标包含总部；仅单位目标仍可单独选择。'],
 [[166],'攻击后可按本次攻击目标的兵种判断，即使该目标已经阵亡也可读取其快照。'],
 [[167],'战斗伤害修正可以查询目标当前是否具有守护。'],
 [[168,169,170,171,172],'已支持反制的触发单位及其相邻单位、触发时另选目标、逐目标读取行动费或攻击力，以及统一和空军分类伤害上限。'],
 [[173],'已支持执行指定单位的阵亡效果而不消灭该单位。'],
 [[174],'受到伤害后可读取本次实际损失的防御，用于增加攻击和恢复总部。'],
 [[175],'已支持从手牌检索并召唤单位，真实移走该手牌实例。'],
 [[176],'抉择可先选择分支，再选择该分支自己的目标；敌方单位与友方步兵可以使用不同筛选。'],
 [[177,180,181,189],'已修复进化编辑默认空衍生标识的问题，并增加每张卡可选形态的词条参数。请在原草稿选定已有衍生形态；缺少形态时仍需补齐，不能引用不存在的模板。'],
 [[178,179],'已修复延迟回合数和重复次数被表单保存为字符串的问题，空白可选数值也不会写入无效值。'],
 [[182],'衍生单位可召唤自己的最初母卡原型，使用母卡原定义、卡图和音效。'],
 [[183],'单位筛选已兼容 kind:unit，并支持常用兵种、名称、费用和罪孽筛选。'],
 [[186,187],'已支持立即执行指定单位自己已安排的进化，使用该单位自己的衍生形态并消费对应延迟任务；无进化任务时跳过。'],
 [[188],'单张卡及每个衍生模板扩展至8个能力组、24个操作，总计96个操作，仍保留执行预算与结构校验。'],
 [[190],'已支持查询牌库顶费用奇偶，不移动牌；空牌库不满足条件。'],
 [[191],'已支持将本组刚抽到的实际手牌实例洗回牌库，不会误取之前同名手牌，牌库数量正常增加。'],
 [[192,193],'已支持按交战目标攻击力高于自身的条件修正战斗攻击；可限定仅主动攻击。'],
 [[194],'已支持只增加防御上限、不恢复当前防御，之后可正常治疗至新上限。'],
 [[195],'事件能力可指定第几次满足条件后触发，首次坦克部署与第二次坦克部署可以分别配置。'],
 [[196],'已区分撤退与一般回手事件，并支持监听撤退后的强化和次数上限。请继续原对话确认尚未指定的次数和持续时间。'],
 [[197,198],'已支持各玩家自己的回合序号与失去当前指挥点，可组合下个敌方回合扣费及第6回合后的条件加扣。']
];
const notes=Object.fromEntries(groups.flatMap(([ids,text])=>ids.map(id=>[id,text])));
if(Object.keys(notes).length!==42)throw Error('Unexpected report set');
const store=new Store(directory);await store.init();
try{
 const reports=await store.transaction(s=>{
  for(const key of Object.keys(s))delete s[key];Object.assign(s,structuredClone(original));
  const done=[];
  for(const d of Object.values(s.diagnostics??{})){
   const text=notes[Number(d.number.slice(3))];
   if(text&&d.status!=='resolved'){markResolved(s,d,{resolution:text+' 原卡与对话保留，请继续原会话重新生成或校验。',version:'0.8.51'});done.push(d.number);}
  }
  return done;
 });
 console.log(JSON.stringify({reports}));
}finally{await store.close();}
