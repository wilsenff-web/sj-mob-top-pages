-- Horário local de início do uso do veículo, sem inferir horas de registros antigos.
alter table public.viagens add column if not exists hora_inicio time without time zone;
alter table public.viagens add constraint viagens_hora_inicio_valida check (hora_inicio is null or hora_inicio < time '24:00');
comment on column public.viagens.hora_inicio is 'Hora local de início da viagem/uso do carro, America/Sao_Paulo. NULL significa não informada no histórico.';
CREATE OR REPLACE FUNCTION public.sj_guard_viagens_conferencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare admin_id constant uuid := '92d8d744-f382-44ad-bcc3-f951765ffa73';
begin
 if tg_op='INSERT' then
   if auth.uid() is distinct from admin_id then
     new.status_conferencia:='pendente';
     new.conferido_em:=null;
     new.conferido_por:=null;
   else
     new.status_conferencia:='aprovada';
     new.conferido_em:=now();
     new.conferido_por:=admin_id;
   end if;
 elsif tg_op='UPDATE' then
   if auth.uid() is distinct from admin_id then
     raise exception 'Somente o administrador pode alterar uma viagem cadastrada';
   end if;
   if new.status_conferencia is distinct from old.status_conferencia then
     if old.status_conferencia <> 'pendente' then raise exception 'Viagem já conferida'; end if;
     if new.status_conferencia not in ('aprovada','rejeitada') then raise exception 'Revisão inválida'; end if;
     if (new.id,new.user_id,new.motorista_id,new.veiculo_id,new.data_viagem,new.hora_inicio,new.km_rodados,new.faturamento,new.observacoes,new.km_inicial,new.km_final,new.origem,new.destino,new.tipo_uso,new.valor_uso)
       is distinct from
        (old.id,old.user_id,old.motorista_id,old.veiculo_id,old.data_viagem,old.hora_inicio,old.km_rodados,old.faturamento,old.observacoes,old.km_inicial,old.km_final,old.origem,old.destino,old.tipo_uso,old.valor_uso)
     then raise exception 'Revise os dados separadamente antes de aprovar'; end if;
     new.conferido_em:=now();
     new.conferido_por:=admin_id;
   else
     new.conferido_em:=old.conferido_em;
     new.conferido_por:=old.conferido_por;
   end if;
 end if;
 return new;
end $function$;

create or replace function sj_private.ultimo_km_veiculo_horario(p_veiculo_id uuid,p_data date,p_hora time without time zone)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare dono uuid; leitura jsonb;
begin
 if auth.uid() is null or p_data is null or p_hora is null or p_hora>=time '24:00' then raise exception 'Acesso restrito ou data/hora inválida' using errcode='42501'; end if;
 select v.user_id into dono from public.veiculos v
 where v.id=p_veiculo_id and (
 (public.is_sj_admin() and v.user_id=auth.uid()) or
 (v.status='ativo' and exists(select 1 from public.motoristas m where m.user_id=v.user_id and m.auth_user_id=auth.uid() and m.status='ativo'))
 );
 if not found then raise exception 'Veículo não autorizado' using errcode='42501'; end if;
 select jsonb_build_object('km_final',v.km_final,'data_viagem',v.data_viagem,'hora_inicio',v.hora_inicio,'situacao',v.status_conferencia) into leitura
 from public.viagens v where v.user_id=dono and v.veiculo_id=p_veiculo_id
 and (v.data_viagem<p_data or (v.data_viagem=p_data and (v.hora_inicio is null or v.hora_inicio<p_hora)))
 and v.status_conferencia<>'rejeitada' and v.km_final is not null and v.km_final>=0 and v.km_final::text not in ('NaN','Infinity','-Infinity')
 order by v.data_viagem desc,v.hora_inicio desc nulls last,v.km_final desc,v.id desc limit 1;
 return leitura;
end $$;
revoke all on function sj_private.ultimo_km_veiculo_horario(uuid,date,time without time zone) from public,anon;
grant execute on function sj_private.ultimo_km_veiculo_horario(uuid,date,time without time zone) to authenticated;
create or replace function public.sj_ultimo_km_veiculo_horario(p_veiculo_id uuid,p_data date,p_hora time without time zone)
returns jsonb language sql stable security invoker set search_path='' as $$
 select sj_private.ultimo_km_veiculo_horario(p_veiculo_id,p_data,p_hora);
$$;
revoke all on function public.sj_ultimo_km_veiculo_horario(uuid,date,time without time zone) from public,anon;
grant execute on function public.sj_ultimo_km_veiculo_horario(uuid,date,time without time zone) to authenticated;
notify pgrst,'reload schema';
