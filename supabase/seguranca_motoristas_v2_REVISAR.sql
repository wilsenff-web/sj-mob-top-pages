-- SJ MOB TOP — MIGRACAO RLS v2 (CANDIDATA; NAO EXECUTAR EM PRODUCAO SEM BACKUP E TESTE)
-- Substitui v1. Aplicar em CLONE/AMBIENTE DE TESTE primeiro.
-- Exige cadastro de motorista com user_id do administrador e auth_user_id da conta do motorista.
BEGIN;
DO $$
DECLARE t text; missing text;
BEGIN
 -- Bloquear execução caso o esquema seja diferente do esperado.
 SELECT string_agg(x.t||'.'||x.c, ', ') INTO missing
 FROM (VALUES
 ('motoristas','id'),('motoristas','user_id'),('motoristas','auth_user_id'),('motoristas','status'),
 ('veiculos','id'),('veiculos','user_id'),('veiculos','status'),
 ('viagens','id'),('viagens','user_id'),('viagens','motorista_id'),('viagens','veiculo_id'),
 ('viagens','origem'),('viagens','destino'),('viagens','km_inicial'),('viagens','km_final'),
 ('viagens','km_rodados'),('viagens','faturamento')
 ) x(t,c)
 WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns z
 WHERE z.table_schema='public' AND z.table_name=x.t AND z.column_name=x.c);
 IF missing IS NOT NULL THEN RAISE EXCEPTION 'Colunas ausentes: %',missing; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid)
 THEN RAISE EXCEPTION 'Conta administrativa não encontrada'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.is_sj_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT (select auth.uid())='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid $$;
REVOKE ALL ON FUNCTION public.is_sj_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_sj_admin() TO authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS motoristas_auth_user_id_unique_idx
 ON public.motoristas(auth_user_id) WHERE auth_user_id IS NOT NULL;

-- Registrar as politicas anteriores fora desta transacao (backup) ANTES de executar.
-- Substituição intencional: políticas permissivas antigas não podem permanecer.
DO $$
DECLARE p record; t text;
BEGIN
 FOR p IN SELECT schemaname,tablename,policyname FROM pg_policies
 WHERE schemaname='public' AND tablename IN
 ('financeiro','manutencoes','metas','motoristas','pagamentos_pendencias','pendencias','veiculos','viagens')
 LOOP
 EXECUTE format('DROP POLICY %I ON %I.%I',p.policyname,p.schemaname,p.tablename);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['financeiro','manutencoes','metas','motoristas',
 'pagamentos_pendencias','pendencias','veiculos','viagens']
 LOOP
 EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY admin_frota ON public.%I FOR ALL TO authenticated USING (public.is_sj_admin() AND user_id = (select auth.uid())) WITH CHECK (public.is_sj_admin() AND user_id = (select auth.uid()))',t);
 END LOOP;
END $$;

CREATE POLICY motorista_proprio_select ON public.motoristas
 FOR SELECT TO authenticated
 USING (auth_user_id=(select auth.uid()) AND user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid AND status='ativo');

CREATE POLICY motorista_veiculos_select ON public.veiculos
 FOR SELECT TO authenticated
 USING (user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 AND status='ativo' AND EXISTS
 (SELECT 1 FROM public.motoristas m WHERE m.auth_user_id=(select auth.uid())
 AND m.user_id=veiculos.user_id AND m.status='ativo'));

CREATE POLICY motorista_viagens_select ON public.viagens
 FOR SELECT TO authenticated
 USING (user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 AND EXISTS (SELECT 1 FROM public.motoristas m WHERE m.id=viagens.motorista_id
 AND m.auth_user_id=(select auth.uid()) AND m.user_id=viagens.user_id AND m.status='ativo'));

CREATE POLICY motorista_viagens_insert ON public.viagens
 FOR INSERT TO authenticated
 WITH CHECK (
 user_id='92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 AND EXISTS (SELECT 1 FROM public.motoristas m WHERE m.id=viagens.motorista_id
 AND m.auth_user_id=(select auth.uid()) AND m.user_id=viagens.user_id AND m.status='ativo')
 AND EXISTS (SELECT 1 FROM public.veiculos v WHERE v.id=viagens.veiculo_id
 AND v.user_id=viagens.user_id AND v.status='ativo')
 AND km_inicial IS NOT NULL AND km_final IS NOT NULL
 AND km_inicial>=0 AND km_final>=km_inicial
 AND km_rodados IS NOT NULL
 AND abs(km_rodados-(km_final-km_inicial))<0.001
 AND nullif(btrim(origem),'') IS NOT NULL
 AND nullif(btrim(destino),'') IS NOT NULL
 AND faturamento IS NOT NULL AND faturamento>=0
 );

REVOKE ALL ON public.financeiro,public.manutencoes,public.metas,public.motoristas,
 public.pagamentos_pendencias,public.pendencias,public.veiculos,public.viagens FROM anon;
REVOKE TRUNCATE,REFERENCES,TRIGGER ON public.financeiro,public.manutencoes,public.metas,
 public.motoristas,public.pagamentos_pendencias,public.pendencias,public.veiculos,public.viagens FROM authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.financeiro,public.manutencoes,public.metas,
 public.motoristas,public.pagamentos_pendencias,public.pendencias,public.veiculos,public.viagens TO authenticated;
COMMIT;

-- IMPORTANTE: testar fluxos de pendencias, pagamentos_pendencias, financeiro,
-- veiculos, motoristas e viagens no clone. Admin é restrito a registros da frota principal.
-- Motorista não possui UPDATE/DELETE em viagens.
-- Criar contas em Auth, vincular auth_user_id no cadastro pertencente à frota principal.
