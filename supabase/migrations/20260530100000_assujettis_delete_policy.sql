drop policy if exists assujettis_delete_admin on public.assujettis;
create policy assujettis_delete_admin
  on public.assujettis for delete
  to authenticated
  using (public.is_admin_provincial());

drop policy if exists assujettis_delete_commune_staff on public.assujettis;
create policy assujettis_delete_commune_staff
  on public.assujettis for delete
  to authenticated
  using (
    commune_id is not null
    and public.can_manage_assujetti_commune(commune_id)
  );

drop policy if exists assujetti_documents_delete on storage.objects;
create policy assujetti_documents_delete
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'assujetti-documents'
    and public.can_write_assujetti_document((storage.foldername(name))[1])
  );
