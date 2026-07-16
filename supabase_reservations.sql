-- ============================================================
-- Izakaya app : Reservation ("yoyaku") feature
--
-- Rules enforced on the SERVER (not just on screen):
--   1) Staff can read ONLY today's reservations, and ONLY from 16:00 JST.
--      Before 16:00, the rows are not sent to the app at all.
--   2) Staff cannot add / edit / delete. Only the owner can, by sending
--      the owner password to the functions below.
--
-- How to run: Supabase -> SQL Editor -> paste -> Run (once)
--
-- !! CHANGE THE OWNER PASSWORD !!
--    Edit the line  select 'yoyaku2026'::text  in private.res_owner_pass() below.
--    To change it later, just re-run that one function with a new value.
-- ============================================================

create table if not exists inv_reservations (
  id         uuid        primary key default gen_random_uuid(),
  reserve_on date        not null,                 -- date of the booking
  start_at   text        not null default '',      -- arrival time, e.g. 18:30
  guest_name text        not null default '',      -- guest name
  people     int         not null default 0,       -- number of guests
  seat       text        not null default '',      -- table / counter / zashiki
  course     text        not null default '',      -- course / nomihoudai
  phone      text        not null default '',      -- phone (tap to call)
  note       text        not null default '',      -- free memo (allergy etc)
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists inv_reservations_on_idx on inv_reservations(reserve_on);

alter table inv_reservations enable row level security;

-- Read policy for everyone using the app key (= staff).
-- Today only, and only after 16:00 Japan time. Nothing else is readable.
do $$ begin
  create policy "inv_reservations_today_after16" on inv_reservations
    for select using (
      reserve_on = (now() at time zone 'Asia/Tokyo')::date
      and (now() at time zone 'Asia/Tokyo')::time >= time '16:00'
    );
exception when duplicate_object then null; end $$;

-- No insert / update / delete policy on purpose:
-- the app key can never write to this table directly.

do $$ begin
  alter publication supabase_realtime add table inv_reservations;
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- Owner password.
-- It lives in the "private" schema on purpose: PostgREST only exposes
-- the "public" schema, so the app key has no way to call this function.
-- (Do NOT put it in public: Supabase grants execute on public functions
--  to the anon role by default, which would expose the password.)
-- ------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.res_owner_pass() returns text
language sql immutable as $$
  select 'yoyaku2026'::text
$$;
revoke all on function private.res_owner_pass() from public, anon, authenticated;

-- ------------------------------------------------------------
-- Owner: read every reservation (any date, any time of day)
-- ------------------------------------------------------------
create or replace function res_list(p_pass text)
returns setof inv_reservations
language plpgsql security definer set search_path = public as $$
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);           -- slow down password guessing
    raise exception 'password_ng';
  end if;
  return query
    select * from inv_reservations
    order by reserve_on desc, start_at asc, created_at asc;
end $$;

-- ------------------------------------------------------------
-- Owner: add (p_id null) or edit (p_id given) a reservation
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- Owner: delete a reservation
-- ------------------------------------------------------------
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

-- Done. The app's "yoyaku" tab shows today's list from 16:00 JST,
-- and the owner unlocks full access with the password above.
