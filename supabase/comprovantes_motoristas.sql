-- SJ MOB TOP: comprovantes de pagamento enviados por motoristas
-- Executar no SQL Editor APENAS após revisar. Não altera políticas existentes.
-- Comprovante enviado NÃO equivale a pagamento confirmado.
begin;
create table if not exists public.comprovantes_motoristas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  motorista_id uuid not null,
  enviado_por uuid not null references auth.users(id),
  valor numeric(12,2) not null check(valor>0),
  data_pagamento date not null,
  observacao text,
  arquivo_path text not null unique,
  status text not null default 'pendente' check(status in ('pendente','confirmado','rejeitado')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint comprovantes_motorista_frota_fk foreign key(motorista_id,user_id)
    references public.motoristas(id,user_id)
);
alter table public.comprovantes_motoristas enable row level security;
drop policy if exists sj_comprovante_motorista_insert on public.comprovantes_motoristas;
create policy sj_comprovante_motorista_insert on public.comprovantes_motoristas
 for insert to authenticated with check (
   enviado_por=(select auth.uid()) and status='pendente'
   and exists(select 1 from public.motoristas m
     where m.id=motorista_id and m.user_id=comprovantes_motoristas.user_id
     and m.auth_user_id=(select auth.uid()) and m.status='ativo')
   and arquivo_path like (select auth.uid()::text)||'/%'
 );
drop policy if exists sj_comprovante_motorista_select on public.comprovantes_motoristas;
create policy sj_comprovante_motorista_select on public.comprovantes_motoristas
 for select to authenticated using (
   enviado_por=(select auth.uid()) or
   (user_id=(select auth.uid()) and (select auth.uid())='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid)
 );
drop policy if exists sj_comprovante_admin_update on public.comprovantes_motoristas;
create policy sj_comprovante_admin_update on public.comprovantes_motoristas
 for update to authenticated using (
   user_id=(select auth.uid()) and (select auth.uid())='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 ) with check (
   user_id=(select auth.uid()) and (select auth.uid())='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 );
-- Trava alterações administrativas aos campos de revisão, impedindo mudança de comprovante/valor.
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
     raise exception 'Comprovante já revisado'; end if;
   if new.status <> 'pendente' then new.reviewed_at=now(); end if;
 end if;
 return new;
end $$;
drop trigger if exists sj_comprovante_guard_trigger on public.comprovantes_motoristas;
create trigger sj_comprovante_guard_trigger before insert or update on public.comprovantes_motoristas
for each row execute function public.sj_comprovante_guard();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('sj-comprovantes','sj-comprovantes',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=5242880,
 allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists sj_comprovantes_upload on storage.objects;
create policy sj_comprovantes_upload on storage.objects
 for insert to authenticated with check (
 bucket_id='sj-comprovantes' and (storage.foldername(name))[1]=(select auth.uid()::text)
 and exists(select 1 from public.motoristas m
   where m.auth_user_id=(select auth.uid()) and m.status='ativo'
   and m.user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid)
);
drop policy if exists sj_comprovantes_read on storage.objects;
create policy sj_comprovantes_read on storage.objects
 for select to authenticated using (
 bucket_id='sj-comprovantes' and (
   (storage.foldername(name))[1]=(select auth.uid()::text)
   or ((select auth.uid())='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
       and exists(select 1 from public.comprovantes_motoristas c where c.arquivo_path=name
         and c.user_id=(select auth.uid())))
 )
);
commit;
-- Não cria receita automaticamente; admin confirma somente a autenticidade declarada.
