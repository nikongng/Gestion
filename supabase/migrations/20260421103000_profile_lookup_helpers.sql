create or replace function public.lookup_taxpayer_profile(
  p_taxpayer_identifier text
)
returns table(
  id uuid,
  full_name text,
  role public.app_role,
  commune_id uuid,
  avatar_url text,
  taxpayer_identifier text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    p.id,
    p.full_name,
    p.role,
    p.commune_id,
    p.avatar_url,
    p.taxpayer_identifier
  from public.profiles p
  where p.taxpayer_identifier is not null
    and lower(btrim(p.taxpayer_identifier)) =
        lower(btrim(p_taxpayer_identifier))
  limit 1;
$$;

create or replace function public.lookup_profile_names(
  p_user_ids uuid[]
)
returns table(
  id uuid,
  full_name text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    p.id,
    p.full_name
  from public.profiles p
  where p.id = any(coalesce(p_user_ids, '{}'::uuid[]));
$$;

grant execute on function public.lookup_taxpayer_profile(text) to authenticated;
grant execute on function public.lookup_profile_names(uuid[]) to authenticated;
