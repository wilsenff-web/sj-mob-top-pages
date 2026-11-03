alter table public.comprovantes_motoristas add column baixado boolean not null default false;
-- Identifica somente comprovantes que já têm recebimento efetivamente registrado.
update public.comprovantes_motoristas c set baixado=true where exists(select 1 from public.financeiro f where f.comprovante_id=c.id) or exists(select 1 from public.sj_recebimentos_viagens r where r.comprovante_id=c.id);
drop index public.sj_comprovante_ativo_por_viagem;
create unique index sj_comprovante_ativo_por_viagem on public.comprovantes_motoristas(viagem_id) where viagem_id is not null and status<>'rejeitado' and not baixado;
create function public.sj_guard_baixado_comprovante() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if tg_op='INSERT' then new.baixado:=false;
 elsif new.baixado is distinct from old.baixado then
  if not new.baixado or not coalesce(public.is_sj_admin(),false) or not (exists(select 1 from public.sj_recebimentos_viagens r where r.comprovante_id=old.id and r.user_id=auth.uid()) or exists(select 1 from public.financeiro f where f.comprovante_id=old.id and f.user_id=auth.uid()))then raise exception 'A baixa do comprovante exige um recebimento registrado';end if;
 end if;return new;end$$;
create trigger sj_guard_baixado_comprovante before insert or update on public.comprovantes_motoristas for each row execute function public.sj_guard_baixado_comprovante();
create function public.sj_marcar_comprovante_recebido() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if new.comprovante_id is not null then update public.comprovantes_motoristas set baixado=true where id=new.comprovante_id and user_id=new.user_id;end if;return new;end$$;
create trigger sj_marcar_comprovante_recebido after insert on public.sj_recebimentos_viagens for each row execute function public.sj_marcar_comprovante_recebido();
create trigger sj_marcar_comprovante_financeiro after insert on public.financeiro for each row execute function public.sj_marcar_comprovante_recebido();
notify pgrst,'reload schema';
