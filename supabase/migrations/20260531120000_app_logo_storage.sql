alter table public.app_settings
  add column if not exists logo_url text;

insert into storage.buckets (id, name, public)
values ('app-assets', 'app-assets', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists app_assets_select_public on storage.objects;
drop policy if exists app_assets_insert_admin on storage.objects;
drop policy if exists app_assets_update_admin on storage.objects;
drop policy if exists app_assets_delete_admin on storage.objects;

create policy app_assets_select_public
  on storage.objects for select
  to public
  using (bucket_id = 'app-assets');

create policy app_assets_insert_admin
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'app-assets'
    and public.is_admin_provincial()
  );

create policy app_assets_update_admin
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'app-assets'
    and public.is_admin_provincial()
  )
  with check (
    bucket_id = 'app-assets'
    and public.is_admin_provincial()
  );

create policy app_assets_delete_admin
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'app-assets'
    and public.is_admin_provincial()
  );
