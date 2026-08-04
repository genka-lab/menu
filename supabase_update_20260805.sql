-- ============================================================
-- 居酒屋メニューアプリ 2026-08-05 更新用SQL
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
--   https://supabase.com/dashboard/project/awnqgypevtgfgbplphrc/sql/new
--
-- ① メニュー: 「1人前の量(g)」の手動入力
--    個数もの・直接入力の食材でg計算できないメニューに、
--    自分で総量を入れられるようにする（コースの1人あたり量が正確になる）
-- ② レシピ: カテゴリー分け
--    フード=揚げ物/おつまみ/〆/デザート/サラダ/ポテト
--    ドリンク=ビール/ワイン/焼酎/ウイスキー/日本酒/カクテル/果実酒/サワー/ソフトドリンク/ノンアルコール
-- ============================================================

-- ① メニューに手動グラム数（0=未設定・自動計算）
alter table inv_menus add column if not exists manual_g numeric not null default 0;

-- ② レシピにカテゴリー（''=未分類）
alter table inv_recipes add column if not exists category text not null default '';

-- 完了。アプリをリロードすると
-- ・メニュー編集に「1人前の量（g）を手動で入力」欄
-- ・レシピ一覧にカテゴリーの絞り込みチップ
-- が使えるようになります。
