alter table public.collections
  add column if not exists collection_scope text not null default 'commune';

update public.collections
set collection_scope = case
  when lower(coalesce(tax_category, '')) like '%mairie%' then 'mairie'
  else 'commune'
end
where collection_scope is null
   or collection_scope not in ('mairie', 'commune');

alter table public.collections
  drop constraint if exists collections_scope_rule;

alter table public.collections
  add constraint collections_scope_rule check (
    collection_scope in ('mairie', 'commune')
  );

create index if not exists collections_scope_collected_idx
  on public.collections (collection_scope, collected_at desc);
