import {unzipSync,zipSync,strFromU8,strToU8} from "npm:fflate@0.8.2";
import {TEMPLATE_BASE64} from "./planilha-template.ts";
export const XLSX_MIME="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
const TABLES=[['motoristas','Motoristas'],['veiculos','Veiculos'],['viagens','Viagens'],['financeiro','Financeiro'],['pendencias','Pendencias'],['pagamentos_pendencias','Pagamentos'],['manutencoes','Manutencoes'],['metas','Metas'],['comprovantes_motoristas','Comprovantes'],['sj_solicitacoes_motoristas','Acessos']];
const MONEY=new Set(['valor','faturamento','custo','meta_faturamento','valor_diaria']);
const NUMBERS=new Set(['ano','km_atual','km_rodados','km_inicial','km_final','km_veiculo','meta_km','size_bytes']);
const PERCENT=new Set(['percentual_comissao']);
const LABELS:Record<string,string>={id:'ID',user_id:'ID proprietário',nome:'Nome',telefone:'Telefone',cnh:'CNH',validade_cnh:'Validade da CNH',status:'Situação',created_at:'Criado em',auth_user_id:'ID da conta',modalidade_cobranca:'Modalidade de cobrança',valor_diaria:'Diária (R$)',percentual_comissao:'Comissão (%)',acordo_cobranca:'Condições do acordo',placa:'Placa',modelo:'Modelo',ano:'Ano',km_atual:'Odômetro (km)',data_viagem:'Data da viagem',motorista_id:'ID motorista',veiculo_id:'ID veículo',km_rodados:'KM rodados',faturamento:'Faturamento (R$)',observacoes:'Observações',km_inicial:'KM inicial',km_final:'KM final',origem:'Origem',destino:'Destino',status_conferencia:'Conferência',conferido_em:'Conferido em',conferido_por:'Conferido por',data_lancamento:'Data do lançamento',tipo:'Tipo',categoria:'Categoria',descricao:'Descrição',valor:'Valor (R$)',comprovante_id:'ID comprovante',data_manutencao:'Data da manutenção',servico:'Serviço',custo:'Custo (R$)',km_veiculo:'KM do veículo',vencimento:'Vencimento',cobranca_detalhes:'Detalhes da cobrança',referencia_cobranca:'Referência da cobrança',pendencia_id:'ID pendência',data_pagamento:'Data do pagamento',forma:'Forma de pagamento',mes:'Mês',meta_faturamento:'Meta (R$)',meta_km:'Meta (km)',enviado_por:'Enviado por',observacao:'Observação',arquivo_path:'Caminho do comprovante',reviewed_at:'Revisado em',email:'E-mail',revisado_em:'Revisado em',revisado_por:'Revisado por',bucket:'Armazenamento',path:'Caminho original do arquivo',mime_type:'Tipo do arquivo',size_bytes:'Tamanho (bytes)',sha256:'SHA-256',motorista_nome:'Motorista',veiculo_nome:'Veículo'};
const xml=(value:unknown)=>String(value??'').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g,'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]!));
function col(n:number){let s='';for(n++;n>0;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;}
function textCell(ref:string,value:unknown,style:number){
 const text=typeof value==='object'&&value!==null?JSON.stringify(value):String(value??'');
 if(text.length>32767)throw Error('Um campo excede o limite de texto da planilha. O backup JSON preserva o conteúdo.');
 return '<x:c r="'+ref+'" s="'+style+'" t="inlineStr"><x:is><x:t xml:space="preserve">'+xml(text)+'</x:t></x:is></x:c>';
}
function cell(ref:string,value:unknown,key:string,style:{header:number;text:number;number:number;money:number;date:number;percent:number},header=false){
 if(header)return textCell(ref,value,style.header);
 if(value===null||value===undefined)return '<x:c r="'+ref+'" s="'+style.text+'" />';
 if(typeof value==='boolean')return '<x:c r="'+ref+'" s="'+style.text+'" t="b"><x:v>'+(value?1:0)+'</x:v></x:c>';
 if(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T00:00:00Z')))return '<x:c r="'+ref+'" s="'+style.date+'" t="n"><x:v>'+(Date.parse(value+'T00:00:00Z')/86400000+25569)+'</x:v></x:c>';
 const numeric=typeof value==='number'||((MONEY.has(key)||NUMBERS.has(key)||PERCENT.has(key))&&typeof value==='string'&&value.trim()!==''&&Number.isFinite(Number(value)));
 if(numeric){let v=Number(value);if(!Number.isFinite(v))throw Error('Número inválido na planilha');let s=style.number;if(MONEY.has(key))s=style.money;if(PERCENT.has(key)){v/=100;s=style.percent;}return '<x:c r="'+ref+'" s="'+s+'" t="n"><x:v>'+v+'</x:v></x:c>';}
 return textCell(ref,value,style.text);
}
export function createSpreadsheet(backup:any,jsonFile:{id:string;name:string}){
 const zip=unzipSync(Uint8Array.from(atob(TEMPLATE_BASE64),c=>c.charCodeAt(0)));
 const driverNames=new Map((backup.tables.motoristas||[]).map((r:any)=>[r.id,r.nome]));
 const vehicles=new Map((backup.tables.veiculos||[]).map((r:any)=>[r.id,[r.placa,r.modelo].filter(Boolean).join(' • ')]));
 const summary:any[][]=[['SJ MOB TOP — Backup','Informação'],['Gerado em',backup.created_at],['Backup completo com anexos','https://drive.google.com/file/d/'+jsonFile.id+'/view'],['Arquivo completo',jsonFile.name],['Anexos incluídos',backup.storage.total_files],['Tamanho dos anexos (bytes)',backup.storage.total_bytes],['Uso','Abra este XLSX com o Google Planilhas. É uma cópia dos dados; editar aqui não altera o sistema.'],['Arquivos anexados','Imagens/PDFs estão no backup JSON completo. A aba Anexos lista os arquivos.'],['Tabela','Quantidade de registros'],...TABLES.map(([key,name])=>[name,(backup.tables[key]||[]).length])];
 const matrices:{rows:any[][];keys:string[];filter:boolean}[]=[{rows:summary,keys:['campo','valor_resumo'],filter:false}];
 for(const [key] of TABLES){
  const records=(backup.tables[key]||[]).map((r:any)=>({...r,...(r.motorista_id?{motorista_nome:driverNames.get(r.motorista_id)||''}:{}),...(r.veiculo_id?{veiculo_nome:vehicles.get(r.veiculo_id)||''}:{})}));
  const keys=Array.from(new Set<string>(records.flatMap((r:any)=>Object.keys(r))));
  matrices.push({keys,filter:true,rows:keys.length?[[...keys.map(k=>LABELS[k]||k)],...records.map((r:any)=>keys.map(k=>r[k]??null))]:[['Sem registros']],});
 }
 const files=(backup.storage.buckets||[]).flatMap((b:any)=>(b.files||[]).map((f:any)=>({bucket:b.id,path:f.path,mime_type:f.mime_type,size_bytes:f.size_bytes,sha256:f.sha256})));
 const fileKeys=['bucket','path','mime_type','size_bytes','sha256'];
 matrices.push({keys:fileKeys,filter:true,rows:[fileKeys.map(k=>LABELS[k]),...files.map((r:any)=>fileKeys.map(k=>r[k]))]});
 for(let i=0;i<matrices.length;i++){
  const filename='xl/worksheets/sheet'+(i+1)+'.xml',original=strFromU8(zip[filename]);
  const styleFor=(ref:string)=>{const m=original.match(new RegExp('<x:c r="'+ref+'" s="(\\d+)"'));if(!m)throw Error('Modelo de planilha inválido');return Number(m[1]);};
  const styles={header:styleFor('A1'),text:styleFor('A2'),number:styleFor('B2'),money:styleFor('C2'),date:styleFor('D2'),percent:styleFor('E2')};
  const {rows,keys,filter}=matrices[i];if(rows.length>100000)throw Error('Quantidade de linhas excedida na planilha');
  const columns=Math.max(...rows.map(r=>r.length));if(columns>16384)throw Error('Quantidade de colunas excedida');
  const widthValues=Array.from({length:columns},(_,c)=>{let w=Math.max(16,String(rows[0]?.[c]||'').length+3);for(const row of rows.slice(1,31))w=Math.max(w,Math.min(45,String(row[c]??'').length+2));if(['path','arquivo_path','sha256'].includes(keys[c]))w=72;if(i===0)w=c===0?34:100;return w;});
  let sheetData='<x:sheetData>';
  for(let r=0;r<rows.length;r++){
   const lines=Math.max(1,...rows[r].map((v,c)=>typeof v==='string'?Math.ceil(v.length/widthValues[c]):1));
   const height=r===0?28:Math.max(22,Math.min(409,lines*14+8));
   sheetData+='<x:row r="'+(r+1)+'" ht="'+height+'" customHeight="1">'+rows[r].map((v,c)=>cell(col(c)+(r+1),v,keys[c]||'',styles,r===0)).join('')+'</x:row>';
  }
  sheetData+='</x:sheetData>';
  const widths=widthValues.map((w,c)=>'<x:col min="'+(c+1)+'" max="'+(c+1)+'" width="'+w+'" customWidth="1" />').join('');
  let updated=original.replace(/<x:cols>[\s\S]*?<\/x:cols>/,'<x:cols>'+widths+'</x:cols>').replace(/<x:sheetData>[\s\S]*?<\/x:sheetData>/,sheetData+(filter&&rows.length>1?'<x:autoFilter ref="A1:'+col(columns-1)+rows.length+'" />':''));
  if(i===0)updated=updated.replace(/<x:pane[^>]*\/>/,'');
  zip[filename]=strToU8(updated);
 }
 return zipSync(zip,{level:6});
}
