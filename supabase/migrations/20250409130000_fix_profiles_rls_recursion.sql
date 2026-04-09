-- Corrige PostgreSQL 42P17 : « infinite recursion detected in policy for relation profiles ».
-- Les politiques qui lisent `profiles` dans un sous-EXISTS sur la même table se réévaluent en boucle.
-- Les fonctions SECURITY DEFINER lisent `profiles` sans appliquer la RLS.

create or replace function public.is_admin_provincial()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin_provincial'
  );
$$;

create or replace function public.is_bourgmestre_of_commune(target_commune uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'bourgmestre'
      and commune_id = target_commune
  );
$$;

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
      and role = 'agent'
      and commune_id = target_commune
  );
$$;

create or replace function public.current_profile_commune_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select commune_id from public.profiles where id = auth.uid() limit 1;
$$;

grant execute on function public.is_admin_provincial() to authenticated;
grant execute on function public.is_bourgmestre_of_commune(uuid) to authenticated;
grant execute on function public.is_agent_of_commune(uuid) to authenticated;
grant execute on function public.current_profile_commune_id() to authenticated;

-- Communes
drop policy if exists communes_write_admin on public.communes;
create policy communes_write_admin
  on public.communes for all
  to authenticated
  using (public.is_admin_provincial())
  with check (public.is_admin_provincial());

-- Profils
drop policy if exists profiles_select_admin on public.profiles;
drop policy if exists profiles_select_same_commune on public.profiles;
drop policy if exists profiles_colleagues_same_commune on public.profiles;
drop policy if exists profiles_update_admin on public.profiles;

create policy profiles_select_admin
  on public.profiles for select
  to authenticated
  using (public.is_admin_provincial());

create policy profiles_select_same_commune
  on public.profiles for select
  to authenticated
  using (
    profiles.commune_id is not null
    and public.is_bourgmestre_of_commune(profiles.commune_id)
  );

create policy profiles_colleagues_same_commune
  on public.profiles for select
  to authenticated
  using (
    public.current_profile_commune_id() is not null
    and profiles.commune_id = public.current_profile_commune_id()
  );

create policy profiles_update_admin
  on public.profiles for update
  to authenticated
  using (public.is_admin_provincial())
  with check (public.is_admin_provincial());

-- Collections
drop policy if exists collections_admin_all on public.collections;
drop policy if exists collections_bourgmestre_select on public.collections;
drop policy if exists collections_bourgmestre_insert on public.collections;
drop policy if exists collections_agent_select on public.collections;
drop policy if exists collections_agent_insert on public.collections;

create policy collections_admin_all
  on public.collections for all
  to authenticated
  using (public.is_admin_provincial())
  with check (public.is_admin_provincial());

create policy collections_bourgmestre_select
  on public.collections for select
  to authenticated
  using (public.is_bourgmestre_of_commune(collections.commune_id));

create policy collections_bourgmestre_insert
  on public.collections for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.is_bourgmestre_of_commune(commune_id)
  );

create policy collections_agent_select
  on public.collections for select
  to authenticated
  using (public.is_agent_of_commune(collections.commune_id));

create policy collections_agent_insert
  on public.collections for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.is_agent_of_commune(commune_id)
    and commune_id = public.current_profile_commune_id()
  );
