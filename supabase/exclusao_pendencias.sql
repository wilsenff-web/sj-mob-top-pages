create policy sj_admin_excluir_pendencia on public.pendencias for delete to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid()));
create policy sj_admin_excluir_pagamento_pendencia on public.pagamentos_pendencias for delete to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid()));
create or replace function public.sj_excluir_pendencia(p_pendencia_id uuid,p_excluir_pagamentos boolean default false)
returns uuid language plpgsql security invoker set search_path=public as $f$
declare v_id uuid;
begin
 if auth.uid() is null or not public.is_sj_admin() then raise exception 'Acesso restrito ao administrador' using errcode='42501'; end if;
 select id into v_id from public.pendencias where id=p_pendencia_id and user_id=auth.uid();
 if not found then raise exception 'Pendência não encontrada ou sem permissão' using errcode='42501'; end if;
 if exists(select 1 from public.pagamentos_pendencias where pendencia_id=v_id) and not coalesce(p_excluir_pagamentos,false) then
  raise exception 'Esta pendência possui pagamentos. Confirme a exclusão dos pagamentos vinculados.';
 end if;
 if coalesce(p_excluir_pagamentos,false) then delete from public.pagamentos_pendencias where pendencia_id=v_id and user_id=auth.uid(); end if;
 delete from public.pendencias where id=v_id and user_id=auth.uid();
 if not found then raise exception 'Exclusão não autorizada' using errcode='42501'; end if;
 return v_id;
exception when foreign_key_violation then
 raise exception 'Os pagamentos desta pendência mudaram. Atualize a página e confirme novamente.';
end $f$;
revoke all on function public.sj_excluir_pendencia(uuid,boolean) from public,anon;
grant execute on function public.sj_excluir_pendencia(uuid,boolean) to authenticated;