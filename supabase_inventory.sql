-- ============================================================
-- 居酒屋メニューアプリ 在庫管理 テーブル定義
-- 実行方法: Supabaseダッシュボード → SQL Editor に貼り付けて Run
--   プロジェクト: awnqgypevtgfgbplphrc (シフトアプリと共用)
-- 一度だけ実行すればOK。2回実行しても壊れないよう if not exists 等を使用。
-- ============================================================

-- ① 食材マスタ（＝在庫リスト）。小分けパック数で管理 -------------
create table if not exists inv_ingredients (
  id          uuid primary key default gen_random_uuid(),
  name        text        not null,                 -- 食材名 例:鶏もも肉
  portion_label text      not null default '',      -- 小分けの中身の目安 例:「150g」「1本」
  unit_name   text        not null default 'パック',-- 数え方の呼称 パック/個/本 など
  stock       numeric     not null default 0,       -- 現在の在庫（小分けの数）
  yellow_at   numeric     not null default 5,       -- この数以下で🟡要注意
  red_at      numeric     not null default 2,       -- この数以下で🔴発注
  note        text        not null default '',
  sort_order  int         not null default 0,
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

-- ② 在庫変動ログ（誰がいつ何をしたか＝みんなで管理の透明性）------
create table if not exists inv_logs (
  id            uuid primary key default gen_random_uuid(),
  ingredient_id uuid references inv_ingredients(id) on delete set null,
  ingredient_name text     not null default '',     -- 履歴用に名前も保存
  kind          text       not null default 'use',  -- in(仕入) / use(使用) / adjust(棚卸補正) / new / delete
  delta         numeric    not null default 0,       -- +6 / -1 など
  stock_after   numeric,                             -- 操作後の残数
  who           text       not null default '',      -- 操作した人の名前
  memo          text       not null default '',
  created_at    timestamptz not null default now()
);

create index if not exists inv_logs_created_idx on inv_logs (created_at desc);

-- ③ 原子的に在庫を増減するRPC -----------------------------------
--    2人が同時に「−1」しても数がズレない（サーバ側で加算するため）
create or replace function inv_apply_delta(
  p_id uuid, p_delta numeric, p_kind text, p_who text, p_memo text
) returns numeric
language plpgsql
as $$
declare v_after numeric; v_name text;
begin
  update inv_ingredients
     set stock = stock + p_delta, updated_at = now()
   where id = p_id
   returning stock, name into v_after, v_name;

  insert into inv_logs(ingredient_id, ingredient_name, kind, delta, stock_after, who, memo)
  values (p_id, coalesce(v_name,''), p_kind, p_delta, v_after, p_who, p_memo);

  return v_after;
end;
$$;

-- ④ アクセス許可（アプリ側の合言葉ロックで来店者を制限）----------
--    publishable(anon)キーでの読み書きを許可。小規模在庫のため簡易設定。
alter table inv_ingredients enable row level security;
alter table inv_logs        enable row level security;

drop policy if exists "inv_ing_all" on inv_ingredients;
create policy "inv_ing_all" on inv_ingredients for all using (true) with check (true);

drop policy if exists "inv_log_all" on inv_logs;
create policy "inv_log_all" on inv_logs for all using (true) with check (true);

grant execute on function inv_apply_delta(uuid, numeric, text, text, text) to anon, authenticated;

-- ⑤ リアルタイム同期を有効化（他の人の変更が即反映）--------------
do $$
begin
  begin
    alter publication supabase_realtime add table inv_ingredients;
  exception when duplicate_object then null; end;
  begin
    alter publication supabase_realtime add table inv_logs;
  exception when duplicate_object then null; end;
end $$;

-- 完了。アプリを開くと在庫タブが使えるようになります。
