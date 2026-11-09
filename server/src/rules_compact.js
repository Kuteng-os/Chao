export function compactRules(text){
 const names=[];text=text.replace(/【[^】]*】/g,value=>`\uE000${names.push(value)-1}\uE001`);
 text=text.replace(/的\s*点伤害/g,'的伤害').replace(/(\d)\s+(点|张|个|回合)/g,'$1$2');
 text=text.replace(/(己方|敌方)在场单位数大于(敌方|己方)在场单位数/g,'$1在场单位更多').replace(/(己方|敌方)在场单位数小于(敌方|己方)在场单位数/g,'$1在场单位更少').replace(/(?:己方在场单位数等于敌方在场单位数|敌方在场单位数等于己方在场单位数)/g,'双方在场单位一样多');
 // Pin and suppression do not need a duplicated target sentence. Preserve side order.
 text=text.replace(/压制所有友方单位，直至其后续\s*(\d+)\s*个回合结束；(?:然后)?压制所有敌方单位，直至其后续\s*\1\s*个回合结束/g,'压制所有单位（各自后续 $1 回合）');
 text=text.replace(/抑制所有友方单位；(?:然后)?抑制所有敌方单位/g,'抑制所有单位');
 text=text.replace(/压制所有友方单位（各自后续(\d+)回合结束时解除）；压制所有敌方单位（各自后续\1回合结束时解除）/g,'压制所有单位（各自后续$1回合结束时解除）');
 text=text.replace(/本次在场期间/g,'在场期间').replace(/；(?:然后|随后)/g,'；');
 const lines=text.split('\n'),out=[];let previous='';
 for(let line of lines){const at=line.indexOf('：'),head=at<0?'':line.slice(0,at);if(head&&head===previous){line='　'+line.slice(at+1);}else previous=head;out.push(line.replaceAll('；然后','；随后'));}
 return out.join('\n').replace(/\uE000(\d+)\uE001/g,(_,index)=>names[Number(index)]);
}
