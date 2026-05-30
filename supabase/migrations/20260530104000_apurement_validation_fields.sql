alter table public.perception_notes
  add column if not exists apurement_comment text,
  add column if not exists bank_slip_submitted boolean not null default false;
