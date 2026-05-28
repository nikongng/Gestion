alter table public.profiles
  add column if not exists taxpayer_id_type text,
  add column if not exists taxpayer_id_number text,
  add column if not exists taxpayer_location_label text,
  add column if not exists taxpayer_activity text,
  add column if not exists taxpayer_status text not null default 'actif';

create index if not exists profiles_taxpayer_id_number_idx
  on public.profiles (taxpayer_id_number)
  where taxpayer_id_number is not null;

create index if not exists profiles_taxpayer_status_idx
  on public.profiles (taxpayer_status)
  where role = 'contribuable';
