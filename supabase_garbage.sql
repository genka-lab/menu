-- ============================================================
-- 居酒屋メニューアプリ 「ゴミ分別」機能 テーブル
-- 何曜日に何のゴミが出せるかを全端末で共有します。
-- day: 0=日, 1=月, 2=火, 3=水, 4=木, 5=金, 6=土
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ============================================================

create table if not exists inv_garbage (
  id         uuid primary key default gen_random_uuid(),
  day        int         not null default 0 unique,  -- 0=日 … 6=土（各曜日1行）
  types      text        not null default '',         -- 出せるゴミ（例：燃えるゴミ・生ゴミ）
  note       text        not null default '',         -- メモ（時間・場所など）
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table inv_garbage enable row level security;
do $$ begin
  create policy "inv_garbage_all" on inv_garbage for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_garbage;
exception when duplicate_object then null; end $$;

-- 完了。アプリを開くと7曜日ぶんの行が自動で用意されます。
