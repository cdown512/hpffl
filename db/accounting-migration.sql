-- HPFFL Archives — League Accounting
-- Run after schema.sql / seed.sql. Safe to re-run.
--
-- SIGN CONVENTION, the thing to get right:
--   amount > 0  increases what the franchise owes the league  (dues, fees, contest entries)
--   amount < 0  decreases it                                  (payments in, prizes won, winnings paid out)
-- This matches the Google Sheet, where a positive BALANCE means the team owes.

begin;

-- ───────────────────────── name aliases ─────────────────────────
-- The accounting sheet spells several franchises differently. Every importer
-- resolves names through this table so a spelling variant can never silently
-- drop a row.

create table if not exists franchise_aliases (
  alias        text primary key,
  franchise_id uuid not null references franchises(id) on delete cascade
);

insert into franchise_aliases (alias, franchise_id)
select v.alias, f.id
  from (values
    ('CPTX Predator', 'Predator'),
    ('Thunder Cunt',  'Thundercunt'),
    ('Nyte Byrd',     'Nytebyrd'),
    ('Eight Ball',    'Eightball'),
    ('Train Wreck',   'Trainwreck')
  ) as v(alias, canonical)
  join franchises f on f.name = v.canonical
on conflict (alias) do update set franchise_id = excluded.franchise_id;

-- Every canonical name is its own alias, so lookups need only one table.
insert into franchise_aliases (alias, franchise_id)
select name, id from franchises
on conflict (alias) do nothing;

create or replace function franchise_by_alias(p_name text)
returns uuid language sql stable as $$
  select franchise_id from franchise_aliases
   where lower(btrim(alias)) = lower(btrim(p_name))
   limit 1;
$$;

-- ───────────────────────── fee schedule ─────────────────────────
-- Reference data: what things cost, dated so a rate change doesn't rewrite history.

create table if not exists league_fees (
  id             uuid primary key default gen_random_uuid(),
  kind           text not null,      -- matches ledger_entries.kind
  label          text not null,
  amount         numeric(9,2) not null,
  effective_from int not null default 1993,
  effective_to   int,                -- null = still current
  note           text,
  unique (kind, label, effective_from)
);

insert into league_fees (kind, label, amount, note) values
  ('dues',             'Franchise dues',            300, 'Per franchise per season. The commissioner (Paranoid Androids) is exempt.'),
  ('acq_fee',          'Player acquisition',          3, 'Per add.'),
  ('trade_fee',        'Trade',                       3, 'Per trade.'),
  ('weekly_prize',     'Weekly prize',               50, 'Two per week, weeks 1-14.'),
  ('playoff_prize',    '1st place',                1700, null),
  ('playoff_prize',    '2nd place',                 800, null),
  ('playoff_prize',    '3rd place',                 350, null),
  ('playoff_prize',    '4th place',                 150, null),
  ('side_game_entry',  'Off-season contest entry',  200, 'College Bowl Pickem, Super Bowl Squares, NFL Fantasy Playoffs, March Madness.')
on conflict (kind, label, effective_from) do update set
  amount = excluded.amount, note = excluded.note;

-- ───────────────────────── ledger ─────────────────────────
-- Widen the kind list and add the columns the sheet carries.

alter table ledger_entries
  add column if not exists week        int,
  add column if not exists description text,
  add column if not exists side_game   text,
  add column if not exists source      text;   -- 'sheet-import' | 'manual' | 'scrape'

alter table ledger_entries drop constraint if exists ledger_entries_kind_check;
alter table ledger_entries add constraint ledger_entries_kind_check
  check (kind in (
    'dues',               -- charged at season start
    'payment',            -- money in from the franchise (negative)
    'acq_fee',            -- player add
    'trade_fee',
    'weekly_prize',       -- won (negative)
    'playoff_prize',      -- won (negative)
    'side_game_entry',    -- off-season contest buy-in
    'side_game_winnings', -- off-season contest won (negative)
    'winnings_paid',      -- cash handed to the franchise (positive: clears what it is owed)
    'carryover',          -- opening balance for the first imported season only
    'adjustment',
    'other'
  ));

alter table ledger_entries drop constraint if exists ledger_entries_side_game_check;
alter table ledger_entries add constraint ledger_entries_side_game_check
  check (side_game is null or side_game in (
    'college_bowl_pickem','super_bowl_squares','nfl_fantasy_playoffs','march_madness','other'
  ));

create index if not exists ledger_year_franchise_idx on ledger_entries (year, franchise_id);
create index if not exists ledger_kind_idx on ledger_entries (kind);

