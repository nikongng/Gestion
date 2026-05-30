alter table public.profiles
  add column if not exists roles text[] not null default array[]::text[];

update public.profiles
set roles = array[role::text]
where roles = array[]::text[];

create or replace function public.profile_has_role(target_role text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and (
        role::text = target_role
        or target_role = any(roles)
      )
  );
$$;

grant execute on function public.profile_has_role(text) to authenticated;
