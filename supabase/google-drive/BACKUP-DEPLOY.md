# Implantação — Backup Google Drive do SJ MOB TOP

**Estado:** código preparado, NÃO implantado no Supabase. A conexão OAuth existente permanece.

## Cobertura e limitações
- Inclui nove tabelas: motoristas, veiculos, viagens, financeiro, pendencias, pagamentos_pendencias, manutencoes, metas, comprovantes_motoristas.
- NÃO inclui arquivos binários (fotos/PDF) de Supabase Storage; inclui apenas os metadados armazenados nas tabelas.
- NÃO é um mecanismo de restauração automática. Testar restauração em projeto isolado antes de depender do backup.
- Limite de segurança: 40 MiB por arquivo; para bases maiores, implementar exportação em partes.
- O Google Drive OAuth externo em modo Testando pode expirar em sete dias; não ativar cron enquanto isso não for resolvido.
- O serviço não implementa política de retenção, auditoria nem alerta automático.

## Implantar manualmente no Supabase
1. Edge Functions > Deploy a new function > Via Editor.
2. Nome da função: `google-drive-backup`.
3. Copiar o conteúdo de `backup.ts` para `index.ts` e publicar.
4. Em Settings da função, desligar `Verify JWT with legacy secret`. A função valida o JWT do administrador internamente, ou o cabeçalho secreto do agendamento.
5. Testar o botão `Salvar backup no Drive` no SJ MOB TOP e verificar se o arquivo foi realmente criado no Google Drive.
6. Confirmar que o backup contém todas as tabelas esperadas, sem dados truncados. Testar recuperação em ambiente separado.

## Agendamento semanal (NÃO ativado)
1. Gerar um valor secreto forte, aleatório e diferente de todas as outras chaves, com pelo menos 32 bytes.
2. Cadastrar esse valor como `BACKUP_CRON_SECRET` em Edge Functions > Secrets.
3. Configurar Supabase Cron / pg_cron + pg_net para enviar POST semanal para
   `https://wdtavnvdkwrwsjbhoiai.supabase.co/functions/v1/google-drive-backup`
   com corpo JSON `{"action":"weekly"}`, `Content-Type: application/json`, e cabeçalho `x-backup-cron-secret` com o valor protegido em Supabase Vault.
4. NÃO gravar segredo em SQL literal ou logs. Usar Vault para armazená-lo e buscar o segredo no momento da chamada.
5. Executar teste do agendamento e conferir o arquivo no Drive; só então considerar ativo.
6. Revisar status de publicação OAuth do Google antes de confiar em backups semanais.

## Segurança
- Nunca enviar `GOOGLE_CLIENT_SECRET`, `GOOGLE_TOKEN_ENCRYPTION_KEY`, `BACKUP_CRON_SECRET`, service_role ou refresh token ao navegador ou GitHub.
- A função de backup usa service_role apenas no servidor, com autenticação interna.
- Não alterar as tabelas existentes ou as políticas RLS da frota.
