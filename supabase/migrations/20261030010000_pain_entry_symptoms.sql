-- Red-flag symptoms the user ticked when logging (IDs from data/red-flags.json).
alter table public.pain_entries add column symptoms text[] not null default '{}';
