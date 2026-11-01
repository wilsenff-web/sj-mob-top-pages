-- SJ MOB TOP | Migração única: aprovação de viagens e recebimentos de comprovantes
-- Executar somente após revisar. Preserva viagens existentes como aprovadas.
begin;
alter table public.viagens add column if not exists status_conferencia text not null default 'aprovada';
alter table public.viagens add column if not exists conferido_em timestamptz;
alter table public.viagens add column if not exists conferido_por uuid;
alter table public.viagens drop constraint if exists viagens_status_conferencia_check;
alter table public.viagens add constraint viagens_status_conferencia_check check(status_conferencia in ('pendente','aprovada','rejeitada'));
-- A coluna nova recebe 'aprovada' em viagens históricas; só lançamentos novos de motorista ficam pendentes.
create or replace function public.sj_guard_viagens_conferencia()
returns trigger language plpgsql set search_path=public as $$
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
     if (new.id,new.user_id,new.motorista_id,new.veiculo_id,new.data_viagem,new.km_rodados,new.faturamento,new.observacoes,new.km_inicial,new.km_final,new.origem,new.destino)
       is distinct from
        (old.id,old.user_id,old.motorista_id,old.veiculo_id,old.data_viagem,old.km_rodados,old.faturamento,old.observacoes,old.km_inicial,old.km_final,old.origem,old.destino)
     then raise exception 'Revise os dados separadamente antes de aprovar'; end if;
     new.conferido_em:=now();
     new.conferido_por:=admin_id;
   else
     new.conferido_em:=old.conferido_em;
     new.conferido_por:=old.conferido_por;
   end if;
 end if;
 return new;
end $$;
drop trigger if exists sj_guard_viagens_conferencia_trigger on public.viagens;
create trigger sj_guard_viagens_conferencia_trigger before insert or update on public.viagens
for each row execute function public.sj_guard_viagens_conferencia();

alter table public.financeiro add column if not exists comprovante_id uuid;
alter table public.financeiro drop constraint if exists financeiro_comprovante_fk;
alter table public.financeiro add constraint financeiro_comprovante_fk foreign key(comprovante_id) references public.comprovantes_motoristas(id) on delete restrict;
create unique index if not exists financeiro_comprovante_unico on public.financeiro(comprovante_id) where comprovante_id is not null;

-- Não permitir alterar a referência do comprovante nem modificar lançamentos vinculados.
create or replace function public.sj_guard_financeiro_comprovante()
returns trigger language plpgsql set search_path=public as $$
begin
 if tg_op='UPDATE' and old.comprovante_id is not null then
   raise exception 'Recebimento vinculado a comprovante é imutável';
 end if;
 if tg_op='DELETE' and old.comprovante_id is not null then
   raise exception 'Recebimento vinculado a comprovante não pode ser excluído';
 end if;
 if tg_op='INSERT' and new.comprovante_id is not null and current_user <> 'postgres' then
   raise exception 'Use a operação de recebimento autorizada';
 end if;
 return coalesce(new,old);
end $$;
drop trigger if exists sj_guard_financeiro_comprovante_trigger on public.financeiro;
create trigger sj_guard_financeiro_comprovante_trigger before insert or update or delete on public.financeiro
for each row execute function public.sj_guard_financeiro_comprovante();
-- A operação RPC SECURITY DEFINER executa com o proprietário da função (postgres).
-- Não usa variável de sessão controlável pelo cliente.
create or replace function public.sj_registrar_recebimento_comprovante(p_comprovante_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare c public.comprovantes_motoristas%rowtype; novo_id uuid;
begin
 if auth.uid() is distinct from '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid then
   raise exception 'Apenas o administrador pode registrar recebimentos';
 end if;
 select * into c from public.comprovantes_motoristas
 where id=p_comprovante_id and user_id=auth.uid() and status='confirmado' for update;
 if not found then raise exception 'Comprovante inexistente, não confirmado ou sem permissão'; end if;
 if exists(select 1 from public.financeiro where comprovante_id=c.id) then
   raise exception 'Este comprovante já foi registrado no Financeiro';
 end if;
 insert into public.financeiro(user_id,data_lancamento,tipo,categoria,descricao,valor,motorista_id,comprovante_id)
 values(c.user_id,c.data_pagamento,'receita','Recebimento de motorista',
        'Comprovante confirmado '||c.id::text,c.valor,c.motorista_id,c.id)
 returning id into novo_id;
 return novo_id;
end $$;
revoke all on function public.sj_registrar_recebimento_comprovante(uuid) from public,anon;
grant execute on function public.sj_registrar_recebimento_comprovante(uuid) to authenticated;
commit;
