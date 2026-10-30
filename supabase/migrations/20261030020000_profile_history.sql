-- Relevant history the user chooses to add during onboarding (optional).
alter table public.profiles add column medical_history text[] not null default '{}';
