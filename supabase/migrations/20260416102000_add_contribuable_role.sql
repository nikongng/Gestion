alter table public.profiles
  add column if not exists taxpayer_identifier text;

create unique index if not exists profiles_taxpayer_identifier_uidx
  on public.profiles (taxpayer_identifier)
  where taxpayer_identifier is not null;

alter table public.profiles
  drop constraint if exists profiles_commune_rule;

alter table public.profiles
  add constraint profiles_commune_rule check (
    (role in ('admin_provincial', 'ministre_finances', 'gouverneur', 'contribuable') and commune_id is null)
    or (role in ('bourgmestre', 'agent') and commune_id is not null)
  );

alter table public.profiles
  drop constraint if exists profiles_taxpayer_identifier_rule;

alter table public.profiles
  add constraint profiles_taxpayer_identifier_rule check (
    (role = 'contribuable' and taxpayer_identifier is not null and length(btrim(taxpayer_identifier)) > 0)
    or (role <> 'contribuable' and taxpayer_identifier is null)
  );

alter table public.collections
  add column if not exists taxpayer_profile_id uuid references public.profiles (id) on delete set null;

alter table public.collections
  add column if not exists taxpayer_identifier text;

create index if not exists collections_taxpayer_profile_collected_idx
  on public.collections (taxpayer_profile_id, collected_at desc);

alter table public.collections
  drop constraint if exists collections_taxpayer_link_rule;

alter table public.collections
  add constraint collections_taxpayer_link_rule check (
    (taxpayer_profile_id is null and taxpayer_identifier is null)
    or (taxpayer_profile_id is not null and taxpayer_identifier is not null)
  );

create or replace function public.is_contribuable()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'contribuable'
  );
$$;

create or replace function public.current_profile_taxpayer_identifier()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select taxpayer_identifier
  from public.profiles
  where id = auth.uid()
  limit 1;
$$;

create or replace function public.can_edit_own_profile()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin_provincial', 'agent', 'contribuable')
  );
$$;

grant execute on function public.is_contribuable() to authenticated;
grant execute on function public.current_profile_taxpayer_identifier() to authenticated;
grant execute on function public.can_edit_own_profile() to authenticated;

drop policy if exists collections_contribuable_select on public.collections;
drop policy if exists collections_contribuable_insert on public.collections;

create policy collections_contribuable_select
  on public.collections for select
  to authenticated
  using (
    public.is_contribuable()
    and taxpayer_profile_id = auth.uid()
  );

create policy collections_contribuable_insert
  on public.collections for insert
  to authenticated
  with check (
    public.is_contribuable()
    and created_by = auth.uid()
    and taxpayer_profile_id = auth.uid()
    and taxpayer_identifier = public.current_profile_taxpayer_identifier()
  );
