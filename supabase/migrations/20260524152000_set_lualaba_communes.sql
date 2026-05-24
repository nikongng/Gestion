do $$
declare
  source_id uuid;
  target_id uuid;
  autre_id uuid;
  stale_id uuid;
begin
  insert into public.communes (name)
  values ('DILALA'), ('MANIKA'), ('FUNGURUME'), ('AUTRE')
  on conflict (name) do nothing;

  for source_id, target_id in
    select *
    from (
      values
      (
        (select id from public.communes where name = 'Lubumbashi' limit 1),
        (select id from public.communes where name = 'DILALA' limit 1)
      ),
      (
        (select id from public.communes where name = 'Kampemba' limit 1),
        (select id from public.communes where name = 'MANIKA' limit 1)
      ),
      (
        (select id from public.communes where name = 'Katuba' limit 1),
        (select id from public.communes where name = 'FUNGURUME' limit 1)
      ),
      (
        (select id from public.communes where name = 'Ruashi' limit 1),
        (select id from public.communes where name = 'AUTRE' limit 1)
      ),
      (
        (select id from public.communes where name = 'Kenya' limit 1),
        (select id from public.communes where name = 'AUTRE' limit 1)
      )
    ) as commune_mapping(source_id, target_id)
  loop
    if source_id is not null and target_id is not null and source_id <> target_id then
      update public.profiles set commune_id = target_id where commune_id = source_id;
      update public.collections set commune_id = target_id where commune_id = source_id;

      if to_regclass('public.alerts') is not null then
        update public.alerts set commune_id = target_id where commune_id = source_id;
      end if;

      delete from public.communes where id = source_id;
    end if;
  end loop;

  select id into autre_id from public.communes where name = 'AUTRE' limit 1;

  if autre_id is not null then
    for stale_id in
      select id
      from public.communes
      where name not in ('DILALA', 'MANIKA', 'FUNGURUME', 'AUTRE')
    loop
      update public.profiles set commune_id = autre_id where commune_id = stale_id;
      update public.collections set commune_id = autre_id where commune_id = stale_id;

      if to_regclass('public.alerts') is not null then
        update public.alerts set commune_id = autre_id where commune_id = stale_id;
      end if;

      delete from public.communes where id = stale_id;
    end loop;
  end if;
end $$;
