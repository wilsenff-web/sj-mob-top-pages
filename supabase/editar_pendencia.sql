create policy sj_admin_corrigir_pendencia_manual on public.pendencias for update to authenticated
 using(public.is_sj_admin() and user_id=(select auth.uid()) and viagem_uso_id is null and meta_semanal_id is null and referencia_cobranca is null)
 with check(public.is_sj_admin() and user_id=(select auth.uid()) and viagem_uso_id is null and meta_semanal_id is null and referencia_cobranca is null);
create function public.sj_validar_valor_pendencia() returns trigger language plpgsql security invoker set search_path='' as $$
declare pago numeric;
begin
 if new.valor is distinct from old.valor then
  if not coalesce(public.is_sj_admin(),false) or old.user_id is distinct from auth.uid() then raise exception 'Somente o administrador pode corrigir valores';end if;
  if new.valor is null or new.valor<0 or new.valor::text in ('NaN','Infinity','-Infinity') then raise exception 'Valor inválido';end if;
  select coalesce(sum(valor),0) into pago from public.pagamentos_pendencias where pendencia_id=old.id;
  if new.valor<pago then raise exception 'O valor não pode ser menor que o total já pago (%)',pago;end if;
 end if;
 return new;
end$$;
create trigger sj_validar_valor_pendencia before update on public.pendencias for each row execute function public.sj_validar_valor_pendencia();
create function public.sj_corrigir_valor_pendencia(p_id uuid,p_valor numeric,p_valor_anterior numeric) returns uuid language plpgsql security invoker set search_path='' as $$
declare p public.pendencias;
begin
 if not coalesce(public.is_sj_admin(),false) then raise exception 'Somente o administrador pode editar';end if;
 select * into p from public.pendencias where id=p_id and user_id=auth.uid() for update;
 if not found then raise exception 'Pendência não encontrada';end if;
 if p.viagem_uso_id is not null or p.meta_semanal_id is not null or p.referencia_cobranca is not null then raise exception 'Corrija a cobrança de origem deste registro automático';end if;
 if p.valor is distinct from p_valor_anterior then raise exception 'Valor alterado em outra sessão. Atualize a página';end if;
 if p_valor is null or p_valor<=0 or p_valor::text in ('NaN','Infinity','-Infinity') or p_valor<>round(p_valor,2) then raise exception 'Informe um valor maior que zero com até duas casas decimais';end if;
 update public.pendencias set valor=p_valor where id=p_id;
 return p_id;
end$$;
revoke all on function public.sj_corrigir_valor_pendencia(uuid,numeric,numeric) from public,anon;
grant execute on function public.sj_corrigir_valor_pendencia(uuid,numeric,numeric) to authenticated;
notify pgrst,'reload schema';
