create or replace function public.is_mairie_staff()
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
        role::text in ('taxateur', 'ordonnateur', 'apureur', 'agent')
        or coalesce(roles, array[]::text[]) && array[
          'taxateur',
          'ordonnateur',
          'apureur',
          'agent'
        ]::text[]
      )
  );
$$;

grant execute on function public.is_mairie_staff() to authenticated;

alter table public.profiles
  drop constraint if exists profiles_commune_rule;

update public.profiles
set commune_id = null
where role::text in ('taxateur', 'ordonnateur', 'apureur', 'agent')
   or coalesce(roles, array[]::text[]) && array[
     'taxateur',
     'ordonnateur',
     'apureur',
     'agent'
   ]::text[];

alter table public.profiles
  add constraint profiles_commune_rule check (
    (
      (array[role::text] || coalesce(roles, array[]::text[])) && array[
        'bourgmestre'
      ]::text[]
      and commune_id is not null
    )
    or (
      not (
        (array[role::text] || coalesce(roles, array[]::text[])) && array[
          'bourgmestre'
        ]::text[]
      )
    )
  );

create or replace function public.is_agent_of_commune(target_commune uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.is_mairie_staff();
$$;

grant execute on function public.is_agent_of_commune(uuid) to authenticated;

create or replace function public.can_manage_assujetti_commune(target_commune uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.is_mairie_staff();
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
  if path = 'mairie' then
    return public.can_read_provincial_scope()
      or public.is_mairie_staff();
  end if;

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
  if path = 'mairie' then
    return public.is_admin_provincial()
      or public.is_mairie_staff();
  end if;

  if path is null or path !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  commune := path::uuid;
  return public.is_admin_provincial()
    or public.can_manage_assujetti_commune(commune);
end;
$$;

grant execute on function public.can_write_assujetti_document(text) to authenticated;

drop policy if exists perception_notes_select_commune on public.perception_notes;
drop policy if exists perception_notes_insert_agent on public.perception_notes;
drop policy if exists perception_notes_update_agent on public.perception_notes;
drop policy if exists perception_notes_select_mairie_staff on public.perception_notes;
drop policy if exists perception_notes_insert_taxateur_mairie on public.perception_notes;
drop policy if exists perception_notes_update_mairie_staff on public.perception_notes;

create policy perception_notes_select_mairie_staff
  on public.perception_notes for select
  to authenticated
  using (public.is_mairie_staff());

create policy perception_notes_insert_taxateur_mairie
  on public.perception_notes for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.profile_has_role('taxateur')
    and collection_scope = 'mairie'
    and commune_id is null
  );

create policy perception_notes_update_mairie_staff
  on public.perception_notes for update
  to authenticated
  using (public.is_mairie_staff())
  with check (public.is_mairie_staff());

drop policy if exists collections_insert_mairie_staff on public.collections;
create policy collections_insert_mairie_staff
  on public.collections for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.is_mairie_staff()
    and collection_scope = 'mairie'
    and commune_id is null
  );

drop policy if exists assujettis_select_mairie_staff on public.assujettis;
drop policy if exists assujettis_insert_mairie_staff on public.assujettis;
drop policy if exists assujettis_update_mairie_staff on public.assujettis;

create policy assujettis_select_mairie_staff
  on public.assujettis for select
  to authenticated
  using (public.is_mairie_staff());

create policy assujettis_insert_mairie_staff
  on public.assujettis for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.is_mairie_staff()
    and commune_id is null
  );

create policy assujettis_update_mairie_staff
  on public.assujettis for update
  to authenticated
  using (public.is_mairie_staff())
  with check (public.is_mairie_staff());

drop policy if exists alerts_select_visible on public.alerts;

create policy alerts_select_visible
  on public.alerts for select
  to authenticated
  using (
    public.can_read_provincial_scope()
    or target_user_id = auth.uid()
    or (
      target_role is not null
      and public.profile_has_role(target_role)
    )
    or (
      target_role is null
      and public.is_mairie_staff()
    )
  );

create index if not exists alerts_target_role_created_idx
  on public.alerts (target_role, created_at desc)
  where target_role is not null;

drop trigger if exists perception_notes_notify_ordonnateur_on_taxation
  on public.perception_notes;

drop trigger if exists perception_notes_notify_workflow_roles
  on public.perception_notes;

drop function if exists public.notify_ordonnateur_taxation_created();

create or replace function public.notify_perception_note_workflow_roles()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_roles text[] := array[]::text[];
  target text;
  alert_title text;
  alert_body text;
  note_label text;
  taxpayer_label text;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  note_label := coalesce(nullif(new.note_number, ''), 'sans numero');
  taxpayer_label := coalesce(nullif(new.taxpayer_name, ''), 'l assujetti');

  if new.status = 'taxation_creee' then
    target_roles := array['ordonnateur'];
    alert_title := 'Nouvelle note de taxation a liquider';
    alert_body := concat(
      'La note ',
      note_label,
      ' de ',
      taxpayer_label,
      ' attend verification et validation par le liquidateur.'
    );
  elsif new.status in ('ordonnee', 'note_perception_generee') then
    target_roles := array['apureur'];
    alert_title := 'Note de perception a apurer';
    alert_body := concat(
      'La note ',
      note_label,
      ' de ',
      taxpayer_label,
      ' est validee et attend apurement puis emission du CPI.'
    );
  elsif new.status = 'paiement_declare' then
    target_roles := array['apureur'];
    alert_title := 'Paiement a verifier';
    alert_body := concat(
      'Un paiement est declare pour la note ',
      note_label,
      ' de ',
      taxpayer_label,
      '. Verification requise avant CPI.'
    );
  elsif new.status = 'en_recouvrement' then
    target_roles := array['agent'];
    alert_title := 'Dossier envoye au recouvrement';
    alert_body := concat(
      'La note ',
      note_label,
      ' de ',
      taxpayer_label,
      ' necessite une action de recouvrement.'
    );
  elsif new.status = 'apuree_cpi_genere' then
    target_roles := array['taxateur', 'ordonnateur'];
    alert_title := 'CPI delivre';
    alert_body := concat(
      'La note ',
      note_label,
      ' de ',
      taxpayer_label,
      ' est apuree et le CPI est disponible.'
    );
  else
    return new;
  end if;

  foreach target in array target_roles loop
    insert into public.alerts (
      severity,
      category,
      title,
      body,
      commune_id,
      target_role,
      source_table,
      source_id
    )
    values (
      case when new.status = 'en_recouvrement' then 'moyenne' else 'faible' end,
      'retard',
      alert_title,
      alert_body,
      new.commune_id,
      target,
      'perception_notes',
      new.id
    );
  end loop;

  return new;
end;
$$;

create trigger perception_notes_notify_workflow_roles
  after insert or update of status on public.perception_notes
  for each row
  execute function public.notify_perception_note_workflow_roles();

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
      or public.is_mairie_staff()
    );

  get diagnostics affected = row_count;
  return affected;
end;
$$;

grant execute on function public.mark_overdue_taxations_for_recovery()
  to authenticated;
