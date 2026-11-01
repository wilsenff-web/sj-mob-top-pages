alter table public.comprovantes_motoristas add column viagem_id uuid references public.viagens(id) on delete restrict;
create policy sj_motorista_consultar_pendencias on public.pendencias for select to authenticated using (
 exists(select 1 from public.motoristas m where m.id=pendencias.motorista_id and m.user_id=pendencias.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo')
);
create policy sj_motorista_consultar_pagamentos on public.pagamentos_pendencias for select to authenticated using (
 exists(select 1 from public.pendencias p join public.motoristas m on m.id=p.motorista_id and m.user_id=p.user_id
 where p.id=pagamentos_pendencias.pendencia_id and p.user_id=pagamentos_pendencias.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo')
);
alter policy sj_comprovante_motorista_insert on public.comprovantes_motoristas with check (
 enviado_por=(select auth.uid()) and status='pendente'
 and exists(select 1 from public.motoristas m where m.id=comprovantes_motoristas.motorista_id and m.user_id=comprovantes_motoristas.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo')
 and arquivo_path like ((select auth.uid())::text||'/%')
 and (viagem_id is null or exists(select 1 from public.viagens v where v.id=comprovantes_motoristas.viagem_id and v.motorista_id=comprovantes_motoristas.motorista_id and v.user_id=comprovantes_motoristas.user_id))
);

CREATE OR REPLACE FUNCTION public.sj_comprovante_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
 if tg_op='INSERT' then
  if new.status<>'pendente' or new.reviewed_at is not null then raise exception 'Novo comprovante deve estar pendente e sem revisão'; end if;
 elsif tg_op='UPDATE' then
  if (new.id,new.user_id,new.motorista_id,new.enviado_por,new.valor,new.data_pagamento,new.observacao,new.arquivo_path,new.created_at,new.viagem_id)
   is distinct from (old.id,old.user_id,old.motorista_id,old.enviado_por,old.valor,old.data_pagamento,old.observacao,old.arquivo_path,old.created_at,old.viagem_id)
   then raise exception 'Campos do comprovante são imutáveis'; end if;
  if new.reviewed_at is distinct from old.reviewed_at then raise exception 'Data de revisão não pode ser definida manualmente'; end if;
  if new.status<>old.status and old.status<>'pendente' then
   if not (old.status='confirmado' and new.status='rejeitado' and public.is_sj_admin() and auth.uid()=old.user_id) then raise exception 'Comprovante já revisado'; end if;
  end if;
  if new.status<>'pendente' then new.reviewed_at=now(); end if;
 end if;
 return new;
end $function$
;
