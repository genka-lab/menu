-- ============================================================
-- 居酒屋メニューアプリ 「ポーション（小分け）」機能 テーブル
-- 食材・料理の小分け方法（g・個数など）を全端末で共有します。
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ============================================================

create table if not exists inv_portions (
  id         uuid primary key default gen_random_uuid(),
  name       text        not null default '',   -- 品名（食材 or 料理）
  kind       text        not null default '食材', -- 種別：食材 / 料理
  from_amt   text        not null default '',    -- 元の量（例：1kg・1パック・1本）
  to_amt     text        not null default '',    -- 小分け後（例：100g×10袋・8個・4切れ）
  note       text        not null default '',    -- やり方・コツ・メモ（改行OK）
  hero_url   text        not null default '',    -- 完成写真URL（Storage: recipe-photos）
  sort_order int         not null default 0,     -- 手動並べ替え用
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- 既存テーブルに後から写真列を足す場合もこの1行でOK（何度実行しても安全）
alter table inv_portions add column if not exists hero_url text not null default '';

alter table inv_portions enable row level security;
do $$ begin
  create policy "inv_portions_all" on inv_portions for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_portions;
exception when duplicate_object then null; end $$;

-- 完了。アプリの「小分け」タブが全端末で共有されるようになります。
