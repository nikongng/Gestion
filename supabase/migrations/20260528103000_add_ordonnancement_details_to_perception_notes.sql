alter table public.perception_notes
  add column if not exists bank_name text,
  add column if not exists receiver_account text,
  add column if not exists declarant_name text,
  add column if not exists declarant_phone text,
  add column if not exists declarant_email text,
  add column if not exists cdf_rate numeric(14, 4);
