update public.app_settings
set app_name = 'GESTIA',
    updated_at = now()
where id = 1
  and app_name <> 'GESTIA';
