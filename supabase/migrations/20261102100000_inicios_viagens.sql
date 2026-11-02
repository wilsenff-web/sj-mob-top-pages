-- Estrutura aditiva: não altera dados, restrições ou permissões das tabelas existentes.
create table public.sj_inicios_viagens (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 motorista_id uuid not null,
 veiculo_id uuid not null,
 data_viagem date not null,
 hora_inicio time without time zone not null check(hora_inicio<time '24:00'),
 origem text not null check(nullif(btrim(origem),'') is not null),
 destino text,
 km_inicial numeric(12,2) not null check(km_inicial>=0 and km_inicial::text not in ('NaN','Infinity','-Infinity')),
 tipo_uso text not null default 'trabalho' check(tipo_uso in ('trabalho','deslocamento','manutencao','ida_casa','uso_particular')),
 observacoes text not null default '',
 created_at timestamptz not null default now(),
 foreign key(motorista_id,user_id) references public.motoristas(id,user_id),
 foreign key(veiculo_id,user_id) references public.veiculos(id,user_id),
 unique(user_id,veiculo_id)
);
alter table public.sj_inicios_viagens enable row level security;
revoke all on public.sj_inicios_viagens from anon;
grant select,insert,update,delete on public.sj_inicios_viagens to authenticated;
create policy sj_inicio_admin on public.sj_inicios_viagens for all to authenticated
 using(public.is_sj_admin() and user_id=(select auth.uid()))
 with check(public.is_sj_admin() and user_id=(select auth.uid()));
