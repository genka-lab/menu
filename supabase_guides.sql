-- ============================================================
-- 居酒屋メニューアプリ 「業務・マニュアル」機能 テーブル
-- 掃除 / オープン準備 / 閉店作業 / ホール / キッチン / カウンター を
-- 写真つきの手順・注意事項として全端末で共有します。
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ============================================================

create table if not exists inv_guides (
  id         uuid primary key default gen_random_uuid(),
  category   text        not null default 'clean',  -- clean/open/close/hall/kitchen/counter
  title      text        not null default '',       -- 作業名・項目名
  body       text        not null default '',       -- 内容・手順・注意事項（改行OK）
  photos     jsonb       not null default '[]',      -- [{url, caption}, ...]（Storage: recipe-photos）
  sort_order int         not null default 0,         -- 手動並べ替え用
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table inv_guides enable row level security;
do $$ begin
  create policy "inv_guides_all" on inv_guides for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_guides;
exception when duplicate_object then null; end $$;

-- 完了。アプリの「業務」タブが全端末で共有されるようになります。
