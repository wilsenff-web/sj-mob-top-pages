// SJ MOB TOP — Backup de registros e anexos no Google Drive (manual + cron).
// JSON v2: anexos em base64 com tamanho e SHA-256; originais nunca são alterados.
import {createClient} from "npm:@supabase/supabase-js@2";
const env=(name:string)=>Deno.env.get(name)||"";
const url=env("SUPABASE_URL"),serviceKey=env("SUPABASE_SERVICE_ROLE_KEY");
const admin=env("SJ_ADMIN_UID");
const clientId=env("GOOGLE_CLIENT_ID"),clientSecret=env("GOOGLE_CLIENT_SECRET");
const encryptionKey=env("GOOGLE_TOKEN_ENCRYPTION_KEY");
// SHA-256 of the high-entropy secret held in Vault (sj_mob_top_backup_cron_secret).
// The plaintext stays in Vault; rotate this verifier together with the Vault secret.
const cronSecretSha256="e1dfd0a110e823191df093aa71ec6beac684e3c281daf2fb597df6a5f67d2ab5";
async function cronRequest(req:Request){
 const secret=req.headers.get("x-backup-cron-secret");
 if(!secret || secret.length>1024)return false;
 const hash=new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(secret)));
 const expected=Uint8Array.from(cronSecretSha256.match(/../g)!,x=>parseInt(x,16));
 let mismatch=0;
 for(let i=0;i<hash.length;i++)mismatch|=hash[i]^expected[i];
 return mismatch===0;
}
const db=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
const origin="https://wilsenff-web.github.io";
const cors={"Access-Control-Allow-Origin":origin,"Access-Control-Allow-Methods":"POST,OPTIONS","Access-Control-Allow-Headers":"authorization,apikey,x-client-info,content-type,x-supabase-api-version","Vary":"Origin"};
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{"content-type":"application/json","cache-control":"no-store",...cors}});
const tables=["motoristas","veiculos","viagens","financeiro","pendencias","pagamentos_pendencias","manutencoes","metas","comprovantes_motoristas","sj_solicitacoes_motoristas"];
async function adminRequest(req:Request){
 const jwt=req.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
 if(!jwt)return false;
 const {data,error}=await db.auth.getUser(jwt);
 return !error && data.user?.id===admin;
}
async function getRefreshToken(){
 const {data,error}=await db.from("sj_google_drive_tokens").select("refresh_token_encrypted").eq("admin_uid",admin).maybeSingle();
 if(error||!data)throw Error("Google Drive não conectado");
 const encrypted=Uint8Array.from(atob(data.refresh_token_encrypted),x=>x.charCodeAt(0));
 const keyBytes=Uint8Array.from(atob(encryptionKey),x=>x.charCodeAt(0));
 if(keyBytes.length!==32)throw Error("Chave de criptografia inválida");
 const key=await crypto.subtle.importKey("raw",keyBytes,"AES-GCM",false,["decrypt"]);
 const plain=await crypto.subtle.decrypt({name:"AES-GCM",iv:encrypted.slice(0,12)},key,encrypted.slice(12));
 return new TextDecoder().decode(plain);
}
async function googleAccessToken(){
 const refreshToken=await getRefreshToken();
 const res=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,refresh_token:refreshToken,grant_type:"refresh_token"})});
 const data=await res.json();
 if(!res.ok||!data.access_token)throw Error("Autorização Google expirada ou revogada. Reconecte o Google Drive.");
 return data.access_token as string;
}
async function collectBackup(){
 const result:Record<string,unknown[]>={};
 for(const table of tables){
  const rows:unknown[]=[];
  for(let offset=0;;offset+=500){
   if(offset>100000)throw Error("Limite de registros excedido: "+table);
   const {data,error}=await db.from(table).select("*").range(offset,offset+499).order("id",{ascending:true});
   if(error)throw Error("Erro ao ler tabela "+table+": "+error.message);
   rows.push(...(data||[]));
   if(!data||data.length<500)break;
  }
  result[table]=rows;
 }
 return {app:"SJ MOB TOP",schema_version:2,created_at:new Date().toISOString(),scope:"Tabelas PostgreSQL e arquivos anexados do bucket sj-comprovantes",tables:result};
}

