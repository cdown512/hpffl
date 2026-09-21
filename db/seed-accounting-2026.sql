-- HPFFL Archives — 2026 accounting ledger
-- Transcribed from the "2026" tab of the accounting sheet and reconciled against
-- its own TOTALS row (2025 ending -2,336 / payments 2,630 / ACQ 15 /
-- weekly prizes 100 / balance -551 all agree).
--
-- Run AFTER accounting-migration.sql (it needs franchise_by_alias and the
-- widened kind list). Safe to re-run: it clears 2026 first.
--
-- Sign convention: positive increases what the franchise owes the league.
-- The Paranoid Androids carry no dues row — commissioner exemption.

begin;

-- 2026 does not exist in league_seasons yet; the ledger references it.
insert into league_seasons (year, era, teams, games, note)
values (2026, 'espn', 16, null, null)
on conflict (year) do update set teams = excluded.teams;

delete from ledger_entries where year = 2026 and source = 'sheet-2026';

insert into ledger_entries (year, franchise_id, kind, amount, source)
select 2026, franchise_by_alias(v.team), v.kind, v.amount, 'sheet-2026'
  from (values
  ('Paranoid Androids', 'carryover', -359.00),
  ('Paranoid Androids', 'acq_fee', 3.00),
  ('Dark Horse', 'carryover', -161.00),
  ('Dark Horse', 'dues', 300.00),
  ('Dark Horse', 'payment', -139.00),
  ('Dark Horse', 'acq_fee', 3.00),
  ('CPTX Predator', 'carryover', -202.00),
  ('CPTX Predator', 'dues', 300.00),
  ('CPTX Predator', 'payment', -98.00),
  ('CPTX Predator', 'weekly_prize', -50.00),
  ('Thunder Cunt', 'carryover', -48.00),
  ('Thunder Cunt', 'dues', 300.00),
  ('Thunder Cunt', 'payment', -252.00),
  ('Thunder Cunt', 'weekly_prize', -50.00),
  ('Dallas Plowgirls', 'carryover', -300.00),
  ('Dallas Plowgirls', 'dues', 300.00),
  ('Nyte Byrd', 'carryover', -126.00),
  ('Nyte Byrd', 'dues', 300.00),
  ('Nyte Byrd', 'payment', -174.00),
  ('Bird of Flame', 'carryover', -30.00),
  ('Bird of Flame', 'dues', 300.00),
  ('Bird of Flame', 'payment', -270.00),
  ('Bird of Flame', 'acq_fee', 3.00),
  ('War Pigs', 'carryover', -29.00),
  ('War Pigs', 'dues', 300.00),
  ('War Pigs', 'payment', -271.00),
  ('Eight Ball', 'carryover', -96.00),
  ('Eight Ball', 'dues', 300.00),
  ('Eight Ball', 'payment', -204.00),
  ('Franco''s Fur Coats', 'carryover', -73.00),
  ('Franco''s Fur Coats', 'dues', 300.00),
  ('Franco''s Fur Coats', 'payment', -227.00),
  ('Train Wreck', 'carryover', 28.00),
  ('Train Wreck', 'dues', 300.00),
  ('Train Wreck', 'payment', -328.00),
  ('The Unforgiven', 'carryover', -228.00),
  ('The Unforgiven', 'dues', 300.00),
  ('The Unforgiven', 'payment', -72.00),
  ('The Unforgiven', 'acq_fee', 3.00),
  ('Reservoir Dogs', 'carryover', -3.00),
  ('Reservoir Dogs', 'dues', 300.00),
  ('Reservoir Dogs', 'payment', -297.00),
  ('Peace Pipes', 'carryover', -2.00),
  ('Peace Pipes', 'dues', 300.00),
  ('Peace Pipes', 'payment', -298.00),
  ('Greatest Show on Paper', 'carryover', -354.00),
  ('Greatest Show on Paper', 'dues', 300.00),
  ('Greatest Show on Paper', 'acq_fee', 3.00),
  ('Grim Outlook', 'carryover', -353.00),
  ('Grim Outlook', 'dues', 300.00)
  ) as v(team, kind, amount);

-- Fail loudly rather than silently dropping a team whose name did not resolve.
do $$
declare n int;
begin
  select count(*) into n from ledger_entries where year = 2026 and franchise_id is null;
  if n > 0 then raise exception 'Unresolved franchise names in the 2026 ledger: % rows', n; end if;
end $$;

commit;

-- ─────────────── reconciliation: every row should read 'ok' ───────────────
select b.franchise,
       b.ending_balance,
       e.expected,
       case when b.ending_balance = e.expected then 'ok' else 'MISMATCH' end as verdict
  from v_accounting_balances b
  join (values
    ('Paranoid Androids', -356.00),
    ('Dark Horse', 3.00),
    ('CPTX Predator', -50.00),
    ('Thunder Cunt', -50.00),
    ('Dallas Plowgirls', 0.00),
    ('Nyte Byrd', 0.00),
    ('Bird of Flame', 3.00),
    ('War Pigs', 0.00),
    ('Eight Ball', 0.00),
    ('Franco''s Fur Coats', 0.00),
    ('Train Wreck', 0.00),
    ('The Unforgiven', 3.00),
    ('Reservoir Dogs', 0.00),
    ('Peace Pipes', 0.00),
    ('Greatest Show on Paper', -51.00),
    ('Grim Outlook', -53.00)
  ) as e(team, expected) on franchise_by_alias(e.team) = b.franchise_id
 where b.year = 2026
 order by verdict desc, b.franchise;
