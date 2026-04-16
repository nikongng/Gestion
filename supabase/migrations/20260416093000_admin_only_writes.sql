-- Admin provincial = lecture/ecriture complete.
-- Ministre des finances, gouverneur et bourgmestre = lecture seule,
-- sauf modification de leur avatar et de leur mot de passe.
-- Agent = collecte + edition de son propre profil + avatar + mot de passe.

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
      and role = 'admin_provincial'
  );
$$;

create or replace function public.can_read_provincial_scope()
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

create or replace function public.can_edit_own_profile()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin_provincial', 'agent')
  );
$$;

grant execute on function public.is_admin_provincial() to authenticated;
grant execute on function public.can_read_provincial_scope() to authenticated;
grant execute on function public.can_edit_own_profile() to authenticated;

drop policy if exists profiles_select_admin on public.profiles;
create policy profiles_select_admin
  on public.profiles for select
  to authenticated
  using (public.can_read_provincial_scope());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists collections_admin_all on public.collections;
drop policy if exists collections_select_provincial_readers on public.collections;
drop policy if exists collections_insert_admin on public.collections;
drop policy if exists collections_update_admin on public.collections;
drop policy if exists collections_delete_admin on public.collections;
drop policy if exists collections_bourgmestre_select on public.collections;
drop policy if exists collections_bourgmestre_insert on public.collections;
drop policy if exists collections_agent_select on public.collections;
drop policy if exists collections_agent_insert on public.collections;

create policy collections_select_provincial_readers
  on public.collections for select
  to authenticated
  using (public.can_read_provincial_scope());

create policy collections_insert_admin
  on public.collections for insert
  to authenticated
  with check (public.is_admin_provincial());

create policy collections_update_admin
  on public.collections for update
  to authenticated
  using (public.is_admin_provincial())
  with check (public.is_admin_provincial());

create policy collections_delete_admin
  on public.collections for delete
  to authenticated
  using (public.is_admin_provincial());

create policy collections_bourgmestre_select
  on public.collections for select
  to authenticated
  using (public.is_bourgmestre_of_commune(collections.commune_id));

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

drop policy if exists alerts_select_admin on public.alerts;
create policy alerts_select_admin
  on public.alerts for select
  to authenticated
  using (public.can_read_provincial_scope());

drop policy if exists avatars_insert_own_folder on storage.objects;
drop policy if exists avatars_update_own_folder on storage.objects;
drop policy if exists avatars_delete_own_folder on storage.objects;

create or replace function public.profiles_lock_role_on_self_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if new.id = auth.uid() and not public.is_admin_provincial() then
    new.role := old.role;
    new.commune_id := old.commune_id;
    new.created_at := old.created_at;

    if not public.can_edit_own_profile() then
      new.full_name := old.full_name;
    end if;
  end if;

  return new;
end;
$$;

create policy avatars_insert_own_folder
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_update_own_folder
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_delete_own_folder
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
