# SJ MOB TOP — preparação da integração Google Drive

Esta etapa **não está implantada**. Não altera o site publicado.

## Já configurado pelo proprietário
- API Google Drive ativada no projeto Google Cloud.
- Cliente OAuth Web criado; callback planejado:
  `https://wdtavnvdkwrwsjbhoiai.supabase.co/functions/v1/google-drive-oauth/callback`
- `GOOGLE_CLIENT_ID` cadastrado em Edge Functions > Secrets.
- `GOOGLE_CLIENT_SECRET`: confirmar que aparece em Custom secrets.

## Implantação segura — próximas etapas
1. Executar `schema.sql` no SQL Editor do projeto Supabase correto, conferindo o resultado.
2. Preparar função `google-drive-oauth` com validação do JWT do administrador, state aleatório de uso único, callback Google e armazenamento cifrado do refresh token. Não publicar o código de exemplo do editor.
3. Armazenar em Edge Function Secrets uma chave AES-256 aleatória (32 bytes base64), ID do administrador e URI de callback, sem expor no chat ou GitHub.
4. Revisar e testar a função. O callback do Google não envia JWT; a função deve validar state e o POST deve validar o JWT do administrador.
5. Criar função de exportação com inventário dos dados, formato recuperável, logs, verificação e restauração testada.
6. Criar botão de backup manual no frontend, mantendo o fluxo atual funcionando.
7. Implementar cron semanal server-side, testar execução sem navegador e alertas de falha.

**Atenção**: em OAuth externo no modo 'Testando', refresh tokens para escopos de Drive podem expirar em 7 dias. Não ativar backup semanal até resolver a validade e o consentimento. Revogar a chave OAuth antiga que foi exposta após validar a nova.

**Segurança**: não usar service_role no navegador, não publicar tokens, não conceder acesso RLS a usuários comuns às tabelas de tokens.

## Função pronta no repositório
`supabase/google-drive/index.ts` — inicia OAuth e armazena refresh token cifrado. **Não exporta backup ainda.**

### Secrets adicionais obrigatórios
- `SJ_ADMIN_UID`: UUID do único administrador autorizado.
- `GOOGLE_OAUTH_REDIRECT_URI`: `https://wdtavnvdkwrwsjbhoiai.supabase.co/functions/v1/google-drive-oauth/callback`
- `GOOGLE_TOKEN_ENCRYPTION_KEY`: chave criptográfica aleatória de 32 bytes codificada em base64; guardar fora do GitHub. Uma forma de gerar localmente é `openssl rand -base64 32`.

### Como implantar
1. No Supabase SQL Editor, executar `schema.sql`.
2. Em Edge Functions > Secrets, confirmar os dois secrets Google e adicionar os três acima.
3. Em Edge Functions > Via Editor, nomear `google-drive-oauth`, substituir o código de exemplo por `index.ts`.
4. Desativar **Verify JWT** apenas para esta função, pois callback GET não carrega JWT; a função verifica manualmente JWT em POST e state em GET.
5. Implantar e verificar logs.
6. O frontend ainda precisa do botão de conexão, que deve usar o access token de sessão para POST `{ "action": "start" }`; abrir `authorization_url` retornada. Para status, POST `{ "action": "status" }`.
7. Nunca usar `GOOGLE_CLIENT_SECRET` ou service_role no frontend.

### Limitações
- OAuth externo em teste pode ter refresh token com expiração de 7 dias para escopo Drive.
- A função não cria backups nem agenda execuções; isso requer backend de exportação, armazenamento e cron com teste de restauração.
