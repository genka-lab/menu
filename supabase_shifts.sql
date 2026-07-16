-- ============================================================
-- Izakaya app : Shift ("shift") feature
--
-- Same rules as the reservation feature:
--   1) Staff can read ONLY today's shift, and ONLY from 16:00 JST.
--      Before 16:00, the rows are not sent to the app at all (RLS).
--   2) Staff cannot add / edit / delete. Only the owner (Kurihara) can,
--      by sending the owner password to the functions below.
--
-- The owner password is SHARED with the reservation feature:
--   it reuses private.res_owner_pass(), so Kurihara has ONE password
--   for both "予約" and "シフト".
--   -> You MUST have already run supabase_reservations.sql
--      (and the _fix_owner_pass one) before running this file.
--
-- How to run: Supabase -> SQL Editor -> paste -> Run (once)
-- ============================================================

create table if not exists inv_shifts (
  id         uuid        primary key default gen_random_uuid(),
  work_on    date        not null,                 -- date of the shift
  staff_name text        not null default '',      -- who works
  start_at   text        not null default '',      -- from what time, e.g. 17:00
  end_at     text        not null default '',      -- until (optional)
  note       text        not null default '',      -- free memo (optional, e.g. ホール/キッチン)
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists inv_shifts_on_idx on inv_shifts(work_on);

alter table inv_shifts enable row level security;

-- Read policy for everyone using the app key (= staff).
-- Today only, and only after 16:00 Japan time. Nothing else is readable.
do $$ begin
  create policy "inv_shifts_today_after16" on inv_shifts
    for select using (
      work_on = (now() at time zone 'Asia/Tokyo')::date
      and (now() at time zone 'Asia/Tokyo')::time >= time '16:00'
    );
exception when duplicate_object then null; end $$;

-- No insert / update / delete policy on purpose:
-- the app key can never write to this table directly.

do $$ begin
  alter publication supabase_realtime add table inv_shifts;
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- Owner (Kurihara): read every shift (any date, any time of day).
-- Reuses the shared owner password in private.res_owner_pass().
-- ------------------------------------------------------------
create or replace function sft_list(p_pass text)
returns setof inv_shifts
language plpgsql security definer set search_path = public as $$
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);           -- slow down password guessing
    raise exception 'password_ng';
  end if;
  return query
    select * from inv_shifts
    order by work_on desc, start_at asc, created_at asc;
end $$;

-- ------------------------------------------------------------
-- Owner: add (p_id null) or edit (p_id given) a shift
-- ------------------------------------------------------------
create or replace function sft_save(
  p_pass  text,
  p_id    uuid,
  p_on    date,
  p_name  text,
  p_start text,
  p_end   text,
  p_note  text
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
    insert into inv_shifts(work_on,staff_name,start_at,end_at,note)
    values(p_on,coalesce(p_name,''),coalesce(p_start,''),coalesce(p_end,''),coalesce(p_note,''))
    returning id into v_id;
  else
    update inv_shifts set
      work_on=p_on, staff_name=coalesce(p_name,''), start_at=coalesce(p_start,''),
      end_at=coalesce(p_end,''), note=coalesce(p_note,''), updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- ------------------------------------------------------------
-- Owner: delete a shift
-- ------------------------------------------------------------
create or replace function sft_delete(p_pass text, p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);
    raise exception 'password_ng';
  end if;
  delete from inv_shifts where id=p_id;
end $$;

-- Done. The app's "シフト" tab shows today's roster from 16:00 JST,
-- and the owner (Kurihara) unlocks full access with the shared password.
