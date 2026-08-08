-- ============================================================
-- 居酒屋メニューアプリ 「📝発注リスト」発注品マスター テーブル
-- 発注タブに並ぶ品を自分たちで登録して全端末で共有します。
-- （在庫タブとは独立。在庫数とは結び付けません）
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ============================================================

create table if not exists inv_order_items (
  id         uuid primary key default gen_random_uuid(),
  name       text        not null default '',   -- 品名（例：鶏もも肉）
  unit_name  text        not null default '',   -- 数え方（例：箱・kg・パック。空でもOK）
  note       text        not null default '',   -- メモ（例：〇〇商店／週2回）
  sort_order int         not null default 0,    -- 並び順
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table inv_order_items enable row level security;
do $$ begin
  create policy "inv_order_items_all" on inv_order_items for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_order_items;
exception when duplicate_object then null; end $$;

-- 完了。アプリの「📝発注」タブで発注品を登録できるようになります。
