alter table public.profiles
  add column if not exists taxpayer_email text,
  add column if not exists taxpayer_phone text,
  add column if not exists taxpayer_address text,
  add column if not exists is_legal_entity boolean not null default false,
  add column if not exists legal_denomination text,
  add column if not exists legal_nif text,
  add column if not exists legal_representative_name text;

create index if not exists profiles_legal_nif_idx
  on public.profiles (legal_nif)
  where legal_nif is not null;
