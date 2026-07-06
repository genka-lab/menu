-- ============================================================
-- 居酒屋メニューアプリ 在庫管理【ロット（仕入れの束）管理】追加
--   1つの食材を「仕入日ごとのロット」に分けて管理し、古い順（先入れ先出し）で使う。
-- 実行方法: Supabaseダッシュボード → SQL Editor に貼り付けて Run
--   プロジェクト: awnqgypevtgfgbplphrc
--   1回だけ実行すればOK。既存の在庫は自動で1つのロットに移行されます。何度実行しても壊れません。
-- ============================================================

-- ① 念のため ordered_on 列（移行元に使う。無ければ足す）--------------
alter table inv_ingredients add column if not exists ordered_on date;

-- ② ロットテーブル（食材ぶら下がりの仕入れ束）-----------------------
create table if not exists inv_lots (
  id            uuid primary key default gen_random_uuid(),
  ingredient_id uuid not null references inv_ingredients(id) on delete cascade,
  qty           numeric     not null default 0,     -- このロットの残数
  ordered_on    date,                               -- 仕入日（発注した日）
  created_at    timestamptz not null default now()
);
create index if not exists inv_lots_ing_idx   on inv_lots (ingredient_id);
create index if not exists inv_lots_order_idx on inv_lots (ingredient_id, ordered_on asc, created_at asc);

-- ③ 既存在庫を1ロットに移行（stock>0 でまだロットが無い食材だけ）------
insert into inv_lots (ingredient_id, qty, ordered_on)
select id, stock, coalesce(ordered_on, current_date)
from inv_ingredients g
where g.stock > 0
  and not exists (select 1 from inv_lots l where l.ingredient_id = g.id);

-- ④ 在庫合計を再計算（stock列はロット合計のキャッシュとして保持）-----
create or replace function inv_recalc(p_ing uuid) returns numeric
language plpgsql as $$
declare v numeric;
begin
  select coalesce(sum(qty),0) into v from inv_lots where ingredient_id=p_ing;
  update inv_ingredients set stock=v, updated_at=now() where id=p_ing;
  return v;
end; $$;

-- ⑤ ロット追加（＝仕入れ。新しい束を今日の日付などで足す）------------
create or replace function inv_add_lot(p_ing uuid, p_qty numeric, p_date date, p_who text)
returns numeric language plpgsql as $$
declare v numeric; nm text;
begin
  insert into inv_lots(ingredient_id, qty, ordered_on)
  values (p_ing, p_qty, coalesce(p_date, current_date));
  select inv_recalc(p_ing) into v;
  select name into nm from inv_ingredients where id=p_ing;
  insert into inv_logs(ingredient_id,ingredient_name,kind,delta,stock_after,who,memo)
  values (p_ing, coalesce(nm,''),'in',p_qty,v,coalesce(p_who,''),'仕入れ（ロット追加）');
  return v;
end; $$;

-- ⑥ 古い順（先入れ先出し）で数量を消費 -------------------------------
create or replace function inv_consume_fifo(p_ing uuid, p_qty numeric, p_who text)
returns numeric language plpgsql as $$
declare need numeric; take numeric; r record; v numeric; nm text;
begin
  need := p_qty;
  for r in select id, qty from inv_lots
           where ingredient_id=p_ing and qty>0
           order by ordered_on asc nulls first, created_at asc loop
    exit when need<=0;
    take := least(need, r.qty);
    update inv_lots set qty=qty-take where id=r.id;
    need := need - take;
  end loop;
  delete from inv_lots where ingredient_id=p_ing and qty<=0;
  select inv_recalc(p_ing) into v;
  select name into nm from inv_ingredients where id=p_ing;
  insert into inv_logs(ingredient_id,ingredient_name,kind,delta,stock_after,who,memo)
  values (p_ing, coalesce(nm,''),'use',-(p_qty-need),v,coalesce(p_who,''),'古い順から使用');
  return v;
end; $$;

-- ⑦ 特定のロットから消費（各ロットの「−」ボタン用）------------------
create or replace function inv_consume_lot(p_lot uuid, p_qty numeric, p_who text)
returns numeric language plpgsql as $$
declare v numeric; ing uuid; nm text; take numeric; cur numeric;
begin
  select ingredient_id, qty into ing, cur from inv_lots where id=p_lot;
  if ing is null then return null; end if;
  take := least(p_qty, cur);
  update inv_lots set qty=qty-take where id=p_lot;
  delete from inv_lots where id=p_lot and qty<=0;
  select inv_recalc(ing) into v;
  select name into nm from inv_ingredients where id=ing;
  insert into inv_logs(ingredient_id,ingredient_name,kind,delta,stock_after,who,memo)
  values (ing, coalesce(nm,''),'use',-take,v,coalesce(p_who,''),'ロットから使用');
  return v;
end; $$;

-- ⑧ ロットを直接訂正（数量・日付の修正。qty<=0 なら削除）------------
create or replace function inv_edit_lot(p_lot uuid, p_qty numeric, p_date date, p_who text)
returns numeric language plpgsql as $$
declare v numeric; ing uuid; nm text;
begin
  select ingredient_id into ing from inv_lots where id=p_lot;
  if ing is null then return null; end if;
  if p_qty<=0 then
    delete from inv_lots where id=p_lot;
  else
    update inv_lots set qty=p_qty, ordered_on=coalesce(p_date,current_date) where id=p_lot;
  end if;
  select inv_recalc(ing) into v;
  select name into nm from inv_ingredients where id=ing;
  insert into inv_logs(ingredient_id,ingredient_name,kind,delta,stock_after,who,memo)
  values (ing, coalesce(nm,''),'adjust',0,v,coalesce(p_who,''),'ロットを訂正');
  return v;
end; $$;

-- ⑨ アクセス許可 ＆ リアルタイム同期 --------------------------------
alter table inv_lots enable row level security;
drop policy if exists "inv_lot_all" on inv_lots;
create policy "inv_lot_all" on inv_lots for all using (true) with check (true);

grant execute on function inv_recalc(uuid)                        to anon, authenticated;
grant execute on function inv_add_lot(uuid,numeric,date,text)     to anon, authenticated;
grant execute on function inv_consume_fifo(uuid,numeric,text)     to anon, authenticated;
grant execute on function inv_consume_lot(uuid,numeric,text)      to anon, authenticated;
grant execute on function inv_edit_lot(uuid,numeric,date,text)    to anon, authenticated;

do $$ begin
  begin alter publication supabase_realtime add table inv_lots;
  exception when duplicate_object then null; end;
end $$;

-- 完了。アプリで「＋仕入れた」を押すたびに新しいロット（仕入日つき）が増えます。
