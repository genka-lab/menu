-- ============================================================
-- Izakaya app : Google review reply maker
--   inv_reviews       : reviews + reply drafts + status
--   inv_reply_samples : past reply examples (AI few-shot)
-- How to run: Supabase -> SQL Editor -> paste all -> Run (once)
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

do $$ begin
  create policy "inv_reviews_all" on inv_reviews for all using (true) with check (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "inv_reply_samples_all" on inv_reply_samples for all using (true) with check (true);
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table inv_reviews;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table inv_reply_samples;
exception when duplicate_object then null; end $$;

-- done. The "review" tab of the app will be shared across devices.
