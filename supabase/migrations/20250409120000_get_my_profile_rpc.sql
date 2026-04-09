-- Lecture du profil courant en contournant les ambiguïtés RLS côté client.
-- À exécuter dans le SQL Editor si le chargement du profil échoue depuis l’app.

create or replace function public.get_my_profile()
returns setof public.profiles
language sql
security definer
set search_path = public
stable
as $$
  select * from public.profiles where id = auth.uid();
$$;

grant execute on function public.get_my_profile() to authenticated;
