-- Answers to a pain insight's follow-up questions: [{question_id, question, answer: yes|no|unsure}].
alter table public.pain_entries add column clarifications jsonb;
