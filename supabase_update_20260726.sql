-- ============================================================
-- Izakaya app update 2026-07-26 (safe to run multiple times)
--  (1) recipes: food / drink type
--  (2) portions: multiple photos
--  (3) guides + garbage: checklist items
--      + shared check table (who checked, resets daily)
--  (4) shifts: role (hall / kitchen etc.)
--  (5) weekly equipment cleaning uses (3)'s check table
--  (6) staff roster (pick names when adding a shift)
-- How to run: Supabase -> SQL Editor -> paste all -> Run (once)
-- ============================================================

-- (1) recipes: food / drink type (existing recipes become 'food')
alter table inv_recipes add column if not exists rtype text not null default 'food';

-- (2) portions: multiple photos [{url, caption}, ...]
alter table inv_portions add column if not exists photos jsonb not null default '[]'::jsonb;

-- (3) guides + garbage: checklist items (array of strings)
alter table inv_guides  add column if not exists checklist jsonb not null default '[]'::jsonb;
alter table inv_garbage add column if not exists checklist jsonb not null default '[]'::jsonb;

-- (3)+ machine cleaning cycle per equipment:
--      'weekly'  = every Sunday (Mon if the Sunday is a holiday)
--      'monthly' = mid-month Sunday (the Sunday between the 12th and 18th)
alter table inv_guides add column if not exists cycle text not null default 'weekly';

-- (3)' shared check table: who checked what, per day (shared by all devices)
--      source: guide:<id> / garbage:<0-6 weekday> / machine:<id>
create table if not exists inv_checks (
  id         uuid primary key default gen_random_uuid(),
  check_on   date not null,
  source     text not null,
  item_idx   int  not null default 0,
  label      text not null default '',
  who        text not null default '',
  created_at timestamptz not null default now(),
  unique(check_on, source, item_idx)
);
create index if not exists inv_checks_on_idx on inv_checks(check_on);
alter table inv_checks enable row level security;
do $$ begin
  create policy "inv_checks_all" on inv_checks for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_checks;
exception when duplicate_object then null; end $$;

-- (4) shifts: role column
alter table inv_shifts add column if not exists role text not null default '';

-- replace old sft_save (7 args, no role) with new one (8 args)
drop function if exists sft_save(text,uuid,date,text,text,text,text);
create or replace function sft_save(
  p_pass  text,
  p_id    uuid,
  p_on    date,
  p_name  text,
  p_start text,
  p_end   text,
  p_note  text,
  p_role  text
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
    insert into inv_shifts(work_on,staff_name,start_at,end_at,note,role)
    values(p_on,coalesce(p_name,''),coalesce(p_start,''),coalesce(p_end,''),coalesce(p_note,''),coalesce(p_role,''))
    returning id into v_id;
  else
    update inv_shifts set
      work_on=p_on, staff_name=coalesce(p_name,''), start_at=coalesce(p_start,''),
      end_at=coalesce(p_end,''), note=coalesce(p_note,''), role=coalesce(p_role,''), updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- (5) weekly equipment cleaning: no extra table needed
--     (uses inv_guides category='machine' and inv_checks)

-- (6) staff roster: everyone can read, only the owner can add/delete
--     (same owner password as reservations / shifts)
create table if not exists inv_staff (
  id         uuid primary key default gen_random_uuid(),
  name       text not null default '',
  created_at timestamptz not null default now()
);
alter table inv_staff enable row level security;
do $$ begin
  create policy "inv_staff_read" on inv_staff for select using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_staff;
exception when duplicate_object then null; end $$;

create or replace function stf_add(p_pass text, p_name text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);
    raise exception 'password_ng';
  end if;
  insert into inv_staff(name) values(coalesce(p_name,'')) returning id into v_id;
  return v_id;
end $$;

create or replace function stf_delete(p_pass text, p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);
    raise exception 'password_ng';
  end if;
  delete from inv_staff where id=p_id;
end $$;

-- Done. Reload the app after running this.
