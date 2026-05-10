-- TAXIS — schema initial Supabase
-- Exécuter dans SQL Editor ou via `supabase db push`.
-- Premier admin : créer l’utilisateur dans Authentication, puis :
-- insert into public.profiles (id, full_name, role, commune_id)
-- values ('<uuid auth.users>', 'Admin Provincial', 'admin_provincial', null);

create extension if not exists "pgcrypto";

create type public.app_role as enum (
  'admin_provincial',
  'bourgmestre',
  'agent'
);

create table public.communes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role public.app_role not null default 'agent',
  commune_id uuid references public.communes (id),
  created_at timestamptz not null default now(),
  constraint profiles_commune_rule check (
    (role = 'admin_provincial' and commune_id is null)
    or (role in ('bourgmestre', 'agent') and commune_id is not null)
  )
);

create table public.collections (
  id uuid primary key default gen_random_uuid(),
  commune_id uuid not null references public.communes (id),
  amount numeric(14, 2) not null check (amount >= 0),
  tax_category text not null,
  payment_channel text,
  collected_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id)
);

create index collections_commune_collected_idx
  on public.collections (commune_id, collected_at desc);

alter table public.communes enable row level security;
alter table public.profiles enable row level security;
alter table public.collections enable row level security;

-- Communes
create policy communes_select_auth
  on public.communes for select
  to authenticated
  using (true);

create policy communes_write_admin
  on public.communes for all
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin_provincial'
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin_provincial'
    )
  );

-- Profils
create policy profiles_select_self
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

create policy profiles_select_admin
  on public.profiles for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin_provincial'
    )
  );

create policy profiles_select_same_commune
  on public.profiles for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles me
      where me.id = auth.uid()
        and me.role = 'bourgmestre'
        and me.commune_id = profiles.commune_id
    )
  );

-- Agents / bourgmestres : annuaire minimal au sein de la même commune
create policy profiles_colleagues_same_commune
  on public.profiles for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles me
      where me.id = auth.uid()
        and me.commune_id is not null
        and me.commune_id = profiles.commune_id
    )
  );

create policy profiles_update_self
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_update_admin
  on public.profiles for update
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin_provincial'
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin_provincial'
    )
  );

-- Collections
create policy collections_admin_all
  on public.collections for all
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin_provincial'
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin_provincial'
    )
  );

create policy collections_bourgmestre_select
  on public.collections for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'bourgmestre'
        and p.commune_id = collections.commune_id
    )
  );

create policy collections_bourgmestre_insert
  on public.collections for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'bourgmestre'
        and p.commune_id = collections.commune_id
    )
  );

create policy collections_agent_select
  on public.collections for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'agent'
        and p.commune_id = collections.commune_id
    )
  );

create policy collections_agent_insert
  on public.collections for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'agent'
        and p.commune_id = collections.commune_id
    )
    and commune_id = (select commune_id from public.profiles where id = auth.uid())
  );

-- Données de base (communes)
insert into public.communes (name)
values
  ('Lubumbashi'),
  ('Kampemba'),
  ('Katuba'),
  ('Ruashi'),
  ('Kenya')
on conflict (name) do nothing;
