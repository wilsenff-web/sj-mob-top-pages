import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {unzipSync,zipSync,strFromU8,strToU8} from 'fflate';
export function loadSpreadsheetRuntime(base){
 const ctx=vm.createContext({console,unzipSync,zipSync,strFromU8,strToU8,Uint8Array,atob,Map,Set,Array,Object,String,Number,JSON,Math,Date,Error});
 vm.runInContext(fs.readFileSync(new URL('planilha-template.ts',base),'utf8').replace('export const','const'),ctx);
 vm.runInContext(stripTypeScriptTypes(fs.readFileSync(new URL('planilha.ts',base),'utf8').replace(/^import .*$/gm,'').replace(/^export /gm,'')),ctx);
 return {createSpreadsheet:vm.runInContext('createSpreadsheet',ctx),XLSX_MIME:vm.runInContext('XLSX_MIME',ctx)};
}
