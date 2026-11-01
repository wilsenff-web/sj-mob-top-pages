-- SJ MOB TOP | MIGRACAO DE PROPRIEDADE v1 — REVISAR ANTES DE EXECUTAR
-- Nao altera Auth, nao apaga dados, nao modifica RLS.
-- Base: 27 registros da conta antiga + 1 motorista ja na conta principal.
-- A migracao e atomica: falha em qualquer verificacao => ROLLBACK automatico.
-- Requer permissao de administrador do banco (SQL Editor).
-- ATENCAO: somente usar se os 27 registros realmente devam pertencer a frota principal.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '90s';

-- Bloqueia alteracoes concorrentes durante a migracao.
LOCK TABLE public.motoristas, public.veiculos, public.viagens,
  public.financeiro, public.manutencoes, public.metas,
  public.pendencias, public.pagamentos_pendencias IN ACCESS EXCLUSIVE MODE;

DO $$
DECLARE
  old_uid constant uuid := '6e33d6cb-f4a5-45da-a068-a95ef18cc5bf';
  new_uid constant uuid := '92d8d744-f382-44ad-bcc3-f951765ffa73';
  t text;
  n bigint;
  expected_n bigint;
  x record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=new_uid) THEN
    RAISE EXCEPTION 'Administrador principal nao encontrado';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=old_uid) THEN
    RAISE EXCEPTION 'Conta antiga nao encontrada';
  END IF;

  -- Protege contra reexecucao, alteracao inesperada dos dados e migracao parcial.
  FOR x IN
    SELECT * FROM (VALUES
      ('motoristas',3),('veiculos',3),('viagens',7),
      ('financeiro',3),('manutencoes',3),('metas',3),
      ('pendencias',3),('pagamentos_pendencias',2)
    ) AS e(tab, qtd)
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE user_id=$1',x.tab)
      INTO n USING old_uid;
    IF n <> x.qtd THEN
      RAISE EXCEPTION 'Contagem divergente em %: esperado %, encontrado %. Nenhuma mudanca aplicada.',
        x.tab,x.qtd,n;
    END IF;
  END LOOP;

  -- Falha se houver FKs em outras tabelas que apontem para tabelas migradas:
  -- nesse caso a migracao precisa incluir essas tabelas antes de prosseguir.
  IF EXISTS (
    SELECT 1 FROM pg_constraint c
    WHERE c.contype='f'
      AND c.confrelid IN (
        'public.motoristas'::regclass,'public.veiculos'::regclass,
        'public.viagens'::regclass,'public.financeiro'::regclass,
        'public.manutencoes'::regclass,'public.metas'::regclass,
        'public.pendencias'::regclass,'public.pagamentos_pendencias'::regclass
      )
      AND c.conrelid NOT IN (
        'public.motoristas'::regclass,'public.veiculos'::regclass,
        'public.viagens'::regclass,'public.financeiro'::regclass,
        'public.manutencoes'::regclass,'public.metas'::regclass,
        'public.pendencias'::regclass,'public.pagamentos_pendencias'::regclass
      )
  ) THEN
    RAISE EXCEPTION 'Existem tabelas adicionais com FKs para a frota; revisar dependencias';
  END IF;

  -- Chaves estrangeiras compostas precisam ser adiadas durante a troca do user_id.
  -- Guardamos a configuracao original em tabela temporaria para restaura-la.
  CREATE TEMP TABLE sj_fk_original ON COMMIT DROP AS
    SELECT c.conrelid, c.conname, c.condeferrable, c.condeferred
    FROM pg_constraint c
    WHERE c.contype='f' AND c.conrelid IN (
      'public.motoristas'::regclass,'public.veiculos'::regclass,
      'public.viagens'::regclass,'public.financeiro'::regclass,
      'public.manutencoes'::regclass,'public.metas'::regclass,
      'public.pendencias'::regclass,'public.pagamentos_pendencias'::regclass
    );

  FOR x IN SELECT * FROM sj_fk_original LOOP
    EXECUTE format('ALTER TABLE %s ALTER CONSTRAINT %I DEFERRABLE INITIALLY DEFERRED',
      x.conrelid::regclass, x.conname);
  END LOOP;
  SET CONSTRAINTS ALL DEFERRED;

  -- Preserva os IDs; as referencias por id e por (id,user_id) continuam validas ao final.
  FOREACH t IN ARRAY ARRAY[
    'motoristas','veiculos','viagens','financeiro',
    'manutencoes','metas','pendencias','pagamentos_pendencias'
  ] LOOP
    EXECUTE format('UPDATE public.%I SET user_id=$1 WHERE user_id=$2',t)
      USING new_uid,old_uid;
  END LOOP;

  -- Verifica que nao restou nenhum registro antigo nessas oito tabelas.
  FOREACH t IN ARRAY ARRAY[
    'motoristas','veiculos','viagens','financeiro',
    'manutencoes','metas','pendencias','pagamentos_pendencias'
  ] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE user_id=$1',t)
      INTO n USING old_uid;
    IF n <> 0 THEN
      RAISE EXCEPTION 'Migracao incompleta na tabela %',t;
    END IF;
  END LOOP;

  -- Valida FKs antes de restaurar o modo original.
  SET CONSTRAINTS ALL IMMEDIATE;
  FOR x IN SELECT * FROM sj_fk_original LOOP
    EXECUTE format('ALTER TABLE %s ALTER CONSTRAINT %I %s %s',
      x.conrelid::regclass, x.conname,
      CASE WHEN x.condeferrable THEN 'DEFERRABLE' ELSE 'NOT DEFERRABLE' END,
      CASE WHEN x.condeferrable AND x.condeferred THEN 'INITIALLY DEFERRED' ELSE 'INITIALLY IMMEDIATE' END);
  END LOOP;
END $$;

COMMIT;

-- Verificacao APOS a migracao:
-- SELECT 'motoristas' tabela,user_id,count(*) FROM public.motoristas GROUP BY user_id
-- UNION ALL SELECT 'veiculos',user_id,count(*) FROM public.veiculos GROUP BY user_id
-- UNION ALL SELECT 'viagens',user_id,count(*) FROM public.viagens GROUP BY user_id;
--
-- ATENCAO: nao executar sem revisao das FKs e constraints reais.
-- A conta antiga pode ter dados ficticios; a transferencia deve ser intencional.
