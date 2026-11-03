-- Valores e baixas anteriores permanecem intactos.
alter table public.viagens add column pagamento_controlado boolean not null default false;
alter table public.viagens alter column pagamento_controlado set default true;
create table public.sj_vinculos_pagamento_viagem(
 viagem_id uuid primary key references public.viagens(id) on delete cascade,
 user_id uuid not null references auth.users(id),
 motorista_id uuid not null references public.motoristas(id),
 pendencia_id uuid references public.pendencias(id) on delete cascade,
 sem_cobranca boolean not null default false,
 created_at timestamptz not null default now(),
 check((sem_cobranca and pendencia_id is null) or (not sem_cobranca and pendencia_id is not null))
);
create table public.sj_recebimentos_viagens(
 referencia uuid primary key,
 user_id uuid not null references auth.users(id),
 viagem_id uuid not null references public.viagens(id) on delete cascade,
 pagamento_id uuid not null unique references public.pagamentos_pendencias(id) on delete cascade,
 comprovante_id uuid unique references public.comprovantes_motoristas(id),
 created_at timestamptz not null default now()
);
alter table public.sj_vinculos_pagamento_viagem enable row level security;
alter table public.sj_recebimentos_viagens enable row level security;
revoke all on public.sj_vinculos_pagamento_viagem,public.sj_recebimentos_viagens from anon;
grant select,insert on public.sj_vinculos_pagamento_viagem,public.sj_recebimentos_viagens to authenticated;
create policy sj_vinculo_ler on public.sj_vinculos_pagamento_viagem for select to authenticated using((public.is_sj_admin() and user_id=(select auth.uid())) or exists(select 1 from public.motoristas m where m.id=motorista_id and m.user_id=sj_vinculos_pagamento_viagem.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo'));
create policy sj_vinculo_inserir on public.sj_vinculos_pagamento_viagem for insert to authenticated with check(public.is_sj_admin() and user_id=(select auth.uid()) and exists(select 1 from public.viagens v where v.id=viagem_id and v.user_id=sj_vinculos_pagamento_viagem.user_id and v.motorista_id=sj_vinculos_pagamento_viagem.motorista_id and v.status_conferencia='aprovada') and (sem_cobranca or exists(select 1 from public.pendencias p where p.id=pendencia_id and p.user_id=sj_vinculos_pagamento_viagem.user_id and p.motorista_id=sj_vinculos_pagamento_viagem.motorista_id)));
create policy sj_recebimento_ler on public.sj_recebimentos_viagens for select to authenticated using((public.is_sj_admin() and user_id=(select auth.uid())) or exists(select 1 from public.viagens v join public.motoristas m on m.id=v.motorista_id and m.user_id=v.user_id where v.id=viagem_id and v.user_id=sj_recebimentos_viagens.user_id and m.auth_user_id=(select auth.uid()) and m.status='ativo'));
create policy sj_recebimento_inserir on public.sj_recebimentos_viagens for insert to authenticated with check(public.is_sj_admin() and user_id=(select auth.uid()) and exists(select 1 from public.sj_vinculos_pagamento_viagem l join public.pagamentos_pendencias p on p.pendencia_id=l.pendencia_id and p.user_id=l.user_id where l.viagem_id=sj_recebimentos_viagens.viagem_id and l.user_id=sj_recebimentos_viagens.user_id and p.id=pagamento_id) and (comprovante_id is null or exists(select 1 from public.comprovantes_motoristas c where c.id=comprovante_id and c.viagem_id=sj_recebimentos_viagens.viagem_id and c.user_id=sj_recebimentos_viagens.user_id and c.status='confirmado')));
create function public.sj_guard_controle_pagamento() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if tg_op='INSERT' then new.pagamento_controlado:=true;
 else
  if new.pagamento_controlado is distinct from old.pagamento_controlado then raise exception 'Controle de pagamento não pode ser alterado manualmente';end if;
  if (new.motorista_id,new.user_id) is distinct from(old.motorista_id,old.user_id) and exists(select 1 from public.sj_vinculos_pagamento_viagem where viagem_id=old.id)then raise exception 'Esta viagem tem uma cobrança vinculada. Preserve o motorista da cobrança';end if;
 end if;return new;end$$;
create trigger sj_guard_controle_pagamento before insert or update on public.viagens for each row execute function public.sj_guard_controle_pagamento();
create function public.sj_guard_motorista_pendencia() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if (new.motorista_id,new.user_id) is distinct from(old.motorista_id,old.user_id) and exists(select 1 from public.sj_vinculos_pagamento_viagem where pendencia_id=old.id)then raise exception 'Pendência vinculada a viagem: mantenha o mesmo motorista';end if;return new;end$$;
create trigger sj_guard_motorista_pendencia before update on public.pendencias for each row execute function public.sj_guard_motorista_pendencia();
create function public.sj_definir_pagamento_viagem(p_viagem_id uuid,p_pendencia_id uuid default null,p_valor numeric default null,p_vencimento date default null,p_sem_cobranca boolean default false) returns uuid language plpgsql security invoker set search_path='' as $$
declare v public.viagens; l public.sj_vinculos_pagamento_viagem; pid uuid;
begin
 if not coalesce(public.is_sj_admin(),false) then raise exception 'Somente o administrador define cobranças';end if;
 select * into v from public.viagens where id=p_viagem_id and user_id=auth.uid() for update;
 if not found or v.status_conferencia<>'aprovada' then raise exception 'Confira a viagem antes de definir seu pagamento';end if;
 select * into l from public.sj_vinculos_pagamento_viagem where viagem_id=v.id;
 if found then return l.pendencia_id;end if;
 if p_sem_cobranca then
  if p_pendencia_id is not null or p_valor is not null then raise exception 'Escolha sem cobrança OU um valor';end if;
  insert into public.sj_vinculos_pagamento_viagem(viagem_id,user_id,motorista_id,sem_cobranca)values(v.id,v.user_id,v.motorista_id,true);return null;
 end if;
 if p_pendencia_id is not null then
  select id into pid from public.pendencias where id=p_pendencia_id and user_id=v.user_id and motorista_id=v.motorista_id;
  if not found then raise exception 'Escolha uma cobrança do mesmo motorista';end if;
 else
  -- Reaproveita cobrança automática de uso particular/casa já existente.
  select id into pid from public.pendencias where viagem_uso_id=v.id and user_id=v.user_id;
  if pid is null then
   if p_valor is null or p_valor<=0 or p_valor::text in ('NaN','Infinity','-Infinity') or p_valor<>round(p_valor,2)then raise exception 'Informe o valor devido ao proprietário, não o faturamento da corrida';end if;
   insert into public.pendencias(user_id,motorista_id,veiculo_id,categoria,descricao,data_lancamento,vencimento,valor)
   values(v.user_id,v.motorista_id,v.veiculo_id,'Outras dívidas','Repasse da viagem de '||to_char(v.data_viagem,'DD/MM/YYYY')||' - '||coalesce(v.origem,'')||' → '||coalesce(v.destino,''),v.data_viagem,p_vencimento,p_valor) returning id into pid;
  end if;
 end if;
 insert into public.sj_vinculos_pagamento_viagem(viagem_id,user_id,motorista_id,pendencia_id)values(v.id,v.user_id,v.motorista_id,pid);
 return pid;
end$$;
create function public.sj_baixar_pagamento_viagem(p_viagem_id uuid,p_valor numeric,p_data date,p_forma text,p_observacoes text,p_referencia uuid,p_comprovante_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$
declare v public.viagens; l public.sj_vinculos_pagamento_viagem; c public.comprovantes_motoristas; pid uuid;
begin
 if not coalesce(public.is_sj_admin(),false) or p_referencia is null then raise exception 'Acesso restrito';end if;
 select * into v from public.viagens where id=p_viagem_id and user_id=auth.uid() for update;
 if not found or v.status_conferencia<>'aprovada'then raise exception 'Viagem não conferida';end if;
 select pagamento_id into pid from public.sj_recebimentos_viagens where referencia=p_referencia and user_id=auth.uid() and viagem_id=v.id;if found then return pid;end if;
 select * into l from public.sj_vinculos_pagamento_viagem where viagem_id=v.id;
 if not found or l.sem_cobranca then raise exception 'Defina ou vincule primeiro a cobrança da viagem';end if;
 if p_comprovante_id is not null then
  select * into c from public.comprovantes_motoristas where id=p_comprovante_id and user_id=auth.uid() and viagem_id=v.id for update;
  if not found or c.status<>'confirmado'then raise exception 'Confirme a conferência do comprovante antes da baixa';end if;
  if c.valor is distinct from p_valor or c.data_pagamento is distinct from p_data then raise exception 'A baixa deve usar o valor e a data do comprovante';end if;
  if exists(select 1 from public.financeiro where comprovante_id=c.id) or exists(select 1 from public.sj_recebimentos_viagens where comprovante_id=c.id)then raise exception 'Este comprovante já foi recebido';end if;
 end if;
 if p_valor is null or p_valor<=0 or p_valor::text in ('NaN','Infinity','-Infinity') or p_valor<>round(p_valor,2)then raise exception 'Valor inválido';end if;
 pid:=public.registrar_pagamento_pendencia(l.pendencia_id,p_valor,p_data,p_forma,coalesce(p_observacoes,''));
 insert into public.sj_recebimentos_viagens(referencia,user_id,viagem_id,pagamento_id,comprovante_id)values(p_referencia,auth.uid(),v.id,pid,p_comprovante_id);
 return pid;
end$$;
revoke all on function public.sj_definir_pagamento_viagem(uuid,uuid,numeric,date,boolean) from public,anon;
revoke all on function public.sj_baixar_pagamento_viagem(uuid,numeric,date,text,text,uuid,uuid) from public,anon;
grant execute on function public.sj_definir_pagamento_viagem(uuid,uuid,numeric,date,boolean),public.sj_baixar_pagamento_viagem(uuid,numeric,date,text,text,uuid,uuid) to authenticated;
notify pgrst,'reload schema';

CREATE OR REPLACE FUNCTION public.sj_registrar_recebimento_comprovante(p_comprovante_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.comprovantes_motoristas%rowtype; novo_id uuid;
begin
 if auth.uid() is distinct from '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid then
   raise exception 'Apenas o administrador pode registrar recebimentos';
 end if;
 select * into c from public.comprovantes_motoristas
 where id=p_comprovante_id and user_id=auth.uid() and status='confirmado' for update;
 if not found then raise exception 'Comprovante inexistente, não confirmado ou sem permissão'; end if;
 if exists(select 1 from public.sj_recebimentos_viagens where comprovante_id=c.id) then raise exception 'Este comprovante já foi recebido na baixa da viagem'; end if;
 if c.viagem_id is not null and (exists(select 1 from public.viagens v where v.id=c.viagem_id and v.pagamento_controlado) or exists(select 1 from public.sj_vinculos_pagamento_viagem l where l.viagem_id=c.viagem_id)) then raise exception 'Use Pagamento da viagem para dar baixa na cobrança sem duplicar o caixa'; end if;
 if exists(select 1 from public.financeiro where comprovante_id=c.id) then
   raise exception 'Este comprovante já foi registrado no Financeiro';
 end if;
 insert into public.financeiro(user_id,data_lancamento,tipo,categoria,descricao,valor,motorista_id,comprovante_id)
 values(c.user_id,c.data_pagamento,'receita','Recebimento de motorista',
        'Comprovante confirmado '||c.id::text,c.valor,c.motorista_id,c.id)
 returning id into novo_id;
 return novo_id;
end $function$
