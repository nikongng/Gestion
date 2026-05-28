-- Allow deleting Auth users while keeping financial history.
-- Historical rows keep their data; the deleted account reference becomes null.

alter table public.collections
  alter column created_by drop not null;

alter table public.collections
  drop constraint if exists collections_created_by_fkey;

alter table public.collections
  add constraint collections_created_by_fkey
  foreign key (created_by)
  references auth.users (id)
  on delete set null;

alter table public.perception_notes
  alter column created_by drop not null;

alter table public.perception_notes
  drop constraint if exists perception_notes_created_by_fkey;

alter table public.perception_notes
  add constraint perception_notes_created_by_fkey
  foreign key (created_by)
  references auth.users (id)
  on delete set null;
