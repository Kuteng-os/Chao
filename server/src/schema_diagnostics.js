// Improve validation errors without changing the wire contract or accepted values.
export function discriminate(schema) {
  if (!schema || typeof schema !== 'object') return schema;
  if (Array.isArray(schema)) return schema.map(discriminate);
  const result = Object.fromEntries(Object.entries(schema).map(([key, value]) => [key, discriminate(value)]));
  const branches = result.oneOf;
  if (branches?.length) {
    const keys = Object.keys(branches[0].properties || {});
    const key = keys.find(k => branches.every(b => typeof b.properties?.[k]?.const === 'string' && b.required?.includes(k)) && new Set(branches.map(b => b.properties[k].const)).size === branches.length);
    if (key) result.discriminator = {propertyName: key};
  }
  return result;
}

const labels = {limit:'累计触发次数',after_turns:'延迟回合数',lifetime:'持续条件',inherit:'继承强化',times:'总触发次数',counter_trigger:'反制触发条件',rarity:'稀有度',name:'名称',description:'描述',flavor_text:'风味描述',cost:'部署费用',operation_cost:'行动费用',attack:'攻击',health:'防御',kind:'类型',unit_class:'兵种',op:'效果类型',trigger:'触发时机',target:'目标',amount:'数量',player:'玩家',attack_delta:'攻击变化',health_delta:'防御变化',duration:'持续时间',attacks:'每回合攻击次数',cost_delta:'行动费变化',multiplier:'伤害倍率',against:'针对兵种',applies_to:'生效阶段',token_id:'衍生单位',keyword_id:'词条',keyword_version:'词条版本',play_target:'登场目标',side:'阵营',row:'战线',version:'版本',id:'编号',aliases:'别名',minimum:'下限',maximum:'上限',schema_version:'数据版本',ruleset_version:'规则版本',param:'参数名',abilities:'效果组',effects:'效果',tokens:'衍生单位',keywords:'词条'};
const values = {on_summon:'被召唤时',create_card:'生成到手牌',counter:'反制',on_reveal:'反制触发时',trigger_unit:'触发单位',enemy_unit_deployed:'对方部署单位后',enemy_order_played:'对方打出指令时',enemy_hq_attacked:'对方攻击己方总部时',unit:'单位',order:'指令',infantry:'步兵',tank:'坦克',artillery:'炮兵',fighter:'战斗机',bomber:'轰炸机',owner:'己方',opponent:'对方',battle:'在场期间',end_of_turn:'当前回合结束',on_play:'登场',own_turn_start:'己方回合开始',own_turn_end:'己方回合结束',on_death:'阵亡',self:'自身',chosen:'选定单位',any:'任意',ally:'友方',enemy:'敌方',front:'前线',support:'支援阵线'};
const decode = part => part.replaceAll('~1','/').replaceAll('~0','~');
const encode = part => part.replaceAll('~','~0').replaceAll('/','~1');
const at = (value, path) => path.split('/').slice(1).reduce((v,k) => v?.[decode(k)], value);
export function fieldName(path) {
  const parts = path.split('/').slice(1).map(decode), result=[];
  for (let i=0;i<parts.length;i++) {
    const key=parts[i];
    if (['card','definition','card_blueprint','implementation'].includes(key)) continue;
    if (['abilities','effects','tokens','keywords','aliases'].includes(key) && /^\d+$/.test(parts[i+1] || '')) { result.push(`${labels[key]} ${Number(parts[++i])+1}`); continue; }
    if (['params','parameters'].includes(key) && parts[i+1]) { result.push(`参数 ${parts[++i]}`); continue; }
    result.push(labels[key] || key);
  }
  return result.join(' · ') || '定义';
}

export function diagnose(errors, value) {
  const details=[];
  for (const error of errors) {
    if (['if','oneOf','anyOf'].includes(error.keyword)) continue;
    const p=error.params;
    let path=error.instancePath, message;
    if (error.keyword==='required') path+='/'+encode(p.missingProperty);
    if (error.keyword==='additionalProperties') path+='/'+encode(p.additionalProperty);
    if (error.keyword==='discriminator') path+='/'+encode(p.tag);
    const name=fieldName(path);
    // The integer-or-parameter union also emits a failed object alternative.
    if (error.keyword==='type' && /\/(oneOf|anyOf)\//.test(error.schemaPath) && ['object','string'].includes(p.type) && typeof at(value,path)==='number') continue;
    switch(error.keyword) {
      case 'required': message=`请填写${name}。`;break;
      case 'minLength': message=p.limit===1?`${name}不能为空。`:`${name}至少需要 ${p.limit} 个字符。`;break;
      case 'maxLength': message=`${name}最多 ${p.limit} 个字符。`;break;
      case 'minimum': message=`${name}不能小于 ${p.limit}。`;break;
      case 'maximum': message=`${name}不能大于 ${p.limit}。`;break;
      case 'minItems': message=`${name}至少需要 ${p.limit} 项。`;break;
      case 'maxItems': message=`${name}最多 ${p.limit} 项。`;break;
      case 'maxProperties': message=`${name}最多 ${p.limit} 项。`;break;
      case 'type': message=`${name}必须是${{integer:'整数',string:'文字',array:'列表',object:'对象',null:'空值',boolean:'布尔值'}[p.type]??p.type}。`;break;
      case 'const': message=`${name}必须为 ${values[p.allowedValue]??p.allowedValue}。`;break;
      case 'enum': message=`${name}请选择：${p.allowedValues.map(v=>values[v]??v).join('、')}。`;break;
      case 'additionalProperties': message=`${name}不是允许的字段。`;break;
      case 'pattern': message=`${name}格式不正确。`;break;
      case 'uniqueItems': message=`${name}不能包含重复项。`;break;
      case 'discriminator': message=`${name}未填写或不受支持。`;break;
      default: message=`${name}不符合规则。`;
    }
    if (!details.some(d=>d.path===path&&d.message===message)) details.push({path,code:'INVALID_SCHEMA',message});
  }
  return details.length?details.slice(0,8):[{path:'',code:'INVALID_SCHEMA',message:'定义结构不正确，请检查 JSON 字段。'}];
}
