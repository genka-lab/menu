-- ============================================================
-- 居酒屋メニューアプリ メニュー(原価計算)機能 テーブル
-- これを実行すると「メニュー」タブが全端末で共有されるようになります。
-- 実行方法: Supabase → SQL Editor に貼り付けて Run（一度だけ）
-- ============================================================

create table if not exists inv_menus (
  id         uuid primary key default gen_random_uuid(),
  menu       text        not null default '',          -- メニュー名
  price      numeric     not null default 0,            -- 売価(税込)
  ings       jsonb       not null default '[]'::jsonb,  -- 食材配列 [{food,cost,taxrate,qty,unit,use,mode,direct,dtax}]
  sort_order int         not null default 0,            -- 手動並べ替え用
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table inv_menus enable row level security;
drop policy if exists "inv_menu_all" on inv_menus;
create policy "inv_menu_all" on inv_menus for all using (true) with check (true);

do $$
begin
  begin alter publication supabase_realtime add table inv_menus; exception when duplicate_object then null; end;
end $$;

-- 完了。アプリの「メニュー」タブが全端末で共有されるようになります。
