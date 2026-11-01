alter policy acesso_proprio on public.motoristas to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid())) with check ((select public.is_sj_admin()) and user_id=(select auth.uid()));
alter policy acesso_proprio on public.veiculos to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid())) with check ((select public.is_sj_admin()) and user_id=(select auth.uid()));
alter policy acesso_proprio on public.viagens to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid())) with check ((select public.is_sj_admin()) and user_id=(select auth.uid()));
alter policy acesso_proprio on public.financeiro to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid())) with check ((select public.is_sj_admin()) and user_id=(select auth.uid()));
alter policy acesso_proprio on public.manutencoes to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid())) with check ((select public.is_sj_admin()) and user_id=(select auth.uid()));
alter policy acesso_proprio on public.metas to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid())) with check ((select public.is_sj_admin()) and user_id=(select auth.uid()));
alter policy pendencias_select on public.pendencias to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid()));
alter policy pendencias_insert on public.pendencias to authenticated with check (
 (select public.is_sj_admin()) and user_id=(select auth.uid())
 and exists(select 1 from public.motoristas m where m.id=motorista_id and m.user_id=(select auth.uid()))
 and (veiculo_id is null or exists(select 1 from public.veiculos v where v.id=veiculo_id and v.user_id=(select auth.uid()))));
alter policy pagamentos_pendencias_select on public.pagamentos_pendencias to authenticated using ((select public.is_sj_admin()) and user_id=(select auth.uid()));
create or replace function public.registrar_pagamento_pendencia(p_pendencia_id uuid,p_valor numeric,p_data date,p_forma text,p_observacoes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare v_p public.pendencias%rowtype; v_pago numeric; v_id uuid;
begin
 if auth.uid() is distinct from '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid then raise exception 'Apenas o administrador pode registrar pagamentos'; end if;
 select * into v_p from public.pendencias where id=p_pendencia_id and user_id=auth.uid() for update;
 if not found then raise exception 'Pendência não encontrada'; end if;
 if p_valor is null or p_valor<=0 then raise exception 'Valor inválido'; end if;
 if p_data is null then raise exception 'Data obrigatória'; end if;
 if p_forma is null or p_forma not in ('PIX','Dinheiro','Cartão de crédito','Cartão de débito','Transferência') then raise exception 'Forma inválida'; end if;
 select coalesce(sum(valor),0) into v_pago from public.pagamentos_pendencias where pendencia_id=p_pendencia_id;
 if p_valor>v_p.valor-v_pago then raise exception 'Pagamento maior que o saldo'; end if;
 insert into public.pagamentos_pendencias(user_id,pendencia_id,valor,data_pagamento,forma,observacoes)
 values(auth.uid(),p_pendencia_id,p_valor,p_data,p_forma,coalesce(p_observacoes,'')) returning id into v_id;
 return v_id;
end $$;
revoke execute on function public.registrar_pagamento_pendencia(uuid,numeric,date,text,text) from public,anon;
grant execute on function public.registrar_pagamento_pendencia(uuid,numeric,date,text,text) to authenticated;
create or replace function public.sj_guard_limite_cadastros()
returns trigger language plpgsql security invoker set search_path='' as $$
declare total integer;
begin
 if tg_table_name not in ('motoristas','veiculos') then raise exception 'Cadastro inválido'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(tg_table_name||new.user_id::text,0));
 if tg_table_name='motoristas' then
  select count(*) into total from public.motoristas where user_id=new.user_id;
 else
  select count(*) into total from public.veiculos where user_id=new.user_id;
 end if;
 if total>=15 then raise exception 'Limite de 15 cadastros atingido'; end if;
 return new;
end $$;
revoke execute on function public.sj_guard_limite_cadastros() from public,anon,authenticated;
create trigger sj_limite_motoristas before insert on public.motoristas for each row execute function public.sj_guard_limite_cadastros();
create trigger sj_limite_veiculos before insert on public.veiculos for each row execute function public.sj_guard_limite_cadastros();