create policy sj_inicio_motorista_ler on public.sj_inicios_viagens for select to authenticated
 using(exists(select 1 from public.motoristas m where m.id=sj_inicios_viagens.motorista_id and m.user_id=sj_inicios_viagens.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo'));
create policy sj_inicio_motorista_inserir on public.sj_inicios_viagens for insert to authenticated
 with check(user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 and exists(select 1 from public.motoristas m where m.id=sj_inicios_viagens.motorista_id and m.user_id=sj_inicios_viagens.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo')
 and exists(select 1 from public.veiculos v where v.id=sj_inicios_viagens.veiculo_id and v.user_id=sj_inicios_viagens.user_id and v.status='ativo'));
create policy sj_inicio_motorista_concluir on public.sj_inicios_viagens for delete to authenticated
 using(exists(select 1 from public.motoristas m where m.id=sj_inicios_viagens.motorista_id and m.user_id=sj_inicios_viagens.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo'));
create function public.sj_concluir_inicio_viagem(p_inicio_id uuid,p_km_final numeric,p_destino text,p_faturamento numeric default 0,p_observacoes text default null,p_valor_uso numeric default 0)
 returns uuid language plpgsql security invoker set search_path='' as $$
declare r public.sj_inicios_viagens; viagem uuid; receita numeric; combinado numeric; administrador boolean:=coalesce(public.is_sj_admin(),false);
begin
 if auth.uid() is null then raise exception 'Acesso restrito' using errcode='42501'; end if;
 select * into r from public.sj_inicios_viagens i where i.id=p_inicio_id and (
 (administrador and i.user_id=auth.uid()) or exists(select 1 from public.motoristas m where m.id=i.motorista_id and m.user_id=i.user_id and m.auth_user_id=auth.uid() and m.status='ativo')) for update;
 if not found then raise exception 'Início não encontrado ou já concluído. Atualize a tela'; end if;
 if p_km_final is null or p_km_final<r.km_inicial or p_km_final::text in ('NaN','Infinity','-Infinity') then raise exception 'Informe um KM final válido, maior ou igual ao inicial'; end if;
 if nullif(btrim(p_destino),'') is null then raise exception 'Informe o destino para concluir'; end if;
 receita:=case when r.tipo_uso='trabalho' then p_faturamento else 0 end;
 if receita is null or receita<0 or receita::text in ('NaN','Infinity','-Infinity') then raise exception 'Informe um faturamento válido'; end if;
 if not administrador and coalesce(p_valor_uso,0)<>0 then raise exception 'Somente o administrador define cobranças'; end if;
 combinado:=case when administrador and r.tipo_uso='ida_casa' then coalesce(p_valor_uso,0) else 0 end;
 if combinado<0 or combinado::text in ('NaN','Infinity','-Infinity') then raise exception 'Valor combinado inválido'; end if;
 insert into public.viagens(user_id,motorista_id,veiculo_id,data_viagem,hora_inicio,origem,destino,km_inicial,km_final,km_rodados,faturamento,tipo_uso,valor_uso,observacoes)
 values(r.user_id,r.motorista_id,r.veiculo_id,r.data_viagem,r.hora_inicio,r.origem,btrim(p_destino),r.km_inicial,p_km_final,round(p_km_final-r.km_inicial,2),receita,r.tipo_uso,combinado,coalesce(p_observacoes,r.observacoes)) returning id into viagem;
 delete from public.sj_inicios_viagens where id=r.id;
 return viagem;
end $$;
revoke all on function public.sj_concluir_inicio_viagem(uuid,numeric,text,numeric,text,numeric) from public,anon;
grant execute on function public.sj_concluir_inicio_viagem(uuid,numeric,text,numeric,text,numeric) to authenticated;
notify pgrst,'reload schema';

create or replace function public.sj_concluir_inicio_viagem(p_inicio_id uuid,p_km_final numeric,p_destino text,p_faturamento numeric default 0,p_observacoes text default null,p_valor_uso numeric default 0)
 returns uuid language plpgsql security invoker set search_path='' as $$
declare r public.sj_inicios_viagens; viagem uuid; receita numeric; combinado numeric; administrador boolean:=coalesce(public.is_sj_admin(),false);
begin
 if auth.uid() is null then raise exception 'Acesso restrito' using errcode='42501'; end if;
 delete from public.sj_inicios_viagens i where i.id=p_inicio_id and (
 (administrador and i.user_id=auth.uid()) or exists(select 1 from public.motoristas m where m.id=i.motorista_id and m.user_id=i.user_id and m.auth_user_id=auth.uid() and m.status='ativo')) returning i.* into r;
 if not found then raise exception 'Início não encontrado ou já concluído. Atualize a tela'; end if;
 if p_km_final is null or p_km_final<r.km_inicial or p_km_final::text in ('NaN','Infinity','-Infinity') then raise exception 'Informe um KM final válido, maior ou igual ao inicial'; end if;
 if nullif(btrim(p_destino),'') is null then raise exception 'Informe o destino para concluir'; end if;
 receita:=case when r.tipo_uso='trabalho' then p_faturamento else 0 end;
 if receita is null or receita<0 or receita::text in ('NaN','Infinity','-Infinity') then raise exception 'Informe um faturamento válido'; end if;
 if not administrador and coalesce(p_valor_uso,0)<>0 then raise exception 'Somente o administrador define cobranças'; end if;
 combinado:=case when administrador and r.tipo_uso='ida_casa' then coalesce(p_valor_uso,0) else 0 end;
 if combinado<0 or combinado::text in ('NaN','Infinity','-Infinity') then raise exception 'Valor combinado inválido'; end if;
 insert into public.viagens(user_id,motorista_id,veiculo_id,data_viagem,hora_inicio,origem,destino,km_inicial,km_final,km_rodados,faturamento,tipo_uso,valor_uso,observacoes)
 values(r.user_id,r.motorista_id,r.veiculo_id,r.data_viagem,r.hora_inicio,r.origem,btrim(p_destino),r.km_inicial,p_km_final,round(p_km_final-r.km_inicial,2),receita,r.tipo_uso,combinado,coalesce(p_observacoes,r.observacoes)) returning id into viagem;

 return viagem;
end $$;
revoke all on function public.sj_concluir_inicio_viagem(uuid,numeric,text,numeric,text,numeric) from public,anon;
grant execute on function public.sj_concluir_inicio_viagem(uuid,numeric,text,numeric,text,numeric) to authenticated;
notify pgrst,'reload schema';
