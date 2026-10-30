-- Saved insights are reused until the episode changes (same entries, pathways, red flags, model).
alter table public.insights add column episode_key text;
create index insights_user_episode_key on public.insights (user_id, episode_key, created_at desc);

-- One row per AI call, for per-user daily limits. Written only by Edge Functions (service role).
create table public.ai_usage (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  function   text not null,
  created_at timestamptz not null default now()
);
create index ai_usage_user_fn_time on public.ai_usage (user_id, function, created_at desc);
alter table public.ai_usage enable row level security;
alter table public.ai_usage force row level security;
create policy "ai_usage_select_own" on public.ai_usage for select to authenticated
  using ((select auth.uid()) = user_id);

-- Private bucket for exported doctor reports, shared only through short-lived signed URLs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reports', 'reports', false, 20971520, array['application/pdf'])
on conflict (id) do nothing;

create policy "reports_read_own" on storage.objects for select to authenticated
  using (bucket_id = 'reports' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "reports_write_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'reports' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "reports_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'reports' and (storage.foldername(name))[1] = (select auth.uid())::text);