const MAX_BACKUP_BYTES=40*1024*1024;
async function sha256(bytes:Uint8Array){
 return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",bytes)),n=>n.toString(16).padStart(2,"0")).join("");
}
function base64Bytes(bytes:Uint8Array){
 const parts:string[]=[];
 // Each chunk is divisible by 3, so concatenating encoded chunks is valid base64.
 for(let offset=0;offset<bytes.length;offset+=24576)parts.push(btoa(String.fromCharCode(...bytes.subarray(offset,offset+24576))));
 return parts.join("");
}
async function collectAttachments(baseBytes:number,requiredPaths:string[]){
 const bucket="sj-comprovantes",paths:string[]=[];
 const queue=[""],visited=new Set<string>();
 while(queue.length){
  const folder=queue.shift()!;
  if(visited.has(folder))throw Error("Pasta repetida nos anexos");
  visited.add(folder);
  if(visited.size>10000)throw Error("Quantidade de pastas de anexos excedida");
  for(let offset=0;;offset+=100){
   const {data,error}=await db.storage.from(bucket).list(folder,{limit:100,offset,sortBy:{column:"name",order:"asc"}});
   if(error)throw Error("Não foi possível listar os anexos: "+error.message);
   for(const item of data||[]){
    const path=folder?folder+"/"+item.name:item.name;
    if(!item.id && !item.metadata)queue.push(path);
    else paths.push(path);
   }
   if(!data||data.length<100)break;
  }
 }
 const uniquePaths=new Set(paths);
 for(const path of requiredPaths)if(!uniquePaths.has(path))throw Error("Um comprovante registrado não foi localizado no Storage. Backup não concluído.");
 const files:{path:string;mime_type:string;size_bytes:number;sha256:string;content_base64:string}[]=[];
 let totalBytes=0,estimated=baseBytes;
 for(const path of Array.from(uniquePaths).sort()){
  const {data:blob,error}=await db.storage.from(bucket).download(path);
  if(error||!blob)throw Error("Não foi possível ler um anexo. Backup não concluído.");
  estimated+=4*Math.ceil(blob.size/3)+2048+path.length*6;
  if(estimated>MAX_BACKUP_BYTES)throw Error("Backup com anexos maior que 40 MB: requer exportação em partes. Nenhum backup parcial foi enviado.");
  const bytes=new Uint8Array(await blob.arrayBuffer());
  files.push({path,mime_type:blob.type||"application/octet-stream",size_bytes:bytes.byteLength,sha256:await sha256(bytes),content_base64:base64Bytes(bytes)});
  totalBytes+=bytes.byteLength;
 }
 return {encoding:"base64",total_files:files.length,total_bytes:totalBytes,buckets:[{id:bucket,files}]};
}

async function upload(accessToken:string,filename:string,content:string){
 const metadata=JSON.stringify({name:filename,mimeType:"application/json",description:"SJ MOB TOP — tabelas e anexos completos em JSON v2"});
 const boundary="sjmobtop_"+crypto.randomUUID();
 const payload="--"+boundary+"\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"+metadata+"\r\n--"+boundary+"\r\nContent-Type: application/json\r\n\r\n"+content+"\r\n--"+boundary+"--";
 const response=await fetch("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,size,webViewLink,sha256Checksum",{method:"POST",headers:{"authorization":"Bearer "+accessToken,"content-type":"multipart/related; boundary="+boundary},body:payload});
 const data=await response.json();
 if(!response.ok||!data.id)throw Error("Google Drive recusou o upload");
 const bytes=new TextEncoder().encode(content);
 if(Number(data.size)!==bytes.byteLength)throw Error("Tamanho do backup no Drive não confere. Verificação falhou.");
 const expectedHash=await sha256(bytes);
 let storedHash=data.sha256Checksum;
 if(!storedHash){
  const check=await fetch("https://www.googleapis.com/drive/v3/files/"+encodeURIComponent(data.id)+"?alt=media",{headers:{authorization:"Bearer "+accessToken}});
  if(!check.ok)throw Error("Backup enviado, mas não foi possível verificar a cópia no Drive.");
  storedHash=await sha256(new Uint8Array(await check.arrayBuffer()));
 }
 if(storedHash!==expectedHash)throw Error("Integridade do backup no Drive não confere.");
 return {...data,sha256:expectedHash,integrity_verified:true};
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
 if(req.method!=="POST")return json({error:"Método não permitido"},405);
 try{
  if(!url||!serviceKey||!admin||!clientId||!clientSecret||!encryptionKey)return json({error:"Configuração incompleta"},503);
  const body=await req.json().catch(()=>({}));
  const isCron=body.action==="weekly" && await cronRequest(req);
  if(!isCron&&!(await adminRequest(req)))return json({error:"Acesso restrito"},403);
  if(body.action!=="manual"&&body.action!=="weekly")return json({error:"Ação inválida"},400);
  if(body.action==="weekly"&&!isCron)return json({error:"Agendamento não autorizado"},403);
  const accessToken=await googleAccessToken();
  const backup=await collectBackup();
  const tableBytes=new TextEncoder().encode(JSON.stringify(backup)).byteLength;
  const requiredPaths=(backup.tables.comprovantes_motoristas||[]).map((row:any)=>row.arquivo_path).filter((path:any)=>typeof path==="string" && path.length>0);
  const storage=await collectAttachments(tableBytes,requiredPaths);
  const completeBackup={...backup,storage};
  const content=JSON.stringify(completeBackup);
  if(new TextEncoder().encode(content).byteLength>40*1024*1024)throw Error("Backup maior que 40 MB: requer exportação em partes");
  const name="SJ-MOB-TOP-"+body.action+"-"+new Date().toISOString().replace(/[:.]/g,"-")+".json";
  const file=await upload(accessToken,name,content);
  return json({ok:true,file_name:file.name,file_id:file.id,created_at:backup.created_at,scope:backup.scope,attachment_count:storage.total_files,attachment_bytes:storage.total_bytes,integrity_verified:file.integrity_verified,sha256:file.sha256,schema_version:2});
 }catch(e){console.error("Drive backup failed:",e instanceof Error?e.message:"unknown");return json({error:e instanceof Error?e.message:"Falha ao criar backup"},500);}
});
