-- ============================================================
-- 居酒屋メニューアプリ レシピ(調理方法)機能 テーブル＋写真置き場
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ============================================================

-- ① レシピ本体 -------------------------------------------------
create table if not exists inv_recipes (
  id         uuid primary key default gen_random_uuid(),
  name       text        not null,               -- メニュー名
  yomi       text        not null default '',     -- よみがな（あいうえお順の並べ替え用）
  steps      text        not null default '',     -- 調理手順（湯せん◯分/揚げ◯分など・改行OK）
  seasoning  text        not null default '',     -- 調味料
  garnish    text        not null default '',     -- 添える食材・盛り付け
  hero_url   text        not null default '',     -- 完成写真URL
  photos     jsonb       not null default '[]'::jsonb, -- 過程写真 [{url,caption}]
  sort_order int         not null default 0,       -- 手動並べ替え用
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table inv_recipes enable row level security;
drop policy if exists "inv_recipe_all" on inv_recipes;
create policy "inv_recipe_all" on inv_recipes for all using (true) with check (true);

do $$
begin
  begin alter publication supabase_realtime add table inv_recipes; exception when duplicate_object then null; end;
end $$;

-- ② 写真置き場（Storageバケット・公開）--------------------------
insert into storage.buckets (id, name, public)
values ('recipe-photos', 'recipe-photos', true)
on conflict (id) do nothing;

-- 写真の読み書き許可（このバケット限定）
drop policy if exists "recipe_photo_read"   on storage.objects;
drop policy if exists "recipe_photo_insert" on storage.objects;
drop policy if exists "recipe_photo_update" on storage.objects;
drop policy if exists "recipe_photo_delete" on storage.objects;
create policy "recipe_photo_read"   on storage.objects for select using (bucket_id = 'recipe-photos');
create policy "recipe_photo_insert" on storage.objects for insert with check (bucket_id = 'recipe-photos');
create policy "recipe_photo_update" on storage.objects for update using (bucket_id = 'recipe-photos');
create policy "recipe_photo_delete" on storage.objects for delete using (bucket_id = 'recipe-photos');

-- 完了。アプリに「📖 レシピ」タブが使えるようになります。
