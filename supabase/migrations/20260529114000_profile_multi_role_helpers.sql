alter table public.profiles
  drop constraint if exists profiles_roles_allowed_rule;

alter table public.profiles
  add constraint profiles_roles_allowed_rule check (
    coalesce(roles, array[]::text[]) <@ array[
      'admin_provincial',
      'ministre_finances',
      'gouverneur',
      'bourgmestre',
      'agent',
      'taxateur',
      'ordonnateur',
      'apureur',
      'contribuable'
    ]::text[]
  );

alter table public.profiles
  drop constraint if exists profiles_commune_rule;

alter table public.profiles
  add constraint profiles_commune_rule check (
    (
      (array[role::text] || coalesce(roles, array[]::text[])) && array[
        'bourgmestre',
        'agent',
        'taxateur',
        'ordonnateur',
        'apureur'
      ]::text[]
      and commune_id is not null
    )
    or (
      not (
        (array[role::text] || coalesce(roles, array[]::text[])) && array[
          'bourgmestre',
          'agent',
          'taxateur',
          'ordonnateur',
          'apureur'
        ]::text[]
      )
      and commune_id is null
    )
  );

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
        or target_role = any(coalesce(roles, array[]::text[]))
      )
  );
$$;

grant execute on function public.profile_has_role(text) to authenticated;

create or replace function public.is_admin_provincial()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.profile_has_role('admin_provincial');
$$;

create or replace function public.can_read_provincial_scope()
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
        role::text in ('admin_provincial', 'ministre_finances', 'gouverneur')
        or coalesce(roles, array[]::text[]) && array[
          'admin_provincial',
          'ministre_finances',
          'gouverneur'
        ]::text[]
      )
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
    select 1
    from public.profiles
    where id = auth.uid()
      and (
        role::text in (
          'admin_provincial',
          'agent',
          'taxateur',
          'ordonnateur',
          'apureur',
          'contribuable'
        )
        or coalesce(roles, array[]::text[]) && array[
          'admin_provincial',
          'agent',
          'taxateur',
          'ordonnateur',
          'apureur',
          'contribuable'
        ]::text[]
      )
  );
$$;

create or replace function public.is_bourgmestre_of_commune(target_commune uuid)
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
      and commune_id = target_commune
      and (
        role::text = 'bourgmestre'
        or 'bourgmestre' = any(coalesce(roles, array[]::text[]))
      )
  );
$$;

create or replace function public.is_agent_of_commune(target_commune uuid)
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
      and commune_id = target_commune
      and (
        role::text in ('agent', 'taxateur', 'ordonnateur', 'apureur')
        or coalesce(roles, array[]::text[]) && array[
          'agent',
          'taxateur',
          'ordonnateur',
          'apureur'
        ]::text[]
      )
  );
$$;

create or replace function public.can_manage_assujetti_commune(target_commune uuid)
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
      and commune_id = target_commune
      and (
        role::text in ('bourgmestre', 'agent', 'taxateur')
        or coalesce(roles, array[]::text[]) && array[
          'bourgmestre',
          'agent',
          'taxateur'
        ]::text[]
      )
  );
$$;

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

    if not public.can_edit_own_profile() then
      new.full_name := old.full_name;
    end if;
  end if;

  return new;
end;
$$;

grant execute on function public.is_admin_provincial() to authenticated;
grant execute on function public.can_read_provincial_scope() to authenticated;
grant execute on function public.can_edit_own_profile() to authenticated;
grant execute on function public.is_bourgmestre_of_commune(uuid) to authenticated;
grant execute on function public.is_agent_of_commune(uuid) to authenticated;
grant execute on function public.can_manage_assujetti_commune(uuid) to authenticated;
