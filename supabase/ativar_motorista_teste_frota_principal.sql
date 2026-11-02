-- SJ MOB TOP — ativação segura do Motorista Teste na frota PRINCIPAL
-- NÃO importa dados da conta antiga, não altera RLS, não apaga registros.
-- Rodar no SQL Editor do Supabase apenas após conferir projeto e e-mail.
BEGIN;
DO $$
DECLARE
  admin_uid constant uuid := '92d8d744-f382-44ad-bcc3-f951765ffa73';
  driver_uid constant uuid := '916bf85f-2f73-408d-af25-296bb8c0be7c';
  existing_id uuid;
  n integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id=driver_uid AND lower(email)='wilsenff01@gmail.com'
  ) THEN
    RAISE EXCEPTION 'Conta Auth do motorista não corresponde ao Gmail esperado';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=admin_uid) THEN
    RAISE EXCEPTION 'Conta administrativa não encontrada';
  END IF;
  -- Não sequestrar cadastro de outra frota.
  IF EXISTS (
    SELECT 1 FROM public.motoristas
    WHERE auth_user_id=driver_uid AND user_id<>admin_uid
  ) THEN
    RAISE EXCEPTION 'Login do motorista está vinculado a outra frota';
  END IF;

  -- Se o login já está vinculado corretamente, apenas ativar o cadastro.
  SELECT count(*) INTO n FROM public.motoristas
    WHERE user_id=admin_uid AND auth_user_id=driver_uid;
  IF n>1 THEN RAISE EXCEPTION 'Mais de um cadastro associado ao mesmo login'; END IF;
  IF n=1 THEN
    UPDATE public.motoristas SET status='ativo'
    WHERE user_id=admin_uid AND auth_user_id=driver_uid;
  ELSE
    -- Aproveitar um cadastro de teste da frota principal, mas jamais de outra frota.
    SELECT count(*) INTO n FROM public.motoristas
    WHERE user_id=admin_uid AND lower(btrim(nome))='motorista teste';
    IF n>1 THEN RAISE EXCEPTION 'Mais de um Motorista Teste na frota principal'; END IF;
    IF n=1 THEN
      SELECT id INTO existing_id FROM public.motoristas
      WHERE user_id=admin_uid AND lower(btrim(nome))='motorista teste';
      UPDATE public.motoristas
      SET auth_user_id=driver_uid,status='ativo'
      WHERE id=existing_id AND user_id=admin_uid AND auth_user_id IS NULL;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cadastro Motorista Teste já vinculado a outro login';
      END IF;
    ELSE
      INSERT INTO public.motoristas (user_id,nome,status,auth_user_id)
      VALUES (admin_uid,'Motorista Teste','ativo',driver_uid);
    END IF;
  END IF;
END $$;
COMMIT;

-- Verificação opcional (somente leitura):
-- SELECT id,nome,status,user_id,auth_user_id FROM public.motoristas
-- WHERE auth_user_id='916bf85f-2f73-408d-af25-296bb8c0be7c'::uuid;
