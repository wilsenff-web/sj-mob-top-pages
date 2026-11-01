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
