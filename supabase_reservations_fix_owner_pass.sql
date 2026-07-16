-- ============================================================
-- SECURITY FIX for the reservation feature (run once, after
-- supabase_reservations.sql has already been run).
--
-- Problem:
--   public.res_owner_pass() was callable with the app's public key,
--   so anyone could read the owner password in plain text.
--   Supabase grants EXECUTE on new public functions to the anon role
--   by default, so "revoke ... from public" was not enough.
--
-- Fix:
--   Move the password into the "private" schema. PostgREST only exposes
--   the "public" schema, so the app key cannot reach it at all.
--
-- !! SET YOUR NEW OWNER PASSWORD on the marked line below !!
--    (the old one should be considered leaked)
-- ============================================================

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- >>> CHANGE THE PASSWORD HERE <<<
create or replace function private.res_owner_pass() returns text
language sql immutable as $$
  select 'CHANGE_ME'::text
$$;
revoke all on function private.res_owner_pass() from public, anon, authenticated;

-- Point the owner-only functions at the new location.
create or replace function res_list(p_pass text)
returns setof inv_reservations
language plpgsql security definer set search_path = public as $$
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);
    raise exception 'password_ng';
  end if;
  return query
    select * from inv_reservations
    order by reserve_on desc, start_at asc, created_at asc;
end $$;

create or replace function res_save(
  p_pass   text,
  p_id     uuid,
  p_on     date,
  p_start  text,
  p_name   text,
  p_people int,
  p_seat   text,
  p_course text,
  p_phone  text,
  p_note   text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);
    raise exception 'password_ng';
  end if;
  if p_on is null then
    raise exception 'date_required';
  end if;
  if p_id is null then
    insert into inv_reservations(reserve_on,start_at,guest_name,people,seat,course,phone,note)
    values(p_on,coalesce(p_start,''),coalesce(p_name,''),coalesce(p_people,0),
           coalesce(p_seat,''),coalesce(p_course,''),coalesce(p_phone,''),coalesce(p_note,''))
    returning id into v_id;
  else
    update inv_reservations set
      reserve_on=p_on, start_at=coalesce(p_start,''), guest_name=coalesce(p_name,''),
      people=coalesce(p_people,0), seat=coalesce(p_seat,''), course=coalesce(p_course,''),
      phone=coalesce(p_phone,''), note=coalesce(p_note,''), updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function res_delete(p_pass text, p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);
    raise exception 'password_ng';
  end if;
  delete from inv_reservations where id=p_id;
end $$;

-- Finally remove the exposed one.
drop function if exists public.res_owner_pass();

-- Done. public.res_owner_pass no longer exists; the password is only
-- reachable from inside the security definer functions above.
