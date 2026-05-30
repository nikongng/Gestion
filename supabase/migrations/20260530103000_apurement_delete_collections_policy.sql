drop policy if exists collections_delete_apurement_mairie_staff
  on public.collections;

create policy collections_delete_apurement_mairie_staff
  on public.collections for delete
  to authenticated
  using (
    public.is_mairie_staff()
    and created_by = auth.uid()
    and revenue_phase = 'apurement'
  );
