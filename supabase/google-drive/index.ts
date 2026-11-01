// SJ MOB TOP — Google Drive OAuth (Supabase Edge Function)
// Deploy with Verify JWT OFF: Google callback is unauthenticated;
// POST start/status authenticate JWT explicitly, callback validates single-use state.
import {createClient} from "npm:@supabase/supabase-js@2";
const env=(k:string)=>Deno.env.get(k)||"";
const supabaseUrl=env("SUPABASE_URL");
const serviceKey=env("SUPABASE_SERVICE_ROLE_KEY");
const clientId=env("GOOGLE_CLIENT_ID");
const clientSecret=env("GOOGLE_CLIENT_SECRET");
const adminUid=env("SJ_ADMIN_UID");
const redirectUri=env("GOOGLE_OAUTH_REDIRECT_URI");
const encryptionSecret=env("GOOGLE_TOKEN_ENCRYPTION_KEY");
const db=createClient(supabaseUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
const corsHeaders={
 "Access-Control-Allow-Origin":"https://wilsenff-web.github.io",
 "Access-Control-Allow-Methods":"POST, OPTIONS",
 "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type, x-supabase-api-version",
 "Access-Control-Max-Age":"3600",
 "Vary":"Origin"
};
const json=(obj:unknown,status=200)=>new Response(JSON.stringify(obj),{status,headers:{"content-type":"application/json","cache-control":"no-store",...corsHeaders}});
const b64url=(bytes:Uint8Array)=>btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
const bytesFromBase64=(value:string)=>Uint8Array.from(atob(value),c=>c.charCodeAt(0));
async function digest(value:string){
 const bytes=new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value)));
 return [...bytes].map(b=>b.toString(16).padStart(2,"0")).join("");
}
async function encrypt(value:string){
 const bytes=bytesFromBase64(encryptionSecret);
 if(bytes.length!==32)throw Error("Invalid encryption key");
 const key=await crypto.subtle.importKey("raw",bytes,"AES-GCM",false,["encrypt"]);
 const iv=crypto.getRandomValues(new Uint8Array(12));
 const ciphertext=new Uint8Array(await crypto.subtle.encrypt({name:"AES-GCM",iv},key,new TextEncoder().encode(value)));
 return btoa(String.fromCharCode(...iv,...ciphertext));
}
async function authorized(req:Request){
 const token=req.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
 if(!token)return false;
 const {data,error}=await db.auth.getUser(token);
 return !error && data.user?.id===adminUid;
}
function resultPage(success:boolean){
 const message=success?"Google Drive autorizado. Pode fechar esta janela.":"Autorização não concluída. Volte ao SJ MOB TOP e tente novamente.";
 return new Response("<!doctype html><html lang='pt-BR'><meta charset='utf-8'><title>SJ MOB TOP</title><body><h2>"+message+"</h2></body></html>",{status:success?200:400,headers:{"content-type":"text/html; charset=utf-8","cache-control":"no-store","content-security-policy":"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'"}});
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:corsHeaders});
 try{
  if(!supabaseUrl||!serviceKey||!clientId||!clientSecret||!adminUid||!redirectUri||!encryptionSecret)return json({error:"Missing server configuration"},503);
  const url=new URL(req.url);
  if(req.method==="GET"&&url.pathname.endsWith("/callback")){
   const state=url.searchParams.get("state"),code=url.searchParams.get("code");
   if(!state||!code)return resultPage(false);
   const {data:record,error:stateError}=await db.from("sj_google_oauth_states").delete().eq("state_hash",await digest(state)).select("admin_uid,expires_at").maybeSingle();
   if(stateError||!record||record.admin_uid!==adminUid||Date.parse(record.expires_at)<Date.now())return resultPage(false);
   const response=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({code,client_id:clientId,client_secret:clientSecret,redirect_uri:redirectUri,grant_type:"authorization_code"})});
   const tokens=await response.json();
   if(!response.ok||typeof tokens.refresh_token!=="string")return resultPage(false);
   const encrypted=await encrypt(tokens.refresh_token);
   const {error:saveError}=await db.from("sj_google_drive_tokens").upsert({admin_uid:adminUid,refresh_token_encrypted:encrypted,updated_at:new Date().toISOString()},{onConflict:"admin_uid"});
   if(saveError)throw saveError;
   return resultPage(true);
  }
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  if(!(await authorized(req)))return json({error:"Admin authorization required"},403);
  const body=await req.json().catch(()=>({}));
  if(body.action==="status"){
   const {data,error}=await db.from("sj_google_drive_tokens").select("updated_at").eq("admin_uid",adminUid).maybeSingle();
   if(error)throw error;
   return json({connected:!!data,updated_at:data?.updated_at??null});
  }
  if(body.action!=="start")return json({error:"Unknown action"},400);
  const state=b64url(crypto.getRandomValues(new Uint8Array(32)));
  const {error}=await db.from("sj_google_oauth_states").insert({state_hash:await digest(state),admin_uid:adminUid,expires_at:new Date(Date.now()+600000).toISOString()});
  if(error)throw error;
  const authorize=new URL("https://accounts.google.com/o/oauth2/v2/auth");
  for(const [key,value] of Object.entries({client_id:clientId,redirect_uri:redirectUri,response_type:"code",scope:"https://www.googleapis.com/auth/drive.file",access_type:"offline",prompt:"consent",state}))authorize.searchParams.set(key,value);
  return json({authorization_url:authorize.toString()});
 }catch(err){console.error("OAuth error",err instanceof Error?err.message:"unknown");return json({error:"OAuth operation failed"},500);}
});
