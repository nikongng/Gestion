alter table public.alerts
  add column if not exists target_role text,
  add column if not exists target_user_id uuid references auth.users (id) on delete cascade,
  add column if not exists source_table text,
  add column if not exists source_id uuid;

alter table public.alerts
  drop constraint if exists alerts_target_role_rule;

alter table public.alerts
  add constraint alerts_target_role_rule check (
    target_role is null
    or target_role in (
      'admin_provincial',
      'ministre_finances',
      'gouverneur',
      'bourgmestre',
      'agent',
      'taxateur',
      'ordonnateur',
      'apureur'
    )
  );

create index if not exists alerts_target_role_idx
  on public.alerts (target_role, commune_id, created_at desc)
  where target_role is not null;

create index if not exists alerts_target_user_idx
  on public.alerts (target_user_id, created_at desc)
  where target_user_id is not null;

create index if not exists alerts_source_idx
  on public.alerts (source_table, source_id)
  where source_table is not null and source_id is not null;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    alter publication supabase_realtime add table public.alerts;
  end if;
exception
  when duplicate_object then
    null;
end;
$$;

drop policy if exists alerts_select_admin on public.alerts;
drop policy if exists alerts_select_bourgmestre on public.alerts;
drop policy if exists alerts_select_visible on public.alerts;

create policy alerts_select_visible
  on public.alerts for select
  to authenticated
  using (
    public.can_read_provincial_scope()
    or target_user_id = auth.uid()
    or (
      target_role is null
      and commune_id is not null
      and public.is_bourgmestre_of_commune(commune_id)
    )
    or (
      target_role is not null
      and public.profile_has_role(target_role)
      and (
        commune_id is null
        or commune_id = public.current_profile_commune_id()
      )
    )
  );

create or replace function public.notify_ordonnateur_taxation_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  commune_label text;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  if new.status <> 'taxation_creee' or new.commune_id is null then
    return new;
  end if;

  select c.name
    into commune_label
  from public.communes c
  where c.id = new.commune_id;

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
    'faible',
    'retard',
    'Nouvelle note de taxation a ordonnancer',
    concat(
      'La note ',
      new.note_number,
      ' de ',
      coalesce(new.taxpayer_name, 'l assujetti'),
      ' est disponible pour verification',
      case
        when commune_label is null then '.'
        else concat(' dans la commune ', commune_label, '.')
      end
    ),
    new.commune_id,
    'ordonnateur',
    'perception_notes',
    new.id
  );

  return new;
end;
$$;

drop trigger if exists perception_notes_notify_ordonnateur_on_taxation
  on public.perception_notes;

create trigger perception_notes_notify_ordonnateur_on_taxation
  after insert on public.perception_notes
  for each row
  execute function public.notify_ordonnateur_taxation_created();
