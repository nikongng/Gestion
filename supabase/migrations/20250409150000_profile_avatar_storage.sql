-- Photo de profil : URL publique + bucket Storage + verrouillage rôle/commune sur auto-édition.

alter table public.profiles
  add column if not exists avatar_url text;

comment on column public.profiles.avatar_url is
  'URL publique Supabase Storage (bucket avatars) ; modifiable par l’utilisateur ou l’admin.';

-- Empêche l’escalade de privilèges : un non-admin ne peut pas changer son rôle ni sa commune en s’éditant lui-même.
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
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_lock_role_on_self_update on public.profiles;
create trigger profiles_lock_role_on_self_update
  before update on public.profiles
  for each row
  execute function public.profiles_lock_role_on_self_update();

-- Bucket avatars (lecture publique pour affichage des images)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;

-- Politiques Storage : chaque utilisateur authentifié ne peut écrire que sous auth.uid()/
drop policy if exists avatars_select_public on storage.objects;
drop policy if exists avatars_insert_own_folder on storage.objects;
drop policy if exists avatars_update_own_folder on storage.objects;
drop policy if exists avatars_delete_own_folder on storage.objects;

create policy avatars_select_public
  on storage.objects for select
  to public
  using (bucket_id = 'avatars');

create policy avatars_insert_own_folder
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_update_own_folder
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_delete_own_folder
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
