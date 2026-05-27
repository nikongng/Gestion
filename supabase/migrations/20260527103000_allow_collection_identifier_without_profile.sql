alter table public.collections
  drop constraint if exists collections_taxpayer_link_rule;

alter table public.collections
  add constraint collections_taxpayer_link_rule check (
    taxpayer_profile_id is null
    or (
      taxpayer_profile_id is not null
      and taxpayer_identifier is not null
      and length(btrim(taxpayer_identifier)) > 0
    )
  );

create index if not exists collections_taxpayer_identifier_collected_idx
  on public.collections (taxpayer_identifier, collected_at desc)
  where taxpayer_identifier is not null;
