alter type public.app_role add value if not exists 'taxateur';
alter type public.app_role add value if not exists 'ordonnateur';
alter type public.app_role add value if not exists 'apureur';

alter table public.profiles
  drop constraint if exists profiles_commune_rule;

alter table public.profiles
  add constraint profiles_commune_rule check (
    (role::text in ('admin_provincial', 'ministre_finances', 'gouverneur', 'contribuable') and commune_id is null)
    or (role::text in ('bourgmestre', 'agent', 'taxateur', 'ordonnateur', 'apureur') and commune_id is not null)
  );

create or replace function public.is_agent_of_commune(target_commune uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role::text in ('agent', 'taxateur', 'ordonnateur', 'apureur')
      and commune_id = target_commune
  );
$$;

grant execute on function public.is_agent_of_commune(uuid) to authenticated;
