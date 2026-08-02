-- ============================================================
-- Izakaya app : Shift "absence" (kekkin) feature  2026-08-02
--
-- What this adds:
--   * inv_shifts.absence column
--       ''            = works as planned (default)
--       other text    = absent. The text is the reason category,
--                       e.g. taichofuryo / kateinojijo / shiyo /
--                       mudan / sonota, or just "kekkin" (no reason).
--   * sft_save gets a 9th argument p_absence.
--     The old 8-argument version is dropped (same pattern as when
--     p_role was added).
--
-- Prerequisite: supabase_shifts.sql and supabase_reservations.sql
--               (+ _fix_owner_pass) already ran on this project.
--
-- How to run: Supabase -> SQL Editor -> paste -> Run (once)
-- ============================================================

alter table inv_shifts add column if not exists absence text not null default '';

-- drop the old 8-argument version so only the new one remains
drop function if exists sft_save(text,uuid,date,text,text,text,text,text);

create or replace function sft_save(
  p_pass    text,
  p_id      uuid,
  p_on      date,
  p_name    text,
  p_start   text,
  p_end     text,
  p_note    text,
  p_role    text,
  p_absence text
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
    insert into inv_shifts(work_on,staff_name,start_at,end_at,note,role,absence)
    values(p_on,coalesce(p_name,''),coalesce(p_start,''),coalesce(p_end,''),
           coalesce(p_note,''),coalesce(p_role,''),coalesce(p_absence,''))
    returning id into v_id;
  else
    update inv_shifts set
      work_on=p_on, staff_name=coalesce(p_name,''), start_at=coalesce(p_start,''),
      end_at=coalesce(p_end,''), note=coalesce(p_note,''), role=coalesce(p_role,''),
      absence=coalesce(p_absence,''), updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- Done. After this, the shift form's "kekkin" (absence) toggle
-- saves correctly, and absent staff show as crossed-out red cards.
