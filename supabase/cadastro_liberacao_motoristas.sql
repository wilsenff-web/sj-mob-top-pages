create table public.sj_solicitacoes_motoristas (
 id uuid primary key default gen_random_uuid(),
 auth_user_id uuid not null unique references auth.users(id),
 nome text not null check(length(btrim(nome)) between 2 and 120),
 telefone text not null default '' check(length(telefone)<=40),
 email text not null check(length(email) between 3 and 320),
 status text not null default 'pendente' check(status in ('pendente','aprovada','recusada')),
 motorista_id uuid references public.motoristas(id),
 created_at timestamptz not null default now(),
 revisado_em timestamptz,
 revisado_por uuid references auth.users(id),
 constraint sj_estado_solicitacao check (
  (status='pendente' and motorista_id is null and revisado_em is null and revisado_por is null) or
  (status='aprovada' and motorista_id is not null and revisado_em is not null and revisado_por is not null) or
  (status='recusada' and motorista_id is null and revisado_em is not null and revisado_por is not null))
);
alter table public.sj_solicitacoes_motoristas enable row level security;
grant select,insert,update on public.sj_solicitacoes_motoristas to authenticated;
revoke all on public.sj_solicitacoes_motoristas from anon;
create policy sj_solicitacao_select on public.sj_solicitacoes_motoristas for select to authenticated
 using ((select public.is_sj_admin()) or auth_user_id=(select auth.uid()));
create policy sj_solicitacao_insert on public.sj_solicitacoes_motoristas for insert to authenticated
 with check (auth_user_id=(select auth.uid()) and not coalesce((select public.is_sj_admin()),false)
 and lower(email)=lower((select auth.jwt()->>'email')) and status='pendente' and motorista_id is null and revisado_em is null and revisado_por is null);
create policy sj_solicitacao_update on public.sj_solicitacoes_motoristas for update to authenticated
 using ((select public.is_sj_admin())) with check ((select public.is_sj_admin()));
create function public.sj_guard_solicitacao_motorista()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if not coalesce(public.is_sj_admin(),false) then raise exception 'Apenas o administrador pode liberar acessos';end if;
  if (new.id,new.auth_user_id,new.nome,new.telefone,new.email,new.created_at) is distinct from (old.id,old.auth_user_id,old.nome,old.telefone,old.email,old.created_at) then raise exception 'Identidade da solicitação é imutável';end if;
  if old.status<>'pendente' then raise exception 'Solicitação já revisada';end if;
  if new.status not in ('aprovada','recusada') then raise exception 'Decisão inválida';end if;
  if new.status='aprovada' and not exists(select 1 from public.motoristas m where m.id=new.motorista_id and m.user_id=auth.uid() and m.auth_user_id=new.auth_user_id and m.status='ativo') then raise exception 'Vinculação do motorista não confere';end if;
  new.revisado_em:=now();new.revisado_por:=auth.uid();
 end if;
 return new;
end $$;
revoke execute on function public.sj_guard_solicitacao_motorista() from public,anon,authenticated;
create trigger sj_solicitacao_guard before update on public.sj_solicitacoes_motoristas for each row execute function public.sj_guard_solicitacao_motorista();
create function public.sj_revisar_acesso_motorista(p_solicitacao_id uuid,p_decisao text,p_motorista_id uuid default null,p_criar_cadastro boolean default false)
returns uuid language plpgsql security invoker set search_path='' as $$
declare r public.sj_solicitacoes_motoristas%rowtype; m public.motoristas%rowtype; destino uuid;
begin
 if not coalesce(public.is_sj_admin(),false) then raise exception 'Apenas o administrador pode liberar acessos';end if;
 select * into r from public.sj_solicitacoes_motoristas where id=p_solicitacao_id for update;
 if not found or r.status<>'pendente' then raise exception 'Solicitação inexistente ou já revisada';end if;
 if r.auth_user_id=auth.uid() then raise exception 'A conta administrativa não pode ser vinculada como motorista';end if;
 if p_decisao='recusada' then
  update public.sj_solicitacoes_motoristas set status='recusada' where id=r.id;return null;
 elsif p_decisao<>'aprovada' or p_decisao is null then raise exception 'Decisão inválida';end if;
 if p_criar_cadastro then
  if p_motorista_id is not null then raise exception 'Escolha criar OU vincular cadastro';end if;
  if exists(select 1 from public.motoristas where auth_user_id=r.auth_user_id) then raise exception 'Conta já vinculada a um motorista';end if;
  insert into public.motoristas(user_id,nome,telefone,status,auth_user_id) values(auth.uid(),r.nome,nullif(r.telefone,''),'ativo',r.auth_user_id) returning id into destino;
 else
  if p_motorista_id is null then raise exception 'Selecione o cadastro correto do motorista';end if;
  select * into m from public.motoristas where id=p_motorista_id and user_id=auth.uid() for update;
  if not found then raise exception 'Cadastro de motorista não encontrado';end if;
  if m.auth_user_id is not null and m.auth_user_id<>r.auth_user_id then raise exception 'Cadastro já vinculado a outra conta';end if;
  update public.motoristas set auth_user_id=r.auth_user_id,status='ativo' where id=m.id returning id into destino;
 end if;
 update public.sj_solicitacoes_motoristas set status='aprovada',motorista_id=destino where id=r.id;
 return destino;
end $$;
revoke execute on function public.sj_revisar_acesso_motorista(uuid,text,uuid,boolean) from public,anon;
grant execute on function public.sj_revisar_acesso_motorista(uuid,text,uuid,boolean) to authenticated;
