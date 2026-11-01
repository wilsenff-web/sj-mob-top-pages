-- Executar no SQL Editor do projeto SJ MOB TOP antes do deploy.
create table if not exists public.sj_google_oauth_states (
  state_hash text primary key,
  admin_uid uuid not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create table if not exists public.sj_google_drive_tokens (
  admin_uid uuid primary key,
  refresh_token_encrypted text not null,
  google_email text,
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.sj_google_oauth_states enable row level security;
alter table public.sj_google_drive_tokens enable row level security;
-- Nenhuma política de leitura/escrita para anon ou authenticated:
-- apenas o backend autenticado com service_role pode acessar.
revoke all on public.sj_google_oauth_states from anon, authenticated;
revoke all on public.sj_google_drive_tokens from anon, authenticated;
create index if not exists sj_google_oauth_states_expiry_idx on public.sj_google_oauth_states(expires_at);
