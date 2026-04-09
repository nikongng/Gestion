-- Ajoute les rôles "ministre_finances" et "gouverneur" au schéma.
-- Exécuter via SQL Editor ou `supabase db push`.

alter type public.app_role add value if not exists 'ministre_finances';
alter type public.app_role add value if not exists 'gouverneur';

alter table public.profiles
  drop constraint if exists profiles_commune_rule;

alter table public.profiles
  add constraint profiles_commune_rule check (
    (role in ('admin_provincial', 'ministre_finances', 'gouverneur') and commune_id is null)
    or (role in ('bourgmestre', 'agent') and commune_id is not null)
  );

create or replace function public.is_admin_provincial()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin_provincial', 'ministre_finances', 'gouverneur')
  );
$$;
