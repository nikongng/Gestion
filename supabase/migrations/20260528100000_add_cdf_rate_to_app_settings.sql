alter table public.app_settings
  add column if not exists cdf_rate numeric(14, 4) not null default 2300;

update public.app_settings
set cdf_rate = 2300
where cdf_rate is null or cdf_rate <= 0;
