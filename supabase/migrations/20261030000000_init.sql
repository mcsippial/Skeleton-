-- Skeleton initial schema (CLAUDE.md §9).
-- Row Level Security is enabled on every table: users only ever read/write their own rows.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  display_name   text,
  dob            date,
  sex            text check (sex in ('female', 'male', 'unspecified')),
  height_cm      numeric(5, 1) check (height_cm between 50 and 260),
  weight_kg      numeric(5, 1) check (weight_kg between 20 and 400),
  activity_level text check (activity_level in ('sedentary', 'light', 'moderate', 'active', 'athlete')),
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- body_models
-- ---------------------------------------------------------------------------
create table public.body_models (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  source        text not null check (source in ('stock', 'in3d', 'meshy', 'bodygram')),
  storage_path  text,
  rig_type      text not null default 'humanoid_mixamo',
  atlas_version text not null,
  is_current    boolean not null default false,
  created_at    timestamptz not null default now()
);
create unique index body_models_one_current on public.body_models (user_id) where is_current;
create index body_models_user on public.body_models (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- pain_entries
-- ---------------------------------------------------------------------------
create table public.pain_entries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  region_ids    text[] not null check (cardinality(region_ids) > 0),
  surface_point jsonb,
  pain_type     text not null check (pain_type in ('sharp', 'dull', 'aching', 'burning', 'throbbing', 'stabbing',
                  'shooting', 'tingling', 'numbness', 'cramping', 'stiffness', 'tenderness')),
  intensity     smallint not null check (intensity between 0 and 10),
  onset_at      timestamptz not null,
  pattern       text check (pattern in ('constant', 'intermittent')),
  triggers      text[] not null default '{}',
  relievers     text[] not null default '{}',
  notes         text,
  input_method  text not null check (input_method in ('tap', 'voice', 'text')),
  raw_text      text,
  created_at    timestamptz not null default now()
);
create index pain_entries_user_onset on public.pain_entries (user_id, onset_at desc);

-- ---------------------------------------------------------------------------
-- episodes
-- ---------------------------------------------------------------------------
create table public.episodes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  title       text not null,
  entry_ids   uuid[] not null default '{}',
  started_at  timestamptz not null,
  ended_at    timestamptz,
  status      text not null default 'active' check (status in ('active', 'resolved')),
  created_at  timestamptz not null default now()
);
create index episodes_user on public.episodes (user_id, started_at desc);

-- ---------------------------------------------------------------------------
-- insights
-- ---------------------------------------------------------------------------
create table public.insights (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  episode_id    uuid references public.episodes (id) on delete cascade,
  rules_output  jsonb not null,
  ai_output     jsonb,
  red_flags     text[] not null default '{}',
  model_version text,
  created_at    timestamptz not null default now()
);
create index insights_user on public.insights (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- health_metrics
-- ---------------------------------------------------------------------------
create table public.health_metrics (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  source      text not null,
  metric      text not null,
  value       double precision not null,
  unit        text not null,
  recorded_at timestamptz not null
);
create index health_metrics_user_metric on public.health_metrics (user_id, metric, recorded_at desc);

-- ---------------------------------------------------------------------------
-- integrations
-- ---------------------------------------------------------------------------
create table public.integrations (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  provider         text not null,
  status           text not null default 'pending' check (status in ('pending', 'connected', 'error', 'disconnected')),
  external_user_id text,
  connected_at     timestamptz,
  unique (user_id, provider)
);

-- ---------------------------------------------------------------------------
-- Row Level Security: owner-only access on every table.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'body_models', 'pain_entries', 'episodes', 'insights', 'health_metrics', 'integrations']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format($p$create policy "%1$s_select_own" on public.%1$I for select to authenticated using ((select auth.uid()) = user_id)$p$, t);
    execute format($p$create policy "%1$s_insert_own" on public.%1$I for insert to authenticated with check ((select auth.uid()) = user_id)$p$, t);
    execute format($p$create policy "%1$s_update_own" on public.%1$I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)$p$, t);
    execute format($p$create policy "%1$s_delete_own" on public.%1$I for delete to authenticated using ((select auth.uid()) = user_id)$p$, t);
  end loop;
end
$$;

-- Insights are written by the cause-engine Edge Function (service role), never edited by clients,
-- so the AI output and red flags a user saw cannot be altered afterwards.
drop policy "insights_insert_own" on public.insights;
drop policy "insights_update_own" on public.insights;

-- ---------------------------------------------------------------------------
-- Storage: private bucket for body scans. Objects live under "<user_id>/...",
-- and are only ever served through signed URLs.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('body-models', 'body-models', false)
on conflict (id) do nothing;

create policy "body_models_read_own" on storage.objects for select to authenticated
  using (bucket_id = 'body-models' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "body_models_write_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'body-models' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "body_models_update_own" on storage.objects for update to authenticated
  using (bucket_id = 'body-models' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "body_models_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'body-models' and (storage.foldername(name))[1] = (select auth.uid())::text);
