alter table public.profiles
  add column if not exists account_status text not null default 'actif';

update public.profiles
set account_status = 'actif'
where account_status not in ('actif', 'inactif');

alter table public.profiles
  drop constraint if exists profiles_account_status_rule;

alter table public.profiles
  add constraint profiles_account_status_rule
  check (account_status in ('actif', 'inactif'));

create index if not exists profiles_account_status_idx
  on public.profiles (account_status);

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
    new.roles := old.roles;
    new.commune_id := old.commune_id;
    new.created_at := old.created_at;
    new.account_status := old.account_status;
    new.taxpayer_status := old.taxpayer_status;

    if not public.can_edit_own_profile() then
      new.full_name := old.full_name;
    end if;
  end if;

  return new;
end;
$$;
