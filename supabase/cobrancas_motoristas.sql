alter table public.motoristas
 add column modalidade_cobranca text,
 add column valor_diaria numeric(12,2),
 add column percentual_comissao numeric(7,4),
 add column acordo_cobranca text,
 add constraint sj_modalidade_cobranca_check check (modalidade_cobranca is null or modalidade_cobranca in ('diaria','comissao','a_combinar')),
 add constraint sj_valor_diaria_check check (valor_diaria is null or (valor_diaria>0 and valor_diaria::text not in ('NaN','Infinity','-Infinity'))),
 add constraint sj_percentual_comissao_check check (percentual_comissao is null or (percentual_comissao>0 and percentual_comissao<=100)),
 add constraint sj_config_cobranca_check check (
  modalidade_cobranca is null or
  (modalidade_cobranca='diaria' and valor_diaria is not null) or
  (modalidade_cobranca='comissao' and percentual_comissao is not null) or
  modalidade_cobranca='a_combinar');
alter table public.pendencias
 add column cobranca_detalhes jsonb,
 add column referencia_cobranca uuid unique,
 add constraint sj_cobranca_detalhes_object check (cobranca_detalhes is null or jsonb_typeof(cobranca_detalhes)='object');
alter table public.pendencias drop constraint pendencias_categoria_check;
alter table public.pendencias add constraint pendencias_categoria_check check (categoria in ('Diária atrasada','Pedágio','Multa de trânsito','Abastecimento','Adiantamento de dinheiro','Empréstimo','Mau uso do veículo','Outras dívidas','Diária','Comissão','A combinar'));
create or replace function public.sj_lancar_cobranca_motorista(
 p_motorista_id uuid,p_modalidade text,p_data date,p_referencia uuid,
 p_vencimento date default null,p_veiculo_id uuid default null,
 p_quantidade numeric default null,p_valor_unitario numeric default null,
 p_base_comissao numeric default null,p_percentual numeric default null,
 p_valor_combinado numeric default null,p_descricao text default '')
returns uuid language plpgsql security invoker set search_path='' as $$
declare m public.motoristas%rowtype; total numeric; detalhes jsonb; categoria text; resumo text; novo_id uuid;
begin
 if not coalesce(public.is_sj_admin(),false) then raise exception 'Somente o administrador pode lançar cobranças'; end if;
 select * into m from public.motoristas where id=p_motorista_id and user_id=auth.uid() and status='ativo';
 if not found then raise exception 'Motorista ativo não encontrado'; end if;
 if p_data is null or p_referencia is null then raise exception 'Data e referência obrigatórias'; end if;
 if p_veiculo_id is not null and not exists(select 1 from public.veiculos where id=p_veiculo_id and user_id=auth.uid()) then raise exception 'Veículo sem permissão'; end if;
 if p_modalidade='diaria' then
  if p_quantidade is null or p_quantidade<=0 or p_quantidade>36600 or p_quantidade<>trunc(p_quantidade) or p_valor_unitario is null or p_valor_unitario<=0 then raise exception 'Informe dias inteiros positivos e o valor da diária'; end if;
  total:=round(p_quantidade*round(p_valor_unitario,2),2); categoria:='Diária';
  detalhes:=jsonb_build_object('modalidade',p_modalidade,'quantidade_dias',p_quantidade,'valor_diaria',round(p_valor_unitario,2));
  resumo:='Diária: '||p_quantidade::text||' dia(s) x R$ '||round(p_valor_unitario,2)::text;
 elsif p_modalidade='comissao' then
  if p_base_comissao is null or p_base_comissao<=0 or p_percentual is null or p_percentual<=0 or p_percentual>100 then raise exception 'Informe a base e o percentual entre 0 e 100'; end if;
  total:=round(round(p_base_comissao,2)*p_percentual/100,2); categoria:='Comissão';
  detalhes:=jsonb_build_object('modalidade',p_modalidade,'base_comissao',round(p_base_comissao,2),'percentual',p_percentual);
  resumo:='Comissão: base R$ '||round(p_base_comissao,2)::text||' x '||p_percentual::text||'%';
 elsif p_modalidade='a_combinar' then
  if nullif(btrim(p_descricao),'') is null or p_valor_combinado is null then raise exception 'Informe valor e descrição do acordo'; end if;
  total:=round(p_valor_combinado,2);categoria:='A combinar';
  detalhes:=jsonb_build_object('modalidade',p_modalidade,'valor_combinado',total);
  resumo:='A combinar';
 else raise exception 'Modalidade inválida'; end if;
 if total is null or total<=0 or total>9999999999.99 or total::text in ('NaN','Infinity','-Infinity') then raise exception 'Valor total inválido'; end if;
 insert into public.pendencias(user_id,motorista_id,veiculo_id,categoria,descricao,data_lancamento,vencimento,valor,cobranca_detalhes,referencia_cobranca)
 values(auth.uid(),m.id,p_veiculo_id,categoria,resumo||case when nullif(btrim(p_descricao),'') is not null then ' — '||btrim(p_descricao) else '' end,p_data,p_vencimento,total,detalhes,p_referencia)
 returning id into novo_id;
 return novo_id;
end $$;
revoke execute on function public.sj_lancar_cobranca_motorista(uuid,text,date,uuid,date,uuid,numeric,numeric,numeric,numeric,numeric,text) from public,anon;
grant execute on function public.sj_lancar_cobranca_motorista(uuid,text,date,uuid,date,uuid,numeric,numeric,numeric,numeric,numeric,text) to authenticated;
