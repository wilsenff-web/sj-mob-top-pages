create or replace function public.sj_comprovante_guard()
returns trigger language plpgsql set search_path=public as $f$
begin
 if tg_op='INSERT' then
  if new.status<>'pendente' or new.reviewed_at is not null then raise exception 'Novo comprovante deve estar pendente e sem revisão'; end if;
 elsif tg_op='UPDATE' then
  if (new.id,new.user_id,new.motorista_id,new.enviado_por,new.valor,new.data_pagamento,new.observacao,new.arquivo_path,new.created_at)
   is distinct from (old.id,old.user_id,old.motorista_id,old.enviado_por,old.valor,old.data_pagamento,old.observacao,old.arquivo_path,old.created_at)
   then raise exception 'Campos do comprovante são imutáveis'; end if;
  if new.reviewed_at is distinct from old.reviewed_at then raise exception 'Data de revisão não pode ser definida manualmente'; end if;
  if new.status<>old.status and old.status<>'pendente' then
   if not (old.status='confirmado' and new.status='rejeitado' and public.is_sj_admin() and auth.uid()=old.user_id) then raise exception 'Comprovante já revisado'; end if;
  end if;
  if new.status<>'pendente' then new.reviewed_at=now(); end if;
 end if;
 return new;
end $f$;
create or replace function public.sj_guard_financeiro_comprovante()
returns trigger language plpgsql set search_path=public as $f$
begin
 if tg_op='UPDATE' and old.comprovante_id is not null then raise exception 'Recebimento vinculado a comprovante é imutável'; end if;
 if tg_op='DELETE' and old.comprovante_id is not null then
  if not (public.is_sj_admin() and auth.uid()=old.user_id and exists(select 1 from public.comprovantes_motoristas c where c.id=old.comprovante_id and c.user_id=old.user_id and c.status='rejeitado')) then
   raise exception 'Use a exclusão autorizada no Financeiro para cancelar este recebimento';
  end if;
 end if;
 if tg_op='INSERT' and new.comprovante_id is not null and current_user<>'postgres' then raise exception 'Use a operação de recebimento autorizada'; end if;
 return coalesce(new,old);
end $f$;
create or replace function public.sj_excluir_lancamento_financeiro(p_lancamento_id uuid)
returns uuid language plpgsql security invoker set search_path=public as $f$
declare v public.financeiro%rowtype; v_comprovante uuid;
begin
 if auth.uid() is null or not public.is_sj_admin() then raise exception 'Acesso restrito ao administrador' using errcode='42501'; end if;
 select comprovante_id into v_comprovante from public.financeiro where id=p_lancamento_id and user_id=auth.uid();
 if not found then raise exception 'Lançamento não encontrado ou sem permissão' using errcode='42501'; end if;
 if v_comprovante is not null then perform 1 from public.comprovantes_motoristas where id=v_comprovante and user_id=auth.uid() for update; end if;
 select * into v from public.financeiro where id=p_lancamento_id and user_id=auth.uid() for update;
 if not found then raise exception 'Lançamento não encontrado ou já excluído'; end if;
 if v.comprovante_id is not null then
  update public.comprovantes_motoristas set status='rejeitado' where id=v.comprovante_id and user_id=auth.uid() and status='confirmado';
  if not found then raise exception 'O comprovante não está confirmado. Atualize a página.'; end if;
 end if;
 delete from public.financeiro where id=v.id and user_id=auth.uid();
 if not found then raise exception 'Exclusão não autorizada'; end if;
 return v.id;
end $f$;
revoke all on function public.sj_excluir_lancamento_financeiro(uuid) from public,anon;
grant execute on function public.sj_excluir_lancamento_financeiro(uuid) to authenticated;
