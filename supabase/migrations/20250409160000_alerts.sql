-- Alertes métier : gravité, catégorie, périmètre commune (null = vue admin provincial uniquement).

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  severity text not null
    check (severity in ('critique', 'moyenne', 'faible')),
  category text not null
    check (category in ('probleme', 'fraude', 'retard', 'securite')),
  title text not null,
  body text not null,
  commune_id uuid references public.communes (id) on delete cascade,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index alerts_created_idx on public.alerts (created_at desc);
create index alerts_commune_idx on public.alerts (commune_id);

alter table public.alerts enable row level security;

-- Admin provincial : toutes les alertes (y compris commune_id null).
create policy alerts_select_admin
  on public.alerts for select
  to authenticated
  using (public.is_admin_provincial());

-- Bourgmestre : alertes rattachées à sa commune uniquement.
create policy alerts_select_bourgmestre
  on public.alerts for select
  to authenticated
  using (
    commune_id is not null
    and public.is_bourgmestre_of_commune(commune_id)
  );

-- Création manuelle / jobs futurs : admin seulement.
create policy alerts_insert_admin
  on public.alerts for insert
  to authenticated
  with check (public.is_admin_provincial());

create policy alerts_update_admin
  on public.alerts for update
  to authenticated
  using (public.is_admin_provincial())
  with check (public.is_admin_provincial());

-- Exemples (s’affichent si les communes seed existent)
insert into public.alerts (severity, category, title, body, commune_id)
select
  'moyenne',
  'probleme',
  'Montant atypique sur une collecte',
  'Un paiement dépasse l’écart-type habituel pour cette catégorie de taxe. Vérifier la saisie et le justificatif.',
  c.id
from public.communes c
where c.name = 'DILALA'
limit 1;

insert into public.alerts (severity, category, title, body, commune_id)
select
  'faible',
  'probleme',
  'Écart mineur sur arrondi',
  'Différence de centimes entre le total affiché et les lignes — information, pas de blocage.',
  c.id
from public.communes c
where c.name = 'MANIKA'
limit 1;

insert into public.alerts (severity, category, title, body, commune_id)
select
  'critique',
  'fraude',
  'Répétition suspecte de transactions',
  'Plusieurs enregistrements quasi identiques (montant, canal, fenêtre courte) pour le même agent — analyse requise.',
  c.id
from public.communes c
where c.name = 'FUNGURUME'
limit 1;

insert into public.alerts (severity, category, title, body, commune_id)
select
  'moyenne',
  'retard',
  'Synchronisation des données en retard',
  'Les agrégats du poste n’ont pas été confirmés dans les délais — vérifier la connectivité ou le statut EN_ATTENTE.',
  c.id
from public.communes c
where c.name = 'AUTRE'
limit 1;

-- Alerte provinciale (commune_id null) : visible admin uniquement (RLS bourgmestre exclut).
insert into public.alerts (severity, category, title, body, commune_id)
values (
  'critique',
  'securite',
  'Tentatives de connexion multiples sur un compte sensible',
  'Plusieurs échecs d''authentification suivis d''une réussite — contrôler l''activité et envisager une réinitialisation.',
  null
);
