-- SJ MOB TOP: conferir colunas e restrições antes da migração
-- SOMENTE LEITURA. Não modifica dados.
select table_name,column_name,data_type,is_nullable,column_default
from information_schema.columns
where table_schema='public'
  and table_name in ('viagens','financeiro','comprovantes_motoristas')
order by table_name,ordinal_position;

select tc.table_name,tc.constraint_name,tc.constraint_type,
       string_agg(kcu.column_name,', ' order by kcu.ordinal_position) as colunas
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on kcu.constraint_name=tc.constraint_name
 and kcu.table_schema=tc.table_schema
 and kcu.table_name=tc.table_name
where tc.table_schema='public'
  and tc.table_name in ('viagens','financeiro','comprovantes_motoristas')
group by tc.table_name,tc.constraint_name,tc.constraint_type
order by tc.table_name,tc.constraint_type;
