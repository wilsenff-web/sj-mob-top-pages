alter table public.viagens
 add column tipo_uso text not null default 'trabalho',
 add column valor_uso numeric(12,2) not null default 0,
 add constraint viagens_tipo_uso_check check(tipo_uso in ('trabalho','deslocamento','manutencao','ida_casa','uso_particular')),
 add constraint viagens_valor_uso_check check(valor_uso>=0 and valor_uso::text not in ('NaN','Infinity','-Infinity')),
 add constraint viagens_receita_por_tipo_check check(tipo_uso='trabalho' or faturamento=0),
 add constraint viagens_cobranca_por_tipo_check check(tipo_uso in ('ida_casa','uso_particular') or valor_uso=0);
alter table public.pendencias add column viagem_uso_id uuid unique references public.viagens(id) on delete restrict;
alter table public.pendencias drop constraint pendencias_categoria_check;
alter table public.pendencias add constraint pendencias_categoria_check check(categoria in ('Diária atrasada','Pedágio','Multa de trânsito','Abastecimento','Adiantamento de dinheiro','Empréstimo','Mau uso do veículo','Outras dívidas','Diária','Comissão','A combinar','Uso particular','Ida para casa'));
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
     if (new.id,new.user_id,new.motorista_id,new.veiculo_id,new.data_viagem,new.km_rodados,new.faturamento,new.observacoes,new.km_inicial,new.km_final,new.origem,new.destino,new.tipo_uso,new.valor_uso)
       is distinct from
        (old.id,old.user_id,old.motorista_id,old.veiculo_id,old.data_viagem,old.km_rodados,old.faturamento,old.observacoes,old.km_inicial,old.km_final,old.origem,old.destino,old.tipo_uso,old.valor_uso)
     then raise exception 'Revise os dados separadamente antes de aprovar'; end if;
     new.conferido_em:=now();
     new.conferido_por:=admin_id;
   else
     new.conferido_em:=old.conferido_em;
     new.conferido_por:=old.conferido_por;
   end if;
 end if;
 return new;
end $function$
;
create function public.sj_guard_viagem_tipo_uso() returns trigger language plpgsql security invoker set search_path='' as $f$
begin
 if tg_op='INSERT' and auth.uid() is distinct from '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid and new.valor_uso<>0 then
  raise exception 'O valor combinado é definido pelo administrador';
 end if;
 if tg_op='UPDATE' and exists(select 1 from public.pendencias p where p.viagem_uso_id=old.id)
 and (new.tipo_uso,new.valor_uso,new.motorista_id,new.veiculo_id,new.user_id,new.data_viagem) is distinct from (old.tipo_uso,old.valor_uso,old.motorista_id,old.veiculo_id,old.user_id,old.data_viagem) then
  raise exception 'Este uso já gerou cobrança. Resolva a pendência vinculada antes de alterar os dados da cobrança.';
 end if;
 return new;
end $f$;
create trigger sj_guard_viagens_uso_trigger before insert or update on public.viagens for each row execute function public.sj_guard_viagem_tipo_uso();
create function public.sj_gerar_pendencia_uso() returns trigger language plpgsql security invoker set search_path='' as $f$
declare gerar boolean;
begin
 if new.status_conferencia<>'aprovada' or new.valor_uso<=0 or new.tipo_uso not in ('ida_casa','uso_particular') then return new; end if;
 if tg_op='INSERT' then gerar:=true;
 else gerar:=old.status_conferencia<>'aprovada' or (new.tipo_uso,new.valor_uso) is distinct from (old.tipo_uso,old.valor_uso); end if;
 if not gerar then return new; end if;
 if not public.is_sj_admin() or auth.uid() is distinct from new.user_id then raise exception 'Apenas o administrador pode gerar a cobrança de uso'; end if;
 insert into public.pendencias(user_id,motorista_id,veiculo_id,categoria,descricao,data_lancamento,valor,viagem_uso_id)
 values(new.user_id,new.motorista_id,new.veiculo_id,case when new.tipo_uso='uso_particular' then 'Uso particular' else 'Ida para casa' end,
 'Uso do veículo em '||to_char(new.data_viagem,'DD/MM/YYYY')||': '||coalesce(new.origem,'')||' → '||coalesce(new.destino,''),new.data_viagem,new.valor_uso,new.id)
 on conflict(viagem_uso_id) do nothing;
 return new;
end $f$;
create trigger sj_gerar_pendencia_uso_trigger after insert or update on public.viagens for each row execute function public.sj_gerar_pendencia_uso();
alter policy pendencias_insert on public.pendencias with check(
 (select public.is_sj_admin()) and user_id=(select auth.uid())
 and exists(select 1 from public.motoristas m where m.id=pendencias.motorista_id and m.user_id=(select auth.uid()))
 and (veiculo_id is null or exists(select 1 from public.veiculos v where v.id=pendencias.veiculo_id and v.user_id=(select auth.uid())))
 and (viagem_uso_id is null or exists(select 1 from public.viagens v where v.id=pendencias.viagem_uso_id and v.user_id=pendencias.user_id and v.motorista_id=pendencias.motorista_id and v.veiculo_id=pendencias.veiculo_id and v.valor_uso=pendencias.valor and v.status_conferencia='aprovada' and v.tipo_uso in ('ida_casa','uso_particular')))
);
revoke all on function public.sj_guard_viagem_tipo_uso() from public,anon,authenticated;
revoke all on function public.sj_gerar_pendencia_uso() from public,anon,authenticated;
