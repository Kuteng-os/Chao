export const sins=[{"id":"wrath","name":"暴怒","color":"#421812"},{"id":"lust","name":"色欲","color":"#573018"},{"id":"sloth","name":"怠惰","color":"#6b4206"},{"id":"gluttony","name":"暴食","color":"#2d3f15"},{"id":"gloom","name":"忧郁","color":"#172f36"},{"id":"pride","name":"傲慢","color":"#0e263f"},{"id":"envy","name":"嫉妒","color":"#321d3f"}];
export const sinInfo=id=>sins.find(s=>s.id===id)??{id:"",name:"未选择罪孽",color:"#303538"};
export const sinIcon=id=>sins.some(s=>s.id===id)?"/workshop/sins/"+id+".png":"";
