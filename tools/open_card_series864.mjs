// Run only with frontline.service stopped, after backing up store.json.
import {readFile,writeFile,rename,stat,access} from 'node:fs/promises';
import {join} from 'node:path';
import {isDeepStrictEqual} from 'node:util';
import {initializeCardSeries} from '../server/src/card_series.js';
const directory=process.argv[2];if(!directory)throw Error('Provide store directory');
try{await access(join(directory,'service.lock'));throw Error('Store is locked; stop the service first');}catch(error){if(error.code!=='ENOENT')throw error;}
const path=join(directory,'store.json'),before=JSON.parse(await readFile(path,'utf8')),after=structuredClone(before);
initializeCardSeries(after);
const stripped=structuredClone(after);delete stripped.card_series;
const original=structuredClone(before);delete original.card_series;
let cards=0,versions=0;
for(const [id,entries] of Object.entries(after.cards)){
 cards++;versions+=entries.length;
 for(let i=0;i<entries.length;i++){
  if(!before.card_series&&entries[i].series!==1)throw Error('First migration must place every existing card in series one');
  delete stripped.cards[id][i].series;delete original.cards[id][i].series;
 }
}
if(!isDeepStrictEqual(stripped,original))throw Error('Migration changed data beyond series metadata');
const temp=path+'.series864.tmp';await writeFile(temp,JSON.stringify(after),{mode:(await stat(path)).mode&0o777,flag:'wx'});await rename(temp,path);
console.log(JSON.stringify({migration:'card-series',current:after.card_series.current,cards,versions,gameplay_unchanged:true}));
