-- SJ MOB TOP: agendamento seguro, domingo 03:00 America/Sao_Paulo.
-- PRÉ-REQUISITOS: BACKUP_CRON_SECRET configurado na Edge Function e no Vault,
-- função google-drive-backup publicada e Google OAuth com refresh token durável.
-- NÃO execute antes de verificar os pré-requisitos.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create extension if not exists vault with schema vault;

-- 06:00 UTC equivale a 03:00 em Brasília (UTC-3, sem horário de verão atual).
-- Se o horário legal mudar, ajustar o cron.
-- Cadastre primeiro no Vault o segredo com name='sj_mob_top_backup_cron_secret':
-- select vault.create_secret('<SEGREDO_ALEATORIO_DE_32_BYTES_OU_MAIS>', 'sj_mob_top_backup_cron_secret');
-- Nunca cole o segredo em código, GitHub, capturas de tela ou mensagens.

select cron.schedule(
 'sj-mob-top-drive-weekly',
 '0 6 * * 0',
 $cron$
 select net.http_post(
   url := 'https://wdtavnvdkwrwsjbhoiai.supabase.co/functions/v1/google-drive-backup',
   headers := jsonb_build_object(
     'Content-Type', 'application/json',
     'x-backup-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'sj_mob_top_backup_cron_secret' limit 1)
   ),
   body := '{"action":"weekly"}'::jsonb,
   timeout_milliseconds := 120000
 );
 $cron$
);
-- Consultar: select jobid, jobname, schedule, active from cron.job where jobname='sj-mob-top-drive-weekly';
-- Desativar: select cron.unschedule('sj-mob-top-drive-weekly');
