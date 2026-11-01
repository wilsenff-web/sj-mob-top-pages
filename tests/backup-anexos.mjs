import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {webcrypto,createHash} from 'node:crypto';
const source=readFileSync(new URL('../supabase/google-drive/backup.ts',import.meta.url),'utf8');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const fixtureSecret='test-fixture-secret-not-a-real-credential';
let handler,uploads=0,corrupt=false,missing=false,listFailure=false,downloadFailure=false;
const fixtureBytes=Uint8Array.from({length:90045},(_,i)=>i%251);
const path='driver/prova.png';
const db={auth:{getUser:async jwt=>({data:{user:{id:jwt==='admin-test'?'admin':'other'}},error:null})},storage:{from:()=>({
 list:async(folder)=>listFailure?{data:null,error:{message:'unavailable'}}:{data:folder===''?[{name:'driver',id:null,metadata:null}]:missing?[]:[{name:'prova.png',id:'file',metadata:{size:fixtureBytes.length}}],error:null},
 download:async()=>downloadFailure?{data:null,error:{message:'unavailable'}}:{data:new Blob([fixtureBytes],{type:'image/png'}),error:null}
})}};
const ctx=vm.createContext({console,Uint8Array,Set,Array,JSON,Number,String,Math,Error,TextEncoder,TextDecoder,URLSearchParams,Request,Response,Blob,crypto:webcrypto,btoa,atob,
 Deno:{env:{get:n=>n==='SJ_ADMIN_UID'?'admin':'configured'},serve:fn=>handler=fn},createClient:()=>db,
 fetch:async(url,options)=>{
  assert.ok(url.includes('/upload/drive/v3/files'));uploads++;
  const content=options.body.match(/Content-Type: application\/json\r\n\r\n([\s\S]*)\r\n--[^\r\n]+--$/)[1];
  const backup=JSON.parse(content),file=backup.storage.buckets[0].files[0];
  assert.deepEqual(Buffer.from(file.content_base64,'base64'),Buffer.from(fixtureBytes));
  assert.equal(file.sha256,sha(fixtureBytes));
  assert.equal(file.path,path);assert.equal(backup.schema_version,2);
  const bytes=new TextEncoder().encode(content);
  return new Response(JSON.stringify({id:'drive-test-file',name:'test.json',size:String(bytes.length),sha256Checksum:corrupt?'invalid':sha(bytes)}),{status:200});
 }
});
let code=source.replace(/^import .*;$/m,'').replace(/const cronSecretSha256="[a-f0-9]+"/,`const cronSecretSha256="${sha(fixtureSecret)}"`);
code+='\ngoogleAccessToken=async()=>"test-token";collectBackup=async()=>({app:"SJ MOB TOP",schema_version:2,created_at:"test",scope:"tables and attachments",tables:{comprovantes_motoristas:[{arquivo_path:"driver/prova.png"}]}});';
vm.runInContext(stripTypeScriptTypes(code),ctx);
for(const length of [0,1,2,3,24575,24576,24577,49153,90045]){
 ctx.bytes=Uint8Array.from({length},(_,i)=>i%251);
 const encoded=vm.runInContext('base64Bytes(bytes)',ctx);
 assert.deepEqual(Buffer.from(encoded,'base64'),Buffer.from(ctx.bytes));
}
console.log('PASS base64 round-trip em limites de bloco e arquivo de 90045 bytes');
const request=(headers={})=>new Request('https://test/backup',{method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify({action:'weekly'})});
assert.equal((await handler(request())).status,403);
assert.equal((await handler(request({'x-backup-cron-secret':'wrong'}))).status,403);
assert.equal(uploads,0);
const response=await handler(request({'x-backup-cron-secret':fixtureSecret}));assert.equal(response.status,200);
const result=await response.json();assert.equal(result.attachment_count,1);assert.equal(result.attachment_bytes,90045);assert.equal(result.integrity_verified,true);
console.log('PASS backup inteiro com anexo, caminho original, SHA-256 e verificação no Drive');
missing=true;assert.equal((await handler(request({'x-backup-cron-secret':fixtureSecret}))).status,500);assert.equal(uploads,1);missing=false;
listFailure=true;assert.equal((await handler(request({'x-backup-cron-secret':fixtureSecret}))).status,500);assert.equal(uploads,1);listFailure=false;
downloadFailure=true;assert.equal((await handler(request({'x-backup-cron-secret':fixtureSecret}))).status,500);assert.equal(uploads,1);downloadFailure=false;
console.log('PASS falha de listagem, arquivo ausente e download inválido não enviam backup parcial');
corrupt=true;assert.equal((await handler(request({'x-backup-cron-secret':fixtureSecret}))).status,500);
await assert.rejects(vm.runInContext('collectAttachments(MAX_BACKUP_BYTES,[])',ctx),/40 MB/);
console.log('PASS verificação detecta corrupção no Drive e limite de tamanho');
