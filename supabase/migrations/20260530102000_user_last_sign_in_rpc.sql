create or replace function public.get_users_last_sign_in()
returns table (
  id uuid,
  last_sign_in_at timestamptz
)
language sql
security definer
set search_path = public, auth
as $$
  select
    u.id,
    u.last_sign_in_at
  from auth.users u
  where public.is_admin_provincial()
  order by u.last_sign_in_at desc nulls last;
$$;

revoke all on function public.get_users_last_sign_in() from public;
grant execute on function public.get_users_last_sign_in() to authenticated;
