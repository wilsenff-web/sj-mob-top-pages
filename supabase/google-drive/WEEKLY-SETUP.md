# Agendamento semanal do SJ MOB TOP

**Status: preparado, NÃO ativado.** O backup manual foi confirmado pelo usuário no Drive em 01/11/2026.

## Pré-requisitos obrigatórios
1. No Google Cloud, o OAuth deve ter credenciais de longa duração adequadas. Com app External em modo **Testing** e escopo Drive, refresh tokens costumam expirar em 7 dias. Antes de ativar cron, publicar o consentimento em Production e cumprir as exigências de verificação aplicáveis. Depois, reconectar Google Drive no SJ MOB TOP e testar um novo backup manual.
2. Gerar segredo aleatório com no mínimo 32 bytes, guardar em **Supabase Edge Functions → Secrets** como `BACKUP_CRON_SECRET`. Não usar o segredo do cliente OAuth nem de criptografia.
3. Guardar o mesmo segredo em **Supabase Vault** com nome `sj_mob_top_backup_cron_secret`. Não colar o segredo em logs, repositório ou chat. Usar o editor do Vault; se indisponível, seguir instrução comentada no SQL.
4. Revisar e executar `weekly-cron.sql` no SQL Editor. Exige extensões `pg_cron`, `pg_net`, `vault` habilitadas.
5. Confirmar job ativo e executar um teste controlado; conferir o arquivo `SJ-MOB-TOP-weekly-...` no Google Drive. Checar logs da Edge Function e respostas `net._http_response` conforme retenção disponível.
6. Se falhar, desativar via `select cron.unschedule('sj-mob-top-drive-weekly');`.

## Horário
Domingos 03:00 Brasília (06:00 UTC, considerando UTC-3). Se a legislação alterar o horário local, atualizar expressão cron.

## Limitações
- Sem anexos Supabase Storage.
- Sem restauração automática, alerta de falha ou política de retenção.
- Backup deve ser testado periodicamente, inclusive restauração em ambiente separado.
- Não ativar cron com OAuth Testing.
