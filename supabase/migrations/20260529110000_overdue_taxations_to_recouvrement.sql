create or replace function public.mark_overdue_taxations_for_recovery()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer := 0;
begin
  update public.perception_notes pn
  set
    status = 'en_recouvrement',
    updated_at = now()
  where pn.status = 'taxation_creee'
    and pn.created_at < now() - interval '8 days'
    and (
      public.can_read_provincial_scope()
      or (
        pn.commune_id is not null
        and (
          public.is_bourgmestre_of_commune(pn.commune_id)
          or public.is_agent_of_commune(pn.commune_id)
          or public.can_manage_assujetti_commune(pn.commune_id)
        )
      )
    );

  get diagnostics affected = row_count;
  return affected;
end;
$$;

grant execute on function public.mark_overdue_taxations_for_recovery()
  to authenticated;
