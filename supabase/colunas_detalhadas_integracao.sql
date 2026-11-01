-- SJ MOB TOP — colunas completas em linhas separadas
-- SOMENTE LEITURA. Retorna uma linha por tabela e coluna.
select table_name,ordinal_position,column_name,data_type,is_nullable,column_default
from information_schema.columns
where table_schema='public'
  and table_name in ('viagens','financeiro','comprovantes_motoristas')
order by table_name,ordinal_position;
