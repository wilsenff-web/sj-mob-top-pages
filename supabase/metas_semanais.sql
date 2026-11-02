-- Sem alterar metas mensais, viagens aprovadas ou valores já cobrados.
create table public.sj_metas_semanais (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid(),
 motorista_id uuid not null references public.motoristas(id) on delete restrict,
 semana_inicio date not null check (extract(isodow from semana_inicio)=1),
 limite_km numeric(12,2) not null check(limite_km>0 and limite_km::text not in ('NaN','Infinity','-Infinity')),
 tarifa_excedente numeric(12,2) not null default 0.50 check(tarifa_excedente=0.50),
 created_at timestamptz not null default now(),
 unique(user_id,motorista_id,semana_inicio)
);
alter table public.sj_metas_semanais enable row level security;
revoke all on public.sj_metas_semanais from anon;
grant select,insert,update,delete on public.sj_metas_semanais to authenticated;
create policy sj_meta_admin on public.sj_metas_semanais for all to authenticated
 using(public.is_sj_admin() and user_id=(select auth.uid()))
 with check(public.is_sj_admin() and user_id=(select auth.uid()) and exists(select 1 from public.motoristas m where m.id=motorista_id and m.user_id=sj_metas_semanais.user_id));
create policy sj_meta_motorista on public.sj_metas_semanais for select to authenticated
 using(exists(select 1 from public.motoristas m where m.id=motorista_id and m.user_id=sj_metas_semanais.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo'));
alter table public.pendencias add column meta_semanal_id uuid unique references public.sj_metas_semanais(id) on delete restrict;
create policy sj_admin_atualizar_excedente on public.pendencias for update to authenticated
 using(public.is_sj_admin() and user_id=(select auth.uid()) and meta_semanal_id is not null)
 with check(public.is_sj_admin() and user_id=(select auth.uid()) and exists(select 1 from public.sj_metas_semanais g where g.id=meta_semanal_id and g.user_id=pendencias.user_id and g.motorista_id=pendencias.motorista_id));
create function public.sj_cobrar_excedente_semanal(p_meta_id uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare g public.sj_metas_semanais; km numeric; excesso numeric; total numeric; pid uuid; pago numeric; antigo numeric; v_descricao text;
begin
 if not public.is_sj_admin() or auth.uid() is null then raise exception 'Acesso restrito ao administrador' using errcode='42501'; end if;
 select * into g from public.sj_metas_semanais where id=p_meta_id and user_id=auth.uid() for update;
 if not found then raise exception 'Meta não encontrada'; end if;
 if exists(select 1 from public.viagens v where v.user_id=g.user_id and v.motorista_id=g.motorista_id and v.data_viagem between g.semana_inicio and g.semana_inicio+6 and v.tipo_uso='trabalho' and v.status_conferencia='pendente') then
 raise exception 'Confira as viagens de trabalho pendentes desta semana antes de gerar a cobrança'; end if;
 select coalesce(sum(v.km_rodados),0) into km from public.viagens v where v.user_id=g.user_id and v.motorista_id=g.motorista_id and v.data_viagem between g.semana_inicio and g.semana_inicio+6 and v.tipo_uso='trabalho' and v.status_conferencia='aprovada';
 excesso:=greatest(0,km-g.limite_km);total:=round(excesso*g.tarifa_excedente,2);
 select id,valor into pid,antigo from public.pendencias where meta_semanal_id=g.id and user_id=auth.uid() for update;
 select coalesce(sum(valor),0) into pago from public.pagamentos_pendencias where pendencia_id=pid;
 if total<pago then raise exception 'O novo valor seria menor que o já pago. Revise os pagamentos antes de recalcular'; end if;
 v_descricao:='Excedente semanal de trabalho: '||to_char(g.semana_inicio,'DD/MM/YYYY')||' a '||to_char(g.semana_inicio+6,'DD/MM/YYYY')||'. Trabalho aprovado: '||km||' km; limite: '||g.limite_km||' km; excedente: '||excesso||' km × R$ 0,50. Uso particular e outros usos excluídos.';
 if pid is null and total>0 then
 insert into public.pendencias(user_id,motorista_id,categoria,descricao,data_lancamento,valor,meta_semanal_id)
 values(g.user_id,g.motorista_id,'Outras dívidas',v_descricao,(now() at time zone 'America/Sao_Paulo')::date,total,g.id) returning id into pid;
 elsif pid is not null and total>0 then
 update public.pendencias set valor=total,descricao=v_descricao where id=pid;
 elsif pid is not null and total=0 then
 delete from public.pendencias where id=pid;pid:=null;
 end if;
 return jsonb_build_object('km_trabalho',km,'km_excedentes',excesso,'valor',total,'pendencia_id',pid);
end $$;
revoke all on function public.sj_cobrar_excedente_semanal(uuid) from public,anon;
grant execute on function public.sj_cobrar_excedente_semanal(uuid) to authenticated;
alter table public.viagens add column tarifa_km_particular numeric(12,2) check(tarifa_km_particular is null or tarifa_km_particular=0.60);
create function public.sj_tarifar_particular() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' and old.tarifa_km_particular is not null and exists(select 1 from public.pendencias p where p.viagem_uso_id=old.id)
 and (new.km_rodados,new.tarifa_km_particular,new.valor_uso) is distinct from (old.km_rodados,old.tarifa_km_particular,old.valor_uso) then
 raise exception 'Este uso particular já gerou cobrança. Resolva a pendência antes de alterar KM ou valor'; end if;
 if new.tipo_uso='uso_particular' and new.status_conferencia='aprovada' then
 if tg_op='INSERT' then new.tarifa_km_particular:=0.60;new.valor_uso:=round(new.km_rodados*0.60,2);
 elsif old.status_conferencia<>'aprovada' or old.tipo_uso<>'uso_particular' then new.tarifa_km_particular:=0.60;new.valor_uso:=round(new.km_rodados*0.60,2);
 elsif old.tarifa_km_particular is not null then new.tarifa_km_particular:=old.tarifa_km_particular;new.valor_uso:=round(new.km_rodados*old.tarifa_km_particular,2);
 end if;
 end if;
 return new;
end $$;
revoke all on function public.sj_tarifar_particular() from public,anon,authenticated;
create trigger zz_sj_tarifar_particular before insert or update on public.viagens for each row execute function public.sj_tarifar_particular();
notify pgrst,'reload schema';
