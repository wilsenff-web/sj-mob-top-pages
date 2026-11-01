-- SJ MOB TOP: armazenamento privado de estado OAuth e token cifrado
create table if not exists public.sj_google_oauth_states (
 state_hash text primary key,
 admin_uid uuid not null,
 expires_at timestamptz not null,
 created_at timestamptz not null default now()
);
create table if not exists public.sj_google_drive_tokens (
 admin_uid uuid primary key,
 refresh_token_encrypted text not null,
 updated_at timestamptz not null default now()
);
alter table public.sj_google_oauth_states enable row level security;
alter table public.sj_google_drive_tokens enable row level security;
revoke all on public.sj_google_oauth_states from anon, authenticated;
revoke all on public.sj_google_drive_tokens from anon, authenticated;
