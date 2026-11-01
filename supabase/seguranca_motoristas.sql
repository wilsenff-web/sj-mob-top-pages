-- SJ MOB TOP | Migração de segurança v1
-- REVISAR e fazer backup antes de executar. Executar UMA vez, após revisão do PR.
-- Administrador principal fixado por UUID, não por email editável.
BEGIN;
CREATE OR REPLACE FUNCTION public.is_sj_admin()
RETURNS boolean LANGUAGE sql STABLE SET search_path = ''
AS $$ SELECT (select auth.uid()) = '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid $$;
REVOKE ALL ON FUNCTION public.is_sj_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_sj_admin() TO authenticated;

-- Cada conta de motorista representa no máximo um cadastro.
CREATE UNIQUE INDEX IF NOT EXISTS motoristas_auth_user_id_unique_idx
ON public.motoristas(auth_user_id) WHERE auth_user_id IS NOT NULL;

-- Remover TODAS as políticas antigas para não manter permissões permissivas paralelas.
DO $$
DECLARE r record;
BEGIN
 FOR r IN SELECT schemaname,tablename,policyname FROM pg_policies
  WHERE schemaname='public' AND tablename IN
 ('financeiro','manutencoes','metas','motoristas','pagamentos_pendencias','pendencias','veiculos','viagens')
 LOOP
  EXECUTE format('DROP POLICY %I ON %I.%I',r.policyname,r.schemaname,r.tablename);
 END LOOP;
END $$;

-- Administrador só pode operar registros de sua própria frota.
DO $$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['financeiro','manutencoes','metas','motoristas',
 'pagamentos_pendencias','pendencias','veiculos','viagens']
 LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY admin_frota ON public.%I FOR ALL TO authenticated USING (public.is_sj_admin() AND user_id = (select auth.uid())) WITH CHECK (public.is_sj_admin() AND user_id = (select auth.uid()))',t);
 END LOOP;
END $$;

-- Motorista lê somente seu cadastro, sem poder alterá-lo.
CREATE POLICY motorista_proprio_select ON public.motoristas
 FOR SELECT TO authenticated
 USING (auth_user_id = (select auth.uid()) AND user_id = '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid AND status = 'ativo');

-- Motorista pode selecionar veículos ativos da frota principal, nunca editá-los.
CREATE POLICY motorista_veiculos_select ON public.veiculos
 FOR SELECT TO authenticated
 USING (user_id = '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 AND status = 'ativo'
 AND EXISTS (SELECT 1 FROM public.motoristas m WHERE m.auth_user_id = (select auth.uid())
 AND m.user_id = '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid AND m.status = 'ativo'));

-- Somente suas viagens; user_id da viagem permanece o UUID do dono da frota.
CREATE POLICY motorista_viagens_select ON public.viagens
 FOR SELECT TO authenticated
 USING (user_id = '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 AND EXISTS (SELECT 1 FROM public.motoristas m WHERE m.id = motorista_id
 AND m.auth_user_id = (select auth.uid()) AND m.user_id = viagens.user_id AND m.status = 'ativo'));

CREATE POLICY motorista_viagens_insert ON public.viagens
 FOR INSERT TO authenticated
 WITH CHECK (user_id = '92d8d744-f382-44ad-bcc3-f951765ffa73'::uuid
 AND EXISTS (SELECT 1 FROM public.motoristas m WHERE m.id = motorista_id
 AND m.auth_user_id = (select auth.uid()) AND m.user_id = viagens.user_id AND m.status = 'ativo')
 AND EXISTS (SELECT 1 FROM public.veiculos v WHERE v.id = veiculo_id
 AND v.user_id = viagens.user_id AND v.status = 'ativo')
 AND km_inicial IS NOT NULL AND km_final IS NOT NULL
 AND km_final >= km_inicial AND km_rodados = km_final - km_inicial
 AND NULLIF(btrim(origem),'') IS NOT NULL AND NULLIF(btrim(destino),'') IS NOT NULL
 AND faturamento >= 0);

-- Revogar permissões públicas; políticas RLS controlam as linhas autenticadas.
REVOKE ALL ON public.financeiro,public.manutencoes,public.metas,public.motoristas,
 public.pagamentos_pendencias,public.pendencias,public.veiculos,public.viagens FROM anon;
REVOKE TRUNCATE,TRIGGER,REFERENCES ON public.financeiro,public.manutencoes,public.metas,
 public.motoristas,public.pagamentos_pendencias,public.pendencias,public.veiculos,public.viagens FROM authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.financeiro,public.manutencoes,public.metas,
 public.motoristas,public.pagamentos_pendencias,public.pendencias,public.veiculos,public.viagens TO authenticated;
COMMIT;

-- Depois: criar contas em Authentication > Users, cadastrar motorista sob conta principal
-- e vincular motoristas.auth_user_id ao auth.users.id do motorista.
-- Testar com sessão autenticada real de administrador e motorista antes de liberar produção.
