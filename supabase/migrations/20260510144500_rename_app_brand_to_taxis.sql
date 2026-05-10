update public.app_settings
set
  app_name = 'TAXIS',
  updated_at = now()
where lower(trim(app_name)) = 'gestia';

alter table public.app_settings
alter column app_name set default 'TAXIS';
