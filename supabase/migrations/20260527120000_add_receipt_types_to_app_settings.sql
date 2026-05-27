alter table public.app_settings
  add column if not exists receipt_types text[] not null default '{}';

update public.app_settings
set receipt_types = coalesce(receipt_types, '{}')
where id = 1;
