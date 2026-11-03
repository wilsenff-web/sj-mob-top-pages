create function public.sj_editar_pendencia(p_id uuid,p_motorista_id uuid,p_veiculo_id uuid,p_categoria text,p_descricao text,p_valor numeric,p_data_lancamento date,p_vencimento date,p_original jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare r public.pendencias; atual jsonb;
begin
 if not coalesce(public.is_sj_admin(),false) then raise exception 'Somente o administrador pode editar pendências';end if;
 select * into r from public.pendencias where id=p_id and user_id=auth.uid() for update;
 if not found then raise exception 'Pendência não encontrada';end if;
 if r.viagem_uso_id is not null or r.meta_semanal_id is not null or r.referencia_cobranca is not null then raise exception 'Corrija a viagem, meta ou cobrança de origem deste registro automático';end if;
 atual:=jsonb_build_object('motorista_id',r.motorista_id,'veiculo_id',r.veiculo_id,'categoria',r.categoria,'descricao',r.descricao,'valor',r.valor,'data_lancamento',r.data_lancamento,'vencimento',r.vencimento);
 if p_original is distinct from atual then raise exception 'A pendência foi alterada em outra sessão. Atualize a tela';end if;
 if not exists(select 1 from public.motoristas m where m.id=p_motorista_id and m.user_id=auth.uid())then raise exception 'Motorista inválido';end if;
 if p_veiculo_id is not null and not exists(select 1 from public.veiculos v where v.id=p_veiculo_id and v.user_id=auth.uid())then raise exception 'Veículo inválido';end if;
 if nullif(btrim(p_categoria),'') is null or length(p_categoria)>100 or length(coalesce(p_descricao,''))>1000 then raise exception 'Categoria ou descrição inválida';end if;
 if p_valor is null or p_valor<=0 or p_valor::text in ('NaN','Infinity','-Infinity') or p_valor<>round(p_valor,2) or p_data_lancamento is null then raise exception 'Informe data e valor válidos';end if;
 update public.pendencias set motorista_id=p_motorista_id,veiculo_id=p_veiculo_id,categoria=btrim(p_categoria),descricao=coalesce(p_descricao,''),valor=p_valor,data_lancamento=p_data_lancamento,vencimento=p_vencimento where id=p_id;
 return p_id;
end$$;
revoke all on function public.sj_editar_pendencia(uuid,uuid,uuid,text,text,numeric,date,date,jsonb) from public,anon;
grant execute on function public.sj_editar_pendencia(uuid,uuid,uuid,text,text,numeric,date,date,jsonb) to authenticated;
notify pgrst,'reload schema';
