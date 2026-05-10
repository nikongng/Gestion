-- Libellés application / province (éditables par admin provincial).

create table if not exists public.app_settings (
  id smallint primary key default 1 check (id = 1),
  app_name text not null default 'TAXIS',
  province_name text not null default 'Province du Haut-Katanga',
  updated_at timestamptz not null default now()
);

insert into public.app_settings (id, app_name, province_name)
values (1, 'TAXIS', 'Province du Haut-Katanga')
on conflict (id) do nothing;

alter table public.app_settings enable row level security;

-- Lecture pour tous (écran login / accueil sans session)
create policy app_settings_select_public
  on public.app_settings for select
  to anon, authenticated
  using (true);

-- Écriture : admin provincial uniquement (insert + update ; pas de delete)
create policy app_settings_insert_admin
  on public.app_settings for insert
  to authenticated
  with check (public.is_admin_provincial() and id = 1);

create policy app_settings_update_admin
  on public.app_settings for update
  to authenticated
  using (public.is_admin_provincial() and id = 1)
  with check (public.is_admin_provincial() and id = 1);
