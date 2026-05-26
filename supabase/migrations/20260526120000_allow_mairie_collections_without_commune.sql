alter table public.collections
  alter column commune_id drop not null;

update public.collections
set commune_id = null
where collection_scope = 'mairie';

alter table public.collections
  drop constraint if exists collections_mairie_commune_rule;

alter table public.collections
  add constraint collections_mairie_commune_rule check (
    (collection_scope = 'mairie' and commune_id is null)
    or (collection_scope = 'commune' and commune_id is not null)
  );
