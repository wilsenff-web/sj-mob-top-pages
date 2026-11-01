-- SJ MOB TOP — habilitação ADITIVA de motoristas (revisão do backup RLS 31/10/2026)
-- Preserva todas as 9 políticas atuais: NÃO remove acesso_proprio nem políticas de pendências.
-- Executar somente no projeto principal, após confirmar o esquema e os dados.
-- O administrador continua regido pelas políticas existentes (user_id = auth.uid()).
-- A autenticação de cada motorista deve ser criada no Supabase Auth e vinculada
-- a public.motoristas.auth_user_id, com user_id igual ao proprietário da frota.
BEGIN;

DO $$
DECLARE faltando text;
BEGIN
  SELECT string_agg(x.t || '.' || x.c, ', ')
    INTO faltando
  FROM (VALUES
    ('motoristas','id'),('motoristas','user_id'),('motoristas','auth_user_id'),
    ('motoristas','status'),('veiculos','id'),('veiculos','user_id'),
    ('veiculos','status'),('viagens','id'),('viagens','user_id'),
    ('viagens','motorista_id'),('viagens','veiculo_id'),
    ('viagens','origem'),('viagens','destino'),
    ('viagens','km_inicial'),('viagens','km_final'),
    ('viagens','km_rodados'),('viagens','faturamento')
  ) AS x(t,c)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema='public'
      AND c.table_name=x.t AND c.column_name=x.c
  );
  IF faltando IS NOT NULL THEN
    RAISE EXCEPTION 'Esquema incompleto: %', faltando;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
  ) THEN
    RAISE EXCEPTION 'Conta administrativa não encontrada; nenhuma alteração aplicada';
  END IF;
END $$;

ALTER TABLE public.motoristas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veiculos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.viagens ENABLE ROW LEVEL SECURITY;

-- Nomes exclusivos para não interferir nas políticas anteriores.
CREATE POLICY sj_motorista_ler_cadastro ON public.motoristas
  FOR SELECT TO authenticated
  USING (
    auth_user_id=(select auth.uid())
    AND user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
    AND status='ativo'
  );

CREATE POLICY sj_motorista_ler_veiculos ON public.veiculos
  FOR SELECT TO authenticated
  USING (
    user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
    AND status='ativo'
    AND EXISTS (
      SELECT 1 FROM public.motoristas m
      WHERE m.auth_user_id=(select auth.uid())
        AND m.user_id=veiculos.user_id
        AND m.status='ativo'
    )
  );

CREATE POLICY sj_motorista_ler_viagens ON public.viagens
  FOR SELECT TO authenticated
  USING (
    user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
    AND EXISTS (
      SELECT 1 FROM public.motoristas m
      WHERE m.id=viagens.motorista_id
        AND m.auth_user_id=(select auth.uid())
        AND m.user_id=viagens.user_id
        AND m.status='ativo'
    )
  );

CREATE POLICY sj_motorista_criar_viagem ON public.viagens
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
    AND EXISTS (
      SELECT 1 FROM public.motoristas m
      WHERE m.id=viagens.motorista_id
        AND m.auth_user_id=(select auth.uid())
        AND m.user_id=viagens.user_id
        AND m.status='ativo'
    )
    AND EXISTS (
      SELECT 1 FROM public.veiculos v
      WHERE v.id=viagens.veiculo_id
        AND v.user_id=viagens.user_id
        AND v.status='ativo'
    )
    AND km_inicial IS NOT NULL AND km_final IS NOT NULL
    AND km_inicial >= 0 AND km_final >= km_inicial
    AND km_rodados IS NOT NULL
    AND abs(km_rodados-(km_final-km_inicial)) < 0.001
    AND nullif(btrim(origem),'') IS NOT NULL
    AND nullif(btrim(destino),'') IS NOT NULL
    AND faturamento IS NOT NULL AND faturamento >= 0
  );

-- Somente as permissões SQL necessárias para as novas políticas.
-- Não amplia acesso ao financeiro, pendências ou outras tabelas.
GRANT SELECT ON public.motoristas, public.veiculos TO authenticated;
GRANT SELECT, INSERT ON public.viagens TO authenticated;

COMMIT;

-- Reversão APENAS desta migração (executar separadamente se necessário):
-- BEGIN;
-- DROP POLICY IF EXISTS sj_motorista_criar_viagem ON public.viagens;
-- DROP POLICY IF EXISTS sj_motorista_ler_viagens ON public.viagens;
-- DROP POLICY IF EXISTS sj_motorista_ler_veiculos ON public.veiculos;
-- DROP POLICY IF EXISTS sj_motorista_ler_cadastro ON public.motoristas;
-- COMMIT;
--
-- Atenção: GRANTs são cumulativos e não são revertidos acima, pois podem já
-- ser usados pelo administrador. Verificar privilégios preexistentes se necessário.
-- Se houver políticas adicionais não presentes no backup, revisar antes de aplicar.
