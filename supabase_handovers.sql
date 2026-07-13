-- ============================================================
-- 居酒屋メニューアプリ 「引き継ぎ連絡」機能 テーブル
-- 誰が / 誰宛てに / いつ / 何の引き継ぎか を写真つきで全端末に共有。
-- 対象者が「確認済」を押すまで、どのタブでも通知バーが出続けます。
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ============================================================

create table if not exists inv_handovers (
  id         uuid        primary key default gen_random_uuid(),
  from_name  text        not null default '',   -- 誰から（引き継ぐ人）
  to_name    text        not null default '',   -- 誰宛て（受け取る人・全員など）
  happen_on  date,                              -- 業務連絡の日付
  body       text        not null default '',   -- 業務連絡・引き継ぎ内容（改行OK）
  photos     jsonb       not null default '[]', -- [{url, caption}, ...]（Storage: recipe-photos）
  done       boolean     not null default false,-- 確認済みかどうか
  read_by    text        not null default '',   -- 確認した人の名前
  read_at    timestamptz,                       -- 確認した日時
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table inv_handovers enable row level security;
do $$ begin
  create policy "inv_handovers_all" on inv_handovers for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_handovers;
exception when duplicate_object then null; end $$;

-- 完了。アプリの「引き継ぎ」タブが全端末で共有され、未確認は通知バーで知らせます。
