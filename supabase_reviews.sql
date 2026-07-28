-- ============================================================
-- Izakaya app : Google review reply maker (OWNER ONLY)
--   inv_reviews       : reviews + reply drafts + status
--   inv_reply_samples : past reply examples (AI few-shot)
--
-- Design = same as reservations/shifts:
--   * RLS enabled with NO policies -> app publishable key cannot
--     read/write the tables at all (staff devices see nothing)
--   * all operations go through SECURITY DEFINER RPCs that check
--     the owner password stored in private.res_owner_pass()
--     (same password as reservations/shifts)
--
-- PREREQUISITE: supabase_reservations.sql and
--   supabase_reservations_fix_owner_pass.sql already executed
--   (private.res_owner_pass() must exist)
--
-- How to run: Supabase -> SQL Editor -> paste all -> Run (once)
-- Safe to re-run. Also removes the old open policies if the
-- previous version of this file was executed.
-- ============================================================

create table if not exists inv_reviews (
  id          uuid primary key default gen_random_uuid(),
  author      text not null default '',   -- reviewer name
  rating      int  not null default 5,    -- 1..5 stars
  review_on   date,                       -- review date (optional)
  body        text not null default '',   -- review text
  reply_draft text not null default '',   -- generated / edited draft
  reply_final text not null default '',   -- approved reply
  status      text not null default 'new',-- new / draft / approved / posted
  engine      text not null default '',   -- ai / tpl
  posted_at   timestamptz,
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

create table if not exists inv_reply_samples (
  id          uuid primary key default gen_random_uuid(),
  review_body text not null default '',   -- customer's review
  reply_body  text not null default '',   -- the shop's actual reply
  note        text not null default '',
  created_at  timestamptz not null default now()
);

alter table inv_reviews enable row level security;
alter table inv_reply_samples enable row level security;

-- remove open policies from the old version of this file (if any)
do $$ begin
  execute 'drop policy "inv_reviews_all" on inv_reviews';
exception when undefined_object then null; end $$;
do $$ begin
  execute 'drop policy "inv_reply_samples_all" on inv_reply_samples';
exception when undefined_object then null; end $$;

-- remove from realtime publication (RLS hides rows anyway; keep it clean)
do $$ begin
  execute 'alter publication supabase_realtime drop table inv_reviews';
exception when undefined_object then null; end $$;
do $$ begin
  execute 'alter publication supabase_realtime drop table inv_reply_samples';
exception when undefined_object then null; end $$;

-- ---------- owner RPCs (password checked inside) ----------

create or replace function rvw_check(p_pass text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);  -- brute force slowdown
    raise exception 'password_ng';
  end if;
end $$;

create or replace function rvw_list(p_pass text)
returns setof inv_reviews
language plpgsql security definer set search_path = public as $$
begin
  perform rvw_check(p_pass);
  return query select * from inv_reviews order by created_at desc;
end $$;

create or replace function rvw_samples(p_pass text)
returns setof inv_reply_samples
language plpgsql security definer set search_path = public as $$
begin
  perform rvw_check(p_pass);
  return query select * from inv_reply_samples order by created_at desc;
end $$;

create or replace function rvw_save(
  p_pass text, p_id uuid, p_author text, p_rating int, p_on date, p_body text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform rvw_check(p_pass);
  if p_id is null then
    insert into inv_reviews(author, rating, review_on, body, status)
      values (coalesce(p_author,''), coalesce(p_rating,5), p_on, coalesce(p_body,''), 'new')
      returning id into v_id;
    return v_id;
  else
    update inv_reviews set
      author = coalesce(p_author, author),
      rating = coalesce(p_rating, rating),
      review_on = p_on,
      body = coalesce(p_body, body),
      updated_at = now()
    where id = p_id;
    return p_id;
  end if;
end $$;

create or replace function rvw_reply(
  p_pass text, p_id uuid, p_draft text, p_final text, p_status text, p_engine text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rvw_check(p_pass);
  update inv_reviews set
    reply_draft = coalesce(p_draft, reply_draft),
    reply_final = coalesce(p_final, reply_final),
    status      = coalesce(p_status, status),
    engine      = coalesce(p_engine, engine),
    posted_at   = case when p_status = 'posted' then now() else posted_at end,
    updated_at  = now()
  where id = p_id;
end $$;

create or replace function rvw_delete(p_pass text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rvw_check(p_pass);
  delete from inv_reviews where id = p_id;
end $$;

create or replace function rvw_sample_add(p_pass text, p_review text, p_reply text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform rvw_check(p_pass);
  insert into inv_reply_samples(review_body, reply_body)
    values (coalesce(p_review,''), coalesce(p_reply,''))
    returning id into v_id;
  return v_id;
end $$;

create or replace function rvw_sample_delete(p_pass text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rvw_check(p_pass);
  delete from inv_reply_samples where id = p_id;
end $$;

-- for the Edge Function (returns true/false instead of raising)
create or replace function rvw_pass_ok(p_pass text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_pass is distinct from private.res_owner_pass() then
    perform pg_sleep(1);
    return false;
  end if;
  return true;
end $$;

-- done. The review tab is now owner-only:
--   * tables are invisible to the app key (RLS, no policies)
--   * every RPC requires the owner password
