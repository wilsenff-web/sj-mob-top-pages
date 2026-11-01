-- SJ MOB TOP: endurecimento pós-instalação + relatório de verificação
-- Executar como postgres no SQL Editor, no projeto correto.
-- Não remove comprovantes, não altera RLS de outras tabelas.
begin;
create or replace function public.sj_comprovante_guard()
returns trigger language plpgsql set search_path=public as $$
begin
 if tg_op='INSERT' then
   if new.status <> 'pendente' or new.reviewed_at is not null then
     raise exception 'Novo comprovante deve estar pendente e sem revisão';
   end if;
 elsif tg_op='UPDATE' then
   if (new.id,new.user_id,new.motorista_id,new.enviado_por,new.valor,new.data_pagamento,new.observacao,new.arquivo_path,new.created_at)
      is distinct from
      (old.id,old.user_id,old.motorista_id,old.enviado_por,old.valor,old.data_pagamento,old.observacao,old.arquivo_path,old.created_at)
   then raise exception 'Campos do comprovante são imutáveis'; end if;
   if new.reviewed_at is distinct from old.reviewed_at then
     raise exception 'Data de revisão não pode ser definida manualmente';
   end if;
   if new.status <> old.status and old.status <> 'pendente' then
     raise exception 'Comprovante já revisado';
   end if;
   if new.status <> 'pendente' then new.reviewed_at=now(); end if;
 end if;
 return new;
end $$;
drop trigger if exists sj_comprovante_guard_trigger on public.comprovantes_motoristas;
create trigger sj_comprovante_guard_trigger before insert or update on public.comprovantes_motoristas
for each row execute function public.sj_comprovante_guard();
commit;

-- Relatório somente leitura (deve retornar todos os itens como OK).
with checks as (
 select 'Tabela com RLS' as item,
   (select relrowsecurity from pg_class where oid='public.comprovantes_motoristas'::regclass) as ok
 union all select 'Bucket privado',
   exists(select 1 from storage.buckets where id='sj-comprovantes' and public=false)
 union all select 'Limite de arquivo 5 MB',
   exists(select 1 from storage.buckets where id='sj-comprovantes' and file_size_limit=5242880)
 union all select 'Política de upload privado',
   exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='sj_comprovantes_upload' and cmd='INSERT')
 union all select 'Política de leitura privada',
   exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='sj_comprovantes_read' and cmd='SELECT')
 union all select 'Política de envio do motorista',
   exists(select 1 from pg_policies where schemaname='public' and tablename='comprovantes_motoristas' and policyname='sj_comprovante_motorista_insert' and cmd='INSERT')
 union all select 'Política de consulta',
   exists(select 1 from pg_policies where schemaname='public' and tablename='comprovantes_motoristas' and policyname='sj_comprovante_motorista_select' and cmd='SELECT')
 union all select 'Política de revisão administrativa',
   exists(select 1 from pg_policies where schemaname='public' and tablename='comprovantes_motoristas' and policyname='sj_comprovante_admin_update' and cmd='UPDATE')
 union all select 'Gatilho de integridade',
   exists(select 1 from pg_trigger where tgrelid='public.comprovantes_motoristas'::regclass and tgname='sj_comprovante_guard_trigger' and not tgisinternal and (tgtype & 4)=4 and (tgtype & 16)=16)
)
select item,case when ok then 'OK' else 'REVISAR' end as resultado from checks;
