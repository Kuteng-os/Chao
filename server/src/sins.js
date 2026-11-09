import {readFileSync} from "node:fs";
import {fail} from "./codec.js";
export const SINS=JSON.parse(readFileSync(new URL("../../assets/sins/catalog.json",import.meta.url),"utf8"));
export function mainSin(value){if(value===undefined||value===null||value==="")return "";if(typeof value!=="string"||!SINS.some(s=>s.id===value))fail("INVALID_SIN","请选择有效的罪孽。",422);return value;}
