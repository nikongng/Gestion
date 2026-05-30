alter table public.app_settings
  add column if not exists system_description text not null default 'Plateforme de gestion fiscale et administrative',
  add column if not exists system_version text not null default 'v1.0.0',
  add column if not exists installation_date text not null default '01/01/2025',
  add column if not exists timezone_label text not null default '(GMT+1) Afrique/Kinshasa',
  add column if not exists default_language text not null default 'Francais',
  add column if not exists date_format text not null default 'DD/MM/YYYY',
  add column if not exists time_format text not null default '24 heures (14:30)',
  add column if not exists currency_label text not null default 'Franc Congolais (FC)',
  add column if not exists decimal_separator text not null default ',',
  add column if not exists thousand_separator text not null default '.',
  add column if not exists fiscal_year text not null default '2025',
  add column if not exists fiscal_start_date text not null default '01/01/2025',
  add column if not exists fiscal_end_date text not null default '31/12/2025',
  add column if not exists default_interest_rate numeric(6, 2) not null default 10,
  add column if not exists late_penalty_rate numeric(6, 2) not null default 2,
  add column if not exists email_notifications_enabled boolean not null default true,
  add column if not exists user_registration_enabled boolean not null default true,
  add column if not exists two_factor_validation_enabled boolean not null default false,
  add column if not exists auto_session_enabled boolean not null default true,
  add column if not exists maintenance_mode_enabled boolean not null default false;

update public.app_settings
set
  system_description = coalesce(
    nullif(system_description, ''),
    'Plateforme de gestion fiscale et administrative'
  ),
  system_version = coalesce(nullif(system_version, ''), 'v1.0.0'),
  installation_date = coalesce(nullif(installation_date, ''), '01/01/2025'),
  timezone_label = coalesce(
    nullif(timezone_label, ''),
    '(GMT+1) Afrique/Kinshasa'
  ),
  default_language = coalesce(nullif(default_language, ''), 'Francais'),
  date_format = coalesce(nullif(date_format, ''), 'DD/MM/YYYY'),
  time_format = coalesce(nullif(time_format, ''), '24 heures (14:30)'),
  currency_label = coalesce(nullif(currency_label, ''), 'Franc Congolais (FC)'),
  decimal_separator = coalesce(nullif(decimal_separator, ''), ','),
  thousand_separator = coalesce(nullif(thousand_separator, ''), '.'),
  fiscal_year = coalesce(nullif(fiscal_year, ''), '2025'),
  fiscal_start_date = coalesce(nullif(fiscal_start_date, ''), '01/01/2025'),
  fiscal_end_date = coalesce(nullif(fiscal_end_date, ''), '31/12/2025'),
  default_interest_rate = coalesce(default_interest_rate, 10),
  late_penalty_rate = coalesce(late_penalty_rate, 2),
  email_notifications_enabled = coalesce(email_notifications_enabled, true),
  user_registration_enabled = coalesce(user_registration_enabled, true),
  two_factor_validation_enabled = coalesce(
    two_factor_validation_enabled,
    false
  ),
  auto_session_enabled = coalesce(auto_session_enabled, true),
  maintenance_mode_enabled = coalesce(maintenance_mode_enabled, false)
where id = 1;
