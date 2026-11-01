-- SJ MOB TOP — diagnóstico prévio para aprovação administrativa de viagens
-- SOMENTE LEITURA. Não altera dados nem permissões.
select table_name,column_name,data_type,is_nullable,column_default
from information_schema.columns
where table_schema='public' and table_name='viagens'
order by ordinal_position;

select tc.constraint_name,tc.constraint_type,
       string_agg(kcu.column_name,', ' order by kcu.ordinal_position) as colunas
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on kcu.constraint_name=tc.constraint_name
 and kcu.table_schema=tc.table_schema
 and kcu.table_name=tc.table_name
where tc.table_schema='public' and tc.table_name='viagens'
group by tc.constraint_name,tc.constraint_type
order by tc.constraint_type;

select policyname,cmd,roles,qual,with_check
from pg_policies
where schemaname='public' and tablename='viagens'
order by policyname;
