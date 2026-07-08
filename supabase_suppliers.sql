-- ============================================================
-- 居酒屋メニューアプリ 「取引先業者」機能 テーブル
-- 会社名・電話・営業時間・発注方法などを全端末で共有します。
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ============================================================

create table if not exists inv_suppliers (
  id         uuid primary key default gen_random_uuid(),
  name       text        not null default '',   -- 会社名・業者名
  phone      text        not null default '',   -- 電話番号
  hours      text        not null default '',   -- 営業時間（例：平日9:00-18:00 日祝休）
  order_way  text        not null default '',   -- 発注方法（電話/FAX/LINE/Webなど・改行OK）
  contact    text        not null default '',   -- 担当者名
  items      text        not null default '',   -- 取扱品目（例：鮮魚・野菜）
  note       text        not null default '',   -- メモ（最低ロット・締め時間など）
  sort_order int         not null default 0,     -- 手動並べ替え用
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table inv_suppliers enable row level security;
do $$ begin
  create policy "inv_suppliers_all" on inv_suppliers for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_suppliers;
exception when duplicate_object then null; end $$;

-- 完了。アプリの「取引先」タブが全端末で共有されるようになります。
