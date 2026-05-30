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
      and role in ('bourgmestre', 'agent', 'taxateur')
  );
$$;

grant execute on function public.can_manage_assujetti_commune(uuid) to authenticated;

create or replace function public.can_access_assujetti_document(path text)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  commune uuid;
begin
  if path is null or path !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  commune := path::uuid;
  return public.can_read_provincial_scope()
    or public.can_manage_assujetti_commune(commune);
end;
$$;

grant execute on function public.can_access_assujetti_document(text) to authenticated;

create or replace function public.can_write_assujetti_document(path text)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  commune uuid;
begin
  if path is null or path !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  commune := path::uuid;
  return public.is_admin_provincial()
    or public.can_manage_assujetti_commune(commune);
end;
$$;

grant execute on function public.can_write_assujetti_document(text) to authenticated;

create table if not exists public.assujettis (
  id uuid primary key default gen_random_uuid(),
  commune_id uuid references public.communes (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null,
  status text not null default 'personne_physique',
  nom text not null,
  postnom text not null,
  prenom text not null,
  lieu_naissance text not null,
  date_naissance date not null,
  nationalite text not null,
  sexe text not null,
  adresse_commune text not null,
  adresse_rue text not null,
  adresse_quartier text not null,
  adresse_numero text not null,
  contact_prefix text not null,
  contact_telephone text not null,
  contact_email text,
  entreprise_nom text,
  id_nat text,
  rccm text,
  identity_document_name text,
  identity_document_path text,
  identity_document_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint assujettis_status_rule check (
    status in ('personne_physique', 'personne_morale')
  ),
  constraint assujettis_sexe_rule check (sexe in ('Masculin', 'Feminin'))
);

alter table public.assujettis enable row level security;

create index if not exists assujettis_commune_created_idx
  on public.assujettis (commune_id, created_at desc);

create index if not exists assujettis_id_nat_idx
  on public.assujettis (id_nat)
  where id_nat is not null;

drop policy if exists assujettis_select_provincial_readers on public.assujettis;
create policy assujettis_select_provincial_readers
  on public.assujettis for select
  to authenticated
  using (public.can_read_provincial_scope());

drop policy if exists assujettis_select_commune_staff on public.assujettis;
create policy assujettis_select_commune_staff
  on public.assujettis for select
  to authenticated
  using (
    commune_id is not null
    and public.can_manage_assujetti_commune(commune_id)
  );

drop policy if exists assujettis_insert_admin on public.assujettis;
create policy assujettis_insert_admin
  on public.assujettis for insert
  to authenticated
  with check (
    public.is_admin_provincial()
    and created_by = auth.uid()
  );

drop policy if exists assujettis_insert_commune_staff on public.assujettis;
create policy assujettis_insert_commune_staff
  on public.assujettis for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and commune_id is not null
    and public.can_manage_assujetti_commune(commune_id)
  );

drop policy if exists assujettis_update_admin on public.assujettis;
create policy assujettis_update_admin
  on public.assujettis for update
  to authenticated
  using (public.is_admin_provincial())
  with check (public.is_admin_provincial());

drop policy if exists assujettis_update_commune_staff on public.assujettis;
create policy assujettis_update_commune_staff
  on public.assujettis for update
  to authenticated
  using (
    commune_id is not null
    and public.can_manage_assujetti_commune(commune_id)
  )
  with check (
    commune_id is not null
    and public.can_manage_assujetti_commune(commune_id)
  );

insert into storage.buckets (id, name, public)
values ('assujetti-documents', 'assujetti-documents', false)
on conflict (id) do nothing;

drop policy if exists assujetti_documents_select on storage.objects;
create policy assujetti_documents_select
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'assujetti-documents'
    and public.can_access_assujetti_document((storage.foldername(name))[1])
  );

drop policy if exists assujetti_documents_insert on storage.objects;
create policy assujetti_documents_insert
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'assujetti-documents'
    and public.can_write_assujetti_document((storage.foldername(name))[1])
  );

drop policy if exists assujetti_documents_update on storage.objects;
create policy assujetti_documents_update
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'assujetti-documents'
    and public.can_write_assujetti_document((storage.foldername(name))[1])
  )
  with check (
    bucket_id = 'assujetti-documents'
    and public.can_write_assujetti_document((storage.foldername(name))[1])
  );
