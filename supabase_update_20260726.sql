-- ============================================================
-- 居酒屋メニューアプリ 2026-07-26 機能追加 まとめSQL
--   ① レシピに「フード / ドリンク」種別
--   ② 小分けの写真を複数枚に
--   ③ 掃除/オープン準備/閉店作業/ゴミ分別のチェック項目
--      ＋ 共有チェック表（誰がいつチェックしたか・毎日リセット）
--   ④ シフトに「役割」（ホール/キッチン等）
--   ⑤ 設備清掃（ビールサーバー/フライヤー）の週次アラームの記録先
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ※ 何度実行しても安全な書き方にしてあります
-- ============================================================

-- ① レシピ：フード / ドリンク種別（既存レシピは全部フード扱いになります）
alter table inv_recipes add column if not exists rtype text not null default 'food';

-- ② 小分け：複数写真 [{url, caption}, ...]
alter table inv_portions add column if not exists photos jsonb not null default '[]'::jsonb;

-- ③ 業務・ゴミ分別：チェック項目（["床のモップがけ", ...] のような文字列の配列）
alter table inv_guides  add column if not exists checklist jsonb not null default '[]'::jsonb;
alter table inv_garbage add column if not exists checklist jsonb not null default '[]'::jsonb;

-- ③' 共有チェック表：その日に誰がチェックしたかを全端末で共有
--     source: guide:<id> ／ garbage:<曜日0-6> ／ machine:<id>（設備清掃）
create table if not exists inv_checks (
  id         uuid primary key default gen_random_uuid(),
  check_on   date not null,                    -- チェックした日（毎日リセットの単位）
  source     text not null,
  item_idx   int  not null default 0,
  label      text not null default '',
  who        text not null default '',
  created_at timestamptz not null default now(),
  unique(check_on, source, item_idx)
);
create index if not exists inv_checks_on_idx on inv_checks(check_on);
alter table inv_checks enable row level security;
do $$ begin
  create policy "inv_checks_all" on inv_checks for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table inv_checks;
exception when duplicate_object then null; end $$;

-- ④ シフト：役割（ホール/キッチン/カウンター等）
alter table inv_shifts add column if not exists role text not null default '';

-- 旧バージョンの sft_save（役割なし・7引数）を新バージョン（8引数）に置き換え
drop function if exists sft_save(text,uuid,date,text,text,text,text);
create or replace function sft_save(
  p_pass  text,
  p_id    uuid,
  p_on    date,
  p_name  text,
  p_start text,
  p_end   text,
  p_note  text,
  p_role  text
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
    insert into inv_shifts(work_on,staff_name,start_at,end_at,note,role)
    values(p_on,coalesce(p_name,''),coalesce(p_start,''),coalesce(p_end,''),coalesce(p_note,''),coalesce(p_role,''))
    returning id into v_id;
  else
    update inv_shifts set
      work_on=p_on, staff_name=coalesce(p_name,''), start_at=coalesce(p_start,''),
      end_at=coalesce(p_end,''), note=coalesce(p_note,''), role=coalesce(p_role,''), updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- ⑤ 設備清掃は追加のテーブル不要（inv_guides の category='machine' と inv_checks を使います）
-- 完了。実行後にアプリを再読み込みしてください。
