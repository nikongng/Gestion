alter table public.collections
  add column if not exists revenue_phase text not null default 'apurement',
  add column if not exists workflow_status text not null default 'apuree_cpi_genere',
  add column if not exists perception_note_number text,
  add column if not exists cpi_number text,
  add column if not exists paid_at timestamptz,
  add column if not exists apured_at timestamptz,
  add column if not exists is_auto_liquidated boolean not null default false;

update public.collections
set
  revenue_phase = coalesce(revenue_phase, 'apurement'),
  workflow_status = coalesce(workflow_status, 'apuree_cpi_genere'),
  paid_at = coalesce(paid_at, collected_at),
  apured_at = coalesce(apured_at, collected_at)
where revenue_phase is null
   or workflow_status is null
   or paid_at is null
   or apured_at is null;

alter table public.collections
  drop constraint if exists collections_revenue_phase_rule;

alter table public.collections
  add constraint collections_revenue_phase_rule check (
    revenue_phase in ('taxation', 'ordonnancement', 'paiement', 'apurement', 'recouvrement')
  );

alter table public.collections
  drop constraint if exists collections_workflow_status_rule;

alter table public.collections
  add constraint collections_workflow_status_rule check (
    workflow_status in (
      'taxation_creee',
      'ordonnee',
      'note_perception_generee',
      'paiement_declare',
      'apuree_cpi_genere',
      'en_recouvrement',
      'annulee'
    )
  );

create index if not exists collections_workflow_status_idx
  on public.collections (workflow_status, collected_at desc);

create index if not exists collections_perception_note_number_idx
  on public.collections (perception_note_number)
  where perception_note_number is not null;

create table if not exists public.perception_notes (
  id uuid primary key default gen_random_uuid(),
  note_number text not null unique,
  commune_id uuid references public.communes (id),
  collection_scope text not null default 'commune',
  amount numeric(14, 2) not null check (amount >= 0),
  tax_category text not null,
  payment_channel text,
  taxpayer_profile_id uuid references public.profiles (id) on delete set null,
  taxpayer_identifier text,
  taxpayer_name text,
  taxpayer_phone text,
  taxpayer_email text,
  taxpayer_address text,
  payment_delay_days integer not null default 8 check (payment_delay_days > 0),
  payment_deadline timestamptz not null,
  status text not null default 'note_perception_generee',
  taxateur_id uuid references auth.users (id) on delete set null,
  ordonnateur_id uuid references auth.users (id) on delete set null,
  created_by uuid not null references auth.users (id),
  collection_id uuid references public.collections (id) on delete set null,
  cpi_number text,
  paid_at timestamptz,
  apured_at timestamptz,
  legal_reference text,
  tariff_details text,
  tariff_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint perception_notes_scope_rule check (
    (collection_scope = 'mairie' and commune_id is null)
    or (collection_scope = 'commune' and commune_id is not null)
  ),
  constraint perception_notes_status_rule check (
    status in (
      'taxation_creee',
      'ordonnee',
      'note_perception_generee',
      'paiement_declare',
      'apuree_cpi_genere',
      'en_recouvrement',
      'annulee'
    )
  )
);

alter table public.perception_notes enable row level security;

create index if not exists perception_notes_status_deadline_idx
  on public.perception_notes (status, payment_deadline);

create index if not exists perception_notes_taxpayer_identifier_idx
  on public.perception_notes (taxpayer_identifier)
  where taxpayer_identifier is not null;

drop policy if exists perception_notes_select_provincial_readers on public.perception_notes;
create policy perception_notes_select_provincial_readers
  on public.perception_notes for select
  to authenticated
  using (public.can_read_provincial_scope());

drop policy if exists perception_notes_select_commune on public.perception_notes;
create policy perception_notes_select_commune
  on public.perception_notes for select
  to authenticated
  using (
    commune_id is not null
    and (
      public.is_bourgmestre_of_commune(commune_id)
      or public.is_agent_of_commune(commune_id)
    )
  );

drop policy if exists perception_notes_insert_admin on public.perception_notes;
create policy perception_notes_insert_admin
  on public.perception_notes for insert
  to authenticated
  with check (public.is_admin_provincial());

drop policy if exists perception_notes_insert_agent on public.perception_notes;
create policy perception_notes_insert_agent
  on public.perception_notes for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and commune_id is not null
    and public.is_agent_of_commune(commune_id)
    and commune_id = public.current_profile_commune_id()
  );

drop policy if exists perception_notes_update_admin on public.perception_notes;
create policy perception_notes_update_admin
  on public.perception_notes for update
  to authenticated
  using (public.is_admin_provincial())
  with check (public.is_admin_provincial());

drop policy if exists perception_notes_update_agent on public.perception_notes;
create policy perception_notes_update_agent
  on public.perception_notes for update
  to authenticated
  using (
    commune_id is not null
    and public.is_agent_of_commune(commune_id)
  )
  with check (
    commune_id is not null
    and public.is_agent_of_commune(commune_id)
  );
