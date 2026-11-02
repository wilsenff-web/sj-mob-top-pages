-- SJ MOB TOP — PRÉ-VALIDAÇÃO DE MIGRAÇÃO (SOMENTE LEITURA)
-- Execute no SQL Editor antes de aplicar seguranca_motoristas.sql.
-- Nenhuma alteração é realizada.
SELECT t.table_name, c.column_name, c.data_type, c.is_nullable
FROM information_schema.tables t
JOIN information_schema.columns c ON c.table_schema=t.table_schema AND c.table_name=t.table_name
WHERE t.table_schema='public' AND t.table_name IN ('motoristas','veiculos','viagens')
AND c.column_name IN ('id','user_id','auth_user_id','status','motorista_id','veiculo_id',
'origem','destino','km_inicial','km_final','km_rodados','faturamento')
ORDER BY t.table_name,c.column_name;

SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies WHERE schemaname='public'
ORDER BY tablename,policyname;

-- Confirme que o usuário administrador e o usuário de teste existem:
SELECT id,email FROM auth.users
WHERE email IN ('wilsenff@gmail.com','wilsenff2@gmail.com');

-- ALERTAS DE REVISÃO:
-- 1. A migração atual remove todas as políticas anteriores, inclusive as de pendencias.
-- 2. O proprietário da frota principal deve ser o UUID do administrador.
-- 3. As regras devem ser testadas em banco separado antes da produção.
-- 4. Testar operações em pendencias e pagamentos_pendencias, além de viagens.
-- 5. Verificar autenticação real e isolamento de motoristas, não apenas SQL Editor.