-- ───────────────────────── views ─────────────────────────

-- One row per franchise per season, with the sheet's columns as sums by kind.
create or replace view v_accounting_season as
  select l.year,
         l.franchise_id,
         f.name as franchise,
         coalesce(sum(l.amount) filter (where l.kind = 'carryover'), 0)          as carryover,
         coalesce(sum(l.amount) filter (where l.kind = 'dues'), 0)               as dues,
         coalesce(-sum(l.amount) filter (where l.kind = 'payment'), 0)           as paid,
         coalesce(sum(l.amount) filter (where l.kind = 'acq_fee'), 0)            as acq_fees,
         coalesce(sum(l.amount) filter (where l.kind = 'trade_fee'), 0)          as trade_fees,
         coalesce(-sum(l.amount) filter (where l.kind = 'weekly_prize'), 0)      as weekly_prizes,
         coalesce(-sum(l.amount) filter (where l.kind = 'playoff_prize'), 0)     as playoff_prizes,
         coalesce(sum(l.amount) filter (where l.kind = 'side_game_entry'), 0)    as side_game_entries,
         coalesce(-sum(l.amount) filter (where l.kind = 'side_game_winnings'), 0) as side_game_winnings,
         coalesce(sum(l.amount) filter (where l.kind = 'winnings_paid'), 0)      as winnings_paid,
         coalesce(sum(l.amount) filter (where l.kind in ('adjustment','other')), 0) as adjustments,
         sum(l.amount)                                                          as net
    from ledger_entries l
    join franchises f on f.id = l.franchise_id
   group by l.year, l.franchise_id, f.name;

-- The sheet's carryover chain: opening and closing balance per season, computed
-- rather than copied between tabs.
create or replace view v_accounting_balances as
  with grid as (
    select f.franchise_id, y.year
      from (select distinct franchise_id from ledger_entries) f
      cross join (select distinct year from ledger_entries) y
     where y.year >= (select min(year) from ledger_entries l where l.franchise_id = f.franchise_id)
  ),
  per as (
    select g.franchise_id, g.year, coalesce(s.net, 0) as net
      from grid g
      left join v_accounting_season s
        on s.franchise_id = g.franchise_id and s.year = g.year
  )
  select p.franchise_id,
         f.name as franchise,
         p.year,
         round(sum(p.net) over w - p.net, 2) as opening_balance,
         round(p.net, 2)                     as season_net,
         round(sum(p.net) over w, 2)         as ending_balance
    from per p
    join franchises f on f.id = p.franchise_id
  window w as (partition by p.franchise_id order by p.year
               rows between unbounded preceding and current row);

-- Where everyone stands today.
create or replace view v_accounting_current as
  select b.franchise_id, b.franchise, b.year, b.ending_balance
    from v_accounting_balances b
   where b.year = (select max(year) from ledger_entries)
   order by b.ending_balance desc;

-- Dues collection status for a season.
create or replace view v_dues_status as
  select s.year, s.franchise_id, s.franchise,
         s.dues                              as dues_charged,
         s.paid                              as paid,
         round(s.dues - s.paid, 2)           as still_due,
         case when s.dues = 0 then 'exempt'
              when s.paid >= s.dues then 'paid'
              when s.paid > 0 then 'partial'
              else 'unpaid' end              as status
    from v_accounting_season s;

-- League-wide money per season.
create or replace view v_accounting_league_totals as
  select year,
         round(sum(dues), 2)               as dues,
         round(sum(paid), 2)               as collected,
         round(sum(acq_fees + trade_fees), 2) as activity_fees,
         round(sum(weekly_prizes), 2)      as weekly_prizes,
         round(sum(playoff_prizes), 2)     as playoff_prizes,
         round(sum(side_game_entries), 2)  as side_game_entries,
         round(sum(winnings_paid), 2)      as winnings_paid,
         round(sum(net), 2)                as outstanding
    from v_accounting_season
   group by year
   order by year;

alter view v_accounting_season        set (security_invoker = on);
alter view v_accounting_balances      set (security_invoker = on);
alter view v_accounting_current       set (security_invoker = on);
alter view v_dues_status              set (security_invoker = on);
alter view v_accounting_league_totals set (security_invoker = on);

alter table franchise_aliases enable row level security;
alter table league_fees       enable row level security;
drop policy if exists "public read" on franchise_aliases;
drop policy if exists "public read" on league_fees;
create policy "public read" on franchise_aliases for select to anon, authenticated using (true);
create policy "public read" on league_fees       for select to anon, authenticated using (true);

commit;
