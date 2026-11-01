create schema sj_private;
revoke all on schema sj_private from public,anon;
grant usage on schema sj_private to authenticated;
create function sj_private.ultimo_km_veiculo(p_veiculo_id uuid,p_data date)
returns jsonb language plpgsql stable security definer set search_path='' as $f$
declare dono uuid; leitura jsonb;
begin
 if auth.uid() is null or p_data is null then raise exception 'Acesso restrito ou data inválida' using errcode='42501'; end if;
 select v.user_id into dono from public.veiculos v
 where v.id=p_veiculo_id and (
 (public.is_sj_admin() and v.user_id=auth.uid()) or
 (v.status='ativo' and exists(select 1 from public.motoristas m where m.user_id=v.user_id and m.auth_user_id=auth.uid() and m.status='ativo'))
 );
 if not found then raise exception 'Veículo não autorizado' using errcode='42501'; end if;
 select jsonb_build_object('km_final',v.km_final,'data_viagem',v.data_viagem,'situacao',v.status_conferencia) into leitura
 from public.viagens v where v.user_id=dono and v.veiculo_id=p_veiculo_id and v.data_viagem<=p_data
 and v.status_conferencia<>'rejeitada' and v.km_final is not null and v.km_final>=0 and v.km_final::text not in ('NaN','Infinity','-Infinity')
 order by v.data_viagem desc,v.km_final desc,v.id desc limit 1;
 return leitura;
end $f$;
revoke all on function sj_private.ultimo_km_veiculo(uuid,date) from public,anon;
grant execute on function sj_private.ultimo_km_veiculo(uuid,date) to authenticated;
create function public.sj_ultimo_km_veiculo(p_veiculo_id uuid,p_data date)
returns jsonb language sql stable security invoker set search_path='' as $f$
 select sj_private.ultimo_km_veiculo(p_veiculo_id,p_data);
$f$;
revoke all on function public.sj_ultimo_km_veiculo(uuid,date) from public,anon;
grant execute on function public.sj_ultimo_km_veiculo(uuid,date) to authenticated;