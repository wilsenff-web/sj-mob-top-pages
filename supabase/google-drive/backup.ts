// SJ MOB TOP — Backup de registros no Google Drive (manual + cron).
// IMPORTANTE: não inclui arquivos anexados no Storage; teste restauração antes de depender dele.
import {createClient} from "npm:@supabase/supabase-js@2";
const env=(name:string)=>Deno.env.get(name)||"";
const url=env("SUPABASE_URL"),serviceKey=env("SUPABASE_SERVICE_ROLE_KEY");
const admin=env("SJ_ADMIN_UID");
const clientId=env("GOOGLE_CLIENT_ID"),clientSecret=env("GOOGLE_CLIENT_SECRET");
const encryptionKey=env("GOOGLE_TOKEN_ENCRYPTION_KEY"),cronSecret=env("BACKUP_CRON_SECRET");
const db=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
const origin="https://wilsenff-web.github.io";
const cors={"Access-Control-Allow-Origin":origin,"Access-Control-Allow-Methods":"POST,OPTIONS","Access-Control-Allow-Headers":"authorization,apikey,x-client-info,content-type,x-supabase-api-version","Vary":"Origin"};
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{"content-type":"application/json","cache-control":"no-store",...cors}});
const tables=["motoristas","veiculos","viagens","financeiro","pendencias","pagamentos_pendencias","manutencoes","metas","comprovantes_motoristas"];
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
 return {app:"SJ MOB TOP",schema_version:1,created_at:new Date().toISOString(),scope:"Tabelas PostgreSQL; arquivos do Storage não incluídos",tables:result};
}
async function upload(accessToken:string,filename:string,content:string){
 const metadata=JSON.stringify({name:filename,mimeType:"application/json",description:"SJ MOB TOP — backup de tabelas; sem anexos"});
 const boundary="sjmobtop_"+crypto.randomUUID();
 const payload="--"+boundary+"\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"+metadata+"\r\n--"+boundary+"\r\nContent-Type: application/json\r\n\r\n"+content+"\r\n--"+boundary+"--";
 const response=await fetch("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,size,webViewLink",{method:"POST",headers:{"authorization":"Bearer "+accessToken,"content-type":"multipart/related; boundary="+boundary},body:payload});
 const data=await response.json();
 if(!response.ok||!data.id)throw Error("Google Drive recusou o upload");
 return data;
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
 if(req.method!=="POST")return json({error:"Método não permitido"},405);
 try{
  if(!url||!serviceKey||!admin||!clientId||!clientSecret||!encryptionKey)return json({error:"Configuração incompleta"},503);
  const body=await req.json().catch(()=>({}));
  const isCron=body.action==="weekly" && !!cronSecret && req.headers.get("x-backup-cron-secret")===cronSecret;
  if(!isCron&&!(await adminRequest(req)))return json({error:"Acesso restrito"},403);
  if(body.action!=="manual"&&body.action!=="weekly")return json({error:"Ação inválida"},400);
  if(body.action==="weekly"&&!isCron)return json({error:"Agendamento não autorizado"},403);
  const accessToken=await googleAccessToken();
  const backup=await collectBackup();
  const content=JSON.stringify(backup);
  if(new TextEncoder().encode(content).byteLength>40*1024*1024)throw Error("Backup maior que 40 MB: requer exportação em partes");
  const name="SJ-MOB-TOP-"+body.action+"-"+new Date().toISOString().replace(/[:.]/g,"-")+".json";
  const file=await upload(accessToken,name,content);
  return json({ok:true,file_name:file.name,file_id:file.id,created_at:backup.created_at,scope:backup.scope});
 }catch(e){console.error("Drive backup failed:",e instanceof Error?e.message:"unknown");return json({error:e instanceof Error?e.message:"Falha ao criar backup"},500);}
});
